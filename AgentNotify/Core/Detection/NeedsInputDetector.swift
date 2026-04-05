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

        guard let previous else {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        guard let agent = resolvedAgent(previous: previous, snapshot: snapshot) else {
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
        if let previous {
            return previous.agent
        }

        if snapshot.processes.contains("claude") {
            return .claude
        }

        if snapshot.processes.contains("codex") {
            return .codex
        }

        return nil
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
