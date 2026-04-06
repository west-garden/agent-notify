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
        var queuedNotifications: [String: QueuedNotification] = [:]
        var queuedNotificationOrder: [String] = []
        var cooldownExpiresAt: Date?
    }

    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying
    private let settingsStore: MonitorSettingsStoring
    private let workerQueue = DispatchQueue(label: "com.westgarden.AgentNotify.MonitorController")
    private let stateLock = NSLock()

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

        let clearedSessionIDs = updateState { state in
            state.isRunning = false
            state.controlGeneration &+= 1
            return clearPendingNotifications(in: &state, resetCooldown: true)
        }
        publishStatus()

        guard !clearedSessionIDs.isEmpty else {
            return
        }

        rearmQueuedSessions(clearedSessionIDs)
    }

    func setMuted(_ muted: Bool) {
        let clearedSessionIDs = updateState { state -> Set<String>? in
            guard state.isMuted != muted else {
                return nil
            }

            state.isMuted = muted
            state.controlGeneration &+= 1

            if muted {
                return clearPendingNotifications(in: &state, resetCooldown: true)
            }

            return []
        }

        guard let clearedSessionIDs else {
            return
        }

        settingsStore.isMuted = muted
        publishStatus()

        if muted {
            rearmQueuedSessions(clearedSessionIDs)
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
            guard shouldProcessTick(controlGeneration: controlGeneration) else {
                return
            }

            var activeSessionIDs = Set<String>()
            var events: [SessionEvent] = []

            for snapshot in snapshots {
                guard shouldProcessTick(controlGeneration: controlGeneration) else {
                    return
                }

                guard let event = tracker.process(snapshot: snapshot, now: now) else {
                    continue
                }

                activeSessionIDs.insert(event.session.id)
                events.append(event)
            }

            tracker.finishCycle(activeSessionIDs: activeSessionIDs)

            guard shouldProcessTick(controlGeneration: controlGeneration) else {
                return
            }

            let activeSessions = tracker.activeSessions()
            let activeSessionsByID = Dictionary(uniqueKeysWithValues: activeSessions.map { ($0.id, $0) })

            reconcileNotifications(
                now: now,
                activeSessionsByID: activeSessionsByID,
                events: events,
                controlGeneration: controlGeneration
            )
            updateTrackedState(from: activeSessions, controlGeneration: controlGeneration)
        } catch {
            guard shouldProcessTick(controlGeneration: controlGeneration) else {
                return
            }

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
        guard shouldProcessTick(controlGeneration: controlGeneration) else {
            return
        }

        pruneQueuedNotifications(
            activeSessionsByID: activeSessionsByID,
            controlGeneration: controlGeneration
        )

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
        guard shouldProcessTick(controlGeneration: controlGeneration) else {
            return
        }

        guard activeSessionsByID[payload.sessionID]?.state == .needsInput else {
            return
        }

        if !isMuted && canSendNotification(now: now) {
            sendNotification(payload, now: now, controlGeneration: controlGeneration)
            return
        }

        queueNotification(payload, controlGeneration: controlGeneration)
    }

    private func flushQueuedNotification(
        now: Date,
        activeSessionsByID: [String: TrackedSession],
        controlGeneration: UInt64
    ) {
        guard shouldProcessTick(controlGeneration: controlGeneration) else {
            return
        }

        guard !isMuted else {
            return
        }

        guard canSendNotification(now: now) else {
            return
        }

        while let queued = dequeueQueuedNotification(controlGeneration: controlGeneration) {
            let sessionID = queued.payload.sessionID

            guard activeSessionsByID[sessionID]?.state == .needsInput else {
                continue
            }

            sendNotification(queued.payload, now: now, controlGeneration: controlGeneration)
            return
        }
    }

    private func pruneQueuedNotifications(
        activeSessionsByID: [String: TrackedSession],
        controlGeneration: UInt64
    ) {
        updateState { state in
            guard state.controlGeneration == controlGeneration, !state.queuedNotificationOrder.isEmpty else {
                return
            }

            var prunedOrder: [String] = []
            var prunedNotifications: [String: QueuedNotification] = [:]

            for sessionID in state.queuedNotificationOrder {
                guard let queued = state.queuedNotifications[sessionID],
                      let session = activeSessionsByID[sessionID],
                      session.state == .needsInput else {
                    continue
                }

                prunedOrder.append(sessionID)
                prunedNotifications[sessionID] = queued
            }

            state.queuedNotificationOrder = prunedOrder
            state.queuedNotifications = prunedNotifications
        }
    }

    private func queueNotification(_ payload: NotificationPayload, controlGeneration: UInt64) {
        updateState { state in
            guard state.controlGeneration == controlGeneration else {
                return
            }

            if state.queuedNotifications[payload.sessionID] == nil {
                state.queuedNotificationOrder.append(payload.sessionID)
            }

            state.queuedNotifications[payload.sessionID] = QueuedNotification(payload: payload)
        }
    }

    private func canSendNotification(now: Date) -> Bool {
        withState { state in
            guard let cooldownExpiresAt = state.cooldownExpiresAt else {
                return true
            }

            return now >= cooldownExpiresAt
        }
    }

    private func sendNotification(_ payload: NotificationPayload, now: Date, controlGeneration: UInt64) {
        let didSend = updateState { state in
            guard state.controlGeneration == controlGeneration, !state.isMuted else {
                return false
            }

            notifier.notify(payload)
            soundPlayer.playCowSound()
            state.lastTriggeredTTY = payload.tty
            state.cooldownExpiresAt = now.addingTimeInterval(settingsStore.alertCooldown)
            return true
        }

        guard didSend else {
            return
        }
    }

    private func updateTrackedState(from activeSessions: [TrackedSession], controlGeneration: UInt64) {
        updateState { state in
            guard state.controlGeneration == controlGeneration else {
                return
            }

            state.trackedSessionCount = activeSessions.count
            state.waitingSessionCount = activeSessions.filter { $0.state == .needsInput }.count
            state.tabs = activeSessions.map { session in
                MonitoredTabState(
                    id: session.id,
                    windowID: session.windowID,
                    tabIndex: session.tabIndex,
                    agent: session.agent,
                    state: session.state,
                    isCoolingDown: state.queuedNotifications[session.id] != nil
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

    private func shouldProcessTick(controlGeneration: UInt64) -> Bool {
        withState { state in
            state.controlGeneration == controlGeneration
        }
    }

    private func dequeueQueuedNotification(controlGeneration: UInt64) -> QueuedNotification? {
        updateState { state in
            guard state.controlGeneration == controlGeneration, !state.isMuted else {
                return nil
            }

            guard let sessionID = state.queuedNotificationOrder.first else {
                return nil
            }

            state.queuedNotificationOrder.removeFirst()
            return state.queuedNotifications.removeValue(forKey: sessionID)
        }
    }

    @discardableResult
    private func clearPendingNotifications(in state: inout ControllerState, resetCooldown: Bool) -> Set<String> {
        let sessionIDs = Set(state.queuedNotificationOrder)
        state.queuedNotifications.removeAll()
        state.queuedNotificationOrder.removeAll()
        if resetCooldown {
            state.cooldownExpiresAt = nil
        }
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
        return sessionIDs
    }

    private func rearmQueuedSessions(_ sessionIDs: Set<String>) {
        workerQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.tracker.rearmNotifications(for: sessionIDs)
            self.updateTrackedState(from: self.tracker.activeSessions(), controlGeneration: self.currentControlGeneration())
            self.publishStatus()
        }
    }

    @discardableResult
    private func updateState<T>(_ body: (inout ControllerState) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&state)
    }
}
