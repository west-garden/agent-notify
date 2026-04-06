import Foundation

protocol TerminalPolling {
    func poll() throws -> [TerminalTabSnapshot]
}

extension TerminalPoller: TerminalPolling {}

final class MonitorController {
    private struct QueuedNotification {
        let payload: NotificationPayload
    }

    private struct ControllerState {
        var isRunning = false
        var isMuted = false
        var controlGeneration: UInt64 = 0
        var trackedSessionCount = 0
        var waitingSessionCount = 0
        var tabs: [MonitoredTabState] = []
        var lastTriggeredTTY: String?
        var lastErrorDescription: String?
    }

    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying
    private let settingsStore: MonitorSettingsStoring
    private let workerQueue = DispatchQueue(label: "com.westgarden.AgentNotify.MonitorController")
    private let stateLock = NSLock()

    private var queuedNotifications: [String: QueuedNotification] = [:]
    private var queuedNotificationOrder: [String] = []
    private var cooldownExpiresAt: Date?

    private var state = ControllerState()

    var isRunning: Bool {
        withState { $0.isRunning }
    }

    var isMuted: Bool {
        withState { $0.isMuted }
    }

    var trackedSessionCount: Int {
        withState { $0.trackedSessionCount }
    }

    var waitingSessionCount: Int {
        withState { $0.waitingSessionCount }
    }

    var tabs: [MonitoredTabState] {
        withState { $0.tabs }
    }

    var lastTriggeredTTY: String? {
        withState { $0.lastTriggeredTTY }
    }

    var lastErrorDescription: String? {
        withState { $0.lastErrorDescription }
    }

    var onStatusChange: ((MonitorStatus) -> Void)?

    private var timer: Timer?

    init(
        poller: TerminalPolling,
        tracker: SessionTracker,
        notifier: Notifying,
        soundPlayer: SoundPlaying,
        settingsStore: MonitorSettingsStoring = MonitorSettingsStore()
    ) {
        self.poller = poller
        self.tracker = tracker
        self.notifier = notifier
        self.soundPlayer = soundPlayer
        self.settingsStore = settingsStore
        updateState { state in
            state.isMuted = settingsStore.isMuted
        }
    }

    deinit {
        stop()
    }

    func start(pollInterval: TimeInterval) {
        guard !isRunning else {
            return
        }

        updateState { $0.isRunning = true }
        publishStatus()

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.scheduleTick(now: .now)
        }
        timer.tolerance = min(0.5, pollInterval / 4)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        guard isRunning else {
            return
        }

        updateState { state in
            state.isRunning = false
            state.controlGeneration &+= 1
        }
        publishStatus()
    }

    func setMuted(_ muted: Bool) {
        let changed = updateState { state in
            guard state.isMuted != muted else {
                return false
            }

            state.isMuted = muted
            state.controlGeneration &+= 1

            if muted {
                state.tabs = state.tabs.map {
                    MonitoredTabState(
                        id: $0.id,
                        windowID: $0.windowID,
                        tabIndex: $0.tabIndex,
                        agent: $0.agent,
                        state: $0.state,
                        isCoolingDown: false
                    )
                }
            }

            return true
        }

        guard changed else {
            return
        }

        settingsStore.isMuted = muted
        publishStatus()

        if muted {
            workerQueue.async { [weak self] in
                self?.clearMutedNotifications()
            }
        }
    }

    func setAlertCooldown(_ cooldown: TimeInterval) {
        settingsStore.alertCooldown = cooldown
    }

    func playTestSound() {
        soundPlayer.playCowSound()
    }

    func tick(now: Date = .now) {
        let controlGeneration = currentControlGeneration()
        workerQueue.sync {
            performTick(now: now, controlGeneration: controlGeneration)
        }
    }

    private func scheduleTick(now: Date) {
        let controlGeneration = currentControlGeneration()
        workerQueue.async { [weak self] in
            self?.performTick(now: now, controlGeneration: controlGeneration)
        }
    }

    private func performTick(now: Date, controlGeneration: UInt64) {
        do {
            let snapshots = try poller.poll()
            var activeSessionIDs = Set<String>()
            var events: [SessionEvent] = []

            for snapshot in snapshots {
                guard let event = tracker.process(snapshot: snapshot, now: now) else {
                    continue
                }

                activeSessionIDs.insert(event.session.id)
                events.append(event)
            }

            tracker.finishCycle(activeSessionIDs: activeSessionIDs)

            let activeSessions = tracker.activeSessions()
            let activeSessionsByID = Dictionary(uniqueKeysWithValues: activeSessions.map { ($0.id, $0) })

            reconcileNotifications(
                now: now,
                activeSessionsByID: activeSessionsByID,
                events: events,
                controlGeneration: controlGeneration
            )
            updateTrackedState(from: activeSessions)
        } catch {
            updateState { state in
                state.trackedSessionCount = 0
                state.waitingSessionCount = 0
                state.tabs = []
                state.lastErrorDescription = error.localizedDescription
            }
        }

        publishStatus()
    }

    private func reconcileNotifications(
        now: Date,
        activeSessionsByID: [String: TrackedSession],
        events: [SessionEvent],
        controlGeneration: UInt64
    ) {
        pruneQueuedNotifications(activeSessionsByID: activeSessionsByID)

        if !isMuted {
            flushQueuedNotification(
                now: now,
                activeSessionsByID: activeSessionsByID,
                controlGeneration: controlGeneration
            )
        }

        for event in events {
            guard let payload = event.notification else {
                continue
            }

            handleNotification(
                payload,
                now: now,
                activeSessionsByID: activeSessionsByID,
                controlGeneration: controlGeneration
            )
        }
    }

    private func handleNotification(
        _ payload: NotificationPayload,
        now: Date,
        activeSessionsByID: [String: TrackedSession],
        controlGeneration: UInt64
    ) {
        guard activeSessionsByID[payload.sessionID]?.state == .needsInput else {
            return
        }

        if !isMuted && canSendNotification(now: now) {
            sendNotification(payload, now: now, controlGeneration: controlGeneration)
            return
        }

        queueNotification(payload)
    }

    private func flushQueuedNotification(
        now: Date,
        activeSessionsByID: [String: TrackedSession],
        controlGeneration: UInt64
    ) {
        guard !isMuted else {
            return
        }

        guard canSendNotification(now: now) else {
            return
        }

        while let sessionID = queuedNotificationOrder.first {
            queuedNotificationOrder.removeFirst()

            guard let queued = queuedNotifications.removeValue(forKey: sessionID) else {
                continue
            }

            guard activeSessionsByID[sessionID]?.state == .needsInput else {
                continue
            }

            sendNotification(queued.payload, now: now, controlGeneration: controlGeneration)
            return
        }
    }

    private func pruneQueuedNotifications(activeSessionsByID: [String: TrackedSession]) {
        guard !queuedNotificationOrder.isEmpty else {
            return
        }

        var prunedOrder: [String] = []
        var prunedNotifications: [String: QueuedNotification] = [:]

        for sessionID in queuedNotificationOrder {
            guard let queued = queuedNotifications[sessionID],
                  let session = activeSessionsByID[sessionID],
                  session.state == .needsInput else {
                continue
            }

            prunedOrder.append(sessionID)
            prunedNotifications[sessionID] = queued
        }

        queuedNotificationOrder = prunedOrder
        queuedNotifications = prunedNotifications
    }

    private func clearMutedNotifications() {
        let activeSessionIDs = Set(queuedNotificationOrder)
        queuedNotifications.removeAll()
        queuedNotificationOrder.removeAll()
        tracker.rearmNotifications(for: activeSessionIDs)
        updateTrackedState(from: tracker.activeSessions())
        publishStatus()
    }

    private func queueNotification(_ payload: NotificationPayload) {
        if queuedNotifications[payload.sessionID] == nil {
            queuedNotificationOrder.append(payload.sessionID)
        }

        queuedNotifications[payload.sessionID] = QueuedNotification(payload: payload)
    }

    private func canSendNotification(now: Date) -> Bool {
        guard let cooldownExpiresAt else {
            return true
        }

        return now >= cooldownExpiresAt
    }

    private func sendNotification(_ payload: NotificationPayload, now: Date, controlGeneration: UInt64) {
        guard currentControlGeneration() == controlGeneration else {
            return
        }

        guard !isMuted else {
            return
        }

        notifier.notify(payload)
        soundPlayer.playCowSound()
        updateState { state in
            state.lastTriggeredTTY = payload.tty
        }
        cooldownExpiresAt = now.addingTimeInterval(settingsStore.alertCooldown)
    }

    private func updateTrackedState(from activeSessions: [TrackedSession]) {
        updateState { state in
            state.trackedSessionCount = activeSessions.count
            state.waitingSessionCount = activeSessions.filter { $0.state == .needsInput }.count
            state.tabs = activeSessions.map { session in
                MonitoredTabState(
                    id: session.id,
                    windowID: session.windowID,
                    tabIndex: session.tabIndex,
                    agent: session.agent,
                    state: session.state,
                    isCoolingDown: queuedNotifications[session.id] != nil
                )
            }
            state.lastErrorDescription = nil
        }
    }

    private func publishStatus() {
        let snapshot = withState { $0 }
        let status = MonitorStatus(
            isRunning: snapshot.isRunning,
            isMuted: snapshot.isMuted,
            trackedSessionCount: snapshot.trackedSessionCount,
            waitingSessionCount: snapshot.waitingSessionCount,
            lastTriggeredTTY: snapshot.lastTriggeredTTY,
            lastErrorDescription: snapshot.lastErrorDescription,
            tabs: snapshot.tabs
        )
        let callback = onStatusChange

        if Thread.isMainThread {
            callback?(status)
            return
        }

        DispatchQueue.main.async {
            callback?(status)
        }
    }

    private func withState<T>(_ body: (ControllerState) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(state)
    }

    private func currentControlGeneration() -> UInt64 {
        withState { $0.controlGeneration }
    }

    @discardableResult
    private func updateState<T>(_ body: (inout ControllerState) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&state)
    }
}
