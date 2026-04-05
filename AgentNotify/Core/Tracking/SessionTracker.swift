import Foundation

struct SessionEvent {
    let session: TrackedSession
    let notification: NotificationPayload?
}

final class SessionTracker {
    private let detector: NeedsInputDetector
    private var sessions: [String: TrackedSession] = [:]

    init(detector: NeedsInputDetector) {
        self.detector = detector
    }

    func process(snapshot: TerminalTabSnapshot, now: Date) -> SessionEvent? {
        guard let agent = AgentKind(processes: snapshot.processes) else {
            return nil
        }

        let id = "\(snapshot.windowID):\(snapshot.tabIndex):\(snapshot.tty)"
        let previous = sessions[id] ?? TrackedSession(
            id: id,
            agent: agent,
            state: .unknown,
            lastFingerprint: "",
            lastChangeAt: now,
            hasNotifiedForCurrentWait: false
        )

        let decision = detector.evaluate(previous: previous, snapshot: snapshot, now: now)
        let notified = decision.shouldNotify || (decision.state == .needsInput && previous.hasNotifiedForCurrentWait)
        let updated = previous.updating(
            state: decision.state,
            fingerprint: decision.fingerprint,
            now: now,
            markNotified: notified
        )
        sessions[id] = updated

        let notification = decision.shouldNotify
            ? NotificationPayload(sessionID: id, agent: agent, tty: snapshot.tty)
            : nil

        return SessionEvent(session: updated, notification: notification)
    }
}

extension AgentKind {
    init?(processes: [String]) {
        if processes.contains("claude") {
            self = .claude
            return
        }

        if processes.contains("codex") {
            self = .codex
            return
        }

        return nil
    }
}
