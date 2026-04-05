import Foundation

struct DetectionDecision {
    let state: SessionState
    let shouldNotify: Bool
    let fingerprint: String
}

struct NeedsInputDetector {
    let quietPeriod: TimeInterval
    private let normalizer = TextNormalizer()

    func evaluate(
        previous: TrackedSession?,
        snapshot: TerminalTabSnapshot,
        now: Date
    ) -> DetectionDecision {
        let fingerprint = normalizer.normalize(snapshot.visibleText)
        let agent = resolvedAgent(previous: previous, snapshot: snapshot)

        guard let previous, let agent else {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        if previous.lastFingerprint != fingerprint {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        let matcher: IdlePatternMatcher = matcher(for: agent)
        let shouldWait = quietFor >= quietPeriod && matcher.matchesInputReady(fingerprint) && !matcher.matchesActiveWork(fingerprint)
        return DetectionDecision(
            state: shouldWait ? .needsInput : .running,
            shouldNotify: shouldWait && !previous.hasNotifiedForCurrentWait,
            fingerprint: fingerprint
        )
    }

    private func resolvedAgent(previous: TrackedSession?, snapshot: TerminalTabSnapshot) -> AgentKind? {
        if snapshot.processes.contains("claude") {
            return .claude
        }

        if snapshot.processes.contains("codex") {
            return .codex
        }

        if let previous, !snapshotProcessesClearlyShowPlainShell(snapshot.processes) {
            return previous.agent
        }

        return nil
    }

    private func snapshotProcessesClearlyShowPlainShell(_ processes: [String]) -> Bool {
        guard !processes.isEmpty else {
            return true
        }

        return processes.allSatisfy { isShellProcess($0) }
    }

    private func isShellProcess(_ process: String) -> Bool {
        switch process.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingPrefix("-") {
        case "login", "zsh", "bash", "sh", "fish", "pwsh", "csh", "tcsh", "ksh":
            return true
        default:
            return false
        }
    }

    private func matcher(for agent: AgentKind) -> IdlePatternMatcher {
        switch agent {
        case .claude:
            return ClaudeMatcher()
        case .codex:
            return CodexMatcher()
        }
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
