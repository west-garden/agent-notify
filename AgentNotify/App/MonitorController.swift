import Foundation

protocol TerminalPolling {
    func poll() throws -> [TerminalTabSnapshot]
}

extension TerminalPoller: TerminalPolling {}

final class MonitorController {
    private struct QueuedNotification {
        let payload: NotificationPayload
    }

    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying
    private let settingsStore: MonitorSettingsStoring
    private let workerQueue = DispatchQueue(label: "com.westgarden.AgentNotify.MonitorController")

    private var queuedNotifications: [String: QueuedNotification] = [:]
    private var queuedNotificationOrder: [String] = []
    private var cooldownExpiresAt: Date?

    private(set) var isRunning = false
    private(set) var isMuted: Bool
    private(set) var trackedSessionCount = 0
    private(set) var waitingSessionCount = 0
    private(set) var tabs: [MonitoredTabState] = []
    private(set) var lastTriggeredTTY: String?
    private(set) var lastErrorDescription: String?

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
        self.isMuted = settingsStore.isMuted
    }

    deinit {
        stop()
    }

    func start(pollInterval: TimeInterval) {
        guard !isRunning else {
            return
        }

        workerQueue.sync {
            isRunning = true
        }
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

        workerQueue.sync {
            isRunning = false
        }
        publishStatus()
    }

    func setMuted(_ muted: Bool) {
        workerQueue.sync {
            guard isMuted != muted else {
                return
            }

            isMuted = muted
            settingsStore.isMuted = muted

            if muted {
                let clearedSessionIDs = Set(queuedNotificationOrder)
                clearQueuedNotifications()
                tracker.rearmNotifications(for: clearedSessionIDs)
                updateTrackedState(from: tracker.activeSessions())
                cooldownExpiresAt = nil
            }

            publishStatus()
        }
    }

    func setAlertCooldown(_ cooldown: TimeInterval) {
        workerQueue.sync {
            settingsStore.alertCooldown = cooldown
        }
    }

    func playTestSound() {
        soundPlayer.playCowSound()
    }

    func tick(now: Date = .now) {
        workerQueue.sync {
            performTick(now: now)
        }
    }

    private func scheduleTick(now: Date) {
        workerQueue.async { [weak self] in
            self?.performTick(now: now)
        }
    }

    private func performTick(now: Date) {
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

            lastErrorDescription = nil
            reconcileNotifications(now: now, activeSessionsByID: activeSessionsByID, events: events)
            updateTrackedState(from: activeSessions)
        } catch {
            trackedSessionCount = 0
            waitingSessionCount = 0
            tabs = []
            lastErrorDescription = error.localizedDescription
        }

        publishStatus()
    }

    private func reconcileNotifications(
        now: Date,
        activeSessionsByID: [String: TrackedSession],
        events: [SessionEvent]
    ) {
        pruneQueuedNotifications(activeSessionsByID: activeSessionsByID)

        if !isMuted {
            flushQueuedNotification(now: now, activeSessionsByID: activeSessionsByID)
        }

        for event in events {
            guard let payload = event.notification else {
                continue
            }

            handleNotification(payload, now: now, activeSessionsByID: activeSessionsByID)
        }
    }

    private func handleNotification(
        _ payload: NotificationPayload,
        now: Date,
        activeSessionsByID: [String: TrackedSession]
    ) {
        guard activeSessionsByID[payload.sessionID]?.state == .needsInput else {
            return
        }

        if !isMuted && canSendNotification(now: now) {
            sendNotification(payload, now: now)
            return
        }

        queueNotification(payload)
    }

    private func flushQueuedNotification(
        now: Date,
        activeSessionsByID: [String: TrackedSession]
    ) {
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

            sendNotification(queued.payload, now: now)
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

    private func clearQueuedNotifications() {
        queuedNotifications.removeAll()
        queuedNotificationOrder.removeAll()
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

    private func sendNotification(_ payload: NotificationPayload, now: Date) {
        notifier.notify(payload)
        soundPlayer.playCowSound()
        lastTriggeredTTY = payload.tty
        cooldownExpiresAt = now.addingTimeInterval(settingsStore.alertCooldown)
    }

    private func updateTrackedState(from activeSessions: [TrackedSession]) {
        trackedSessionCount = activeSessions.count
        waitingSessionCount = activeSessions.filter { $0.state == .needsInput }.count
        tabs = activeSessions.map { session in
            MonitoredTabState(
                id: session.id,
                windowID: session.windowID,
                tabIndex: session.tabIndex,
                agent: session.agent,
                state: session.state,
                isCoolingDown: queuedNotifications[session.id] != nil
            )
        }
    }

    private func publishStatus() {
        let status = MonitorStatus(
            isRunning: isRunning,
            isMuted: isMuted,
            trackedSessionCount: trackedSessionCount,
            waitingSessionCount: waitingSessionCount,
            lastTriggeredTTY: lastTriggeredTTY,
            lastErrorDescription: lastErrorDescription,
            tabs: tabs
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
}
