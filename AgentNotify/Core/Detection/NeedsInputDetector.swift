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

        let matcher: IdlePatternMatcher = snapshot.processes.contains("claude") ? ClaudeMatcher() : CodexMatcher()

        if previous.lastFingerprint != fingerprint {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        let shouldWait = quietFor >= quietPeriod && matcher.matchesInputReady(fingerprint) && !matcher.matchesActiveWork(fingerprint)
        return DetectionDecision(
            state: shouldWait ? .needsInput : .running,
            shouldNotify: shouldWait && !previous.hasNotifiedForCurrentWait,
            fingerprint: fingerprint
        )
    }
}
