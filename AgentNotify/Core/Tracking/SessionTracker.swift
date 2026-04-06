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
        let id = "\(snapshot.windowID):\(snapshot.tabIndex):\(snapshot.tty)"
        let explicitAgent = AgentKind(processes: snapshot.processes)

        if explicitAgent == nil, isPlainShell(snapshot.processes) {
            sessions.removeValue(forKey: id)
            return nil
        }

        guard let effectiveAgent = explicitAgent ?? sessions[id]?.agent else {
            return nil
        }

        let stored = sessions[id]
        let previous: TrackedSession
        if let stored, let explicitAgent, explicitAgent != stored.agent {
            previous = TrackedSession(
                id: id,
                agent: explicitAgent,
                state: .unknown,
                lastFingerprint: stored.lastFingerprint,
                lastChangeAt: now,
                hasNotifiedForCurrentWait: false,
                windowID: snapshot.windowID,
                tabIndex: snapshot.tabIndex,
                tty: snapshot.tty
            )
        } else {
            previous = stored ?? TrackedSession(
                id: id,
                agent: effectiveAgent,
                state: .unknown,
                lastFingerprint: "",
                lastChangeAt: now,
                hasNotifiedForCurrentWait: false,
                windowID: snapshot.windowID,
                tabIndex: snapshot.tabIndex,
                tty: snapshot.tty
            )
        }

        let decision = detector.evaluate(previous: previous, snapshot: snapshot, now: now)
        let notified = decision.shouldNotify || (decision.state == .needsInput && previous.hasNotifiedForCurrentWait)
        let updated = previous.updating(
            snapshot: snapshot,
            agent: explicitAgent,
            state: decision.state,
            fingerprint: decision.fingerprint,
            now: now,
            markNotified: notified
        )
        sessions[id] = updated

        let notification = decision.shouldNotify
            ? NotificationPayload(sessionID: id, agent: effectiveAgent, tty: snapshot.tty)
            : nil

        return SessionEvent(session: updated, notification: notification)
    }

    func finishCycle(activeSessionIDs: Set<String>) {
        sessions = sessions.filter { activeSessionIDs.contains($0.key) }
    }

    func rearmNotifications(for sessionIDs: Set<String>) {
        for sessionID in sessionIDs {
            guard let session = sessions[sessionID], session.state == .needsInput else {
                continue
            }

            sessions[sessionID] = TrackedSession(
                id: session.id,
                agent: session.agent,
                state: session.state,
                lastFingerprint: session.lastFingerprint,
                lastChangeAt: session.lastChangeAt,
                hasNotifiedForCurrentWait: false,
                windowID: session.windowID,
                tabIndex: session.tabIndex,
                tty: session.tty
            )
        }
    }

    func activeSessions() -> [TrackedSession] {
        sessions.values.sorted {
            if $0.windowID != $1.windowID {
                return $0.windowID < $1.windowID
            }

            if $0.tabIndex != $1.tabIndex {
                return $0.tabIndex < $1.tabIndex
            }

            return $0.tty < $1.tty
        }
    }

    private func isPlainShell(_ processes: [String]) -> Bool {
        guard !processes.isEmpty else {
            return true
        }

        return processes.allSatisfy { isShellProcess($0) }
    }

    private func isShellProcess(_ process: String) -> Bool {
        switch process
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingPrefix("-") {
        case "login", "zsh", "bash", "sh", "fish", "pwsh", "csh", "tcsh", "ksh":
            return true
        default:
            return false
        }
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

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        guard self.first == prefix else {
            return self
        }
        return String(dropFirst())
    }
}
