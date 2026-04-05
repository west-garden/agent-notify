import Foundation

struct DetectionDecision {
    let state: SessionState
    let shouldNotify: Bool
    let fingerprint: String
}

struct NeedsInputDetector {
    let quietPeriod: TimeInterval

    func evaluate(
        previous: TrackedSession?,
        snapshot: TerminalTabSnapshot,
        now: Date
    ) -> DetectionDecision {
        let fingerprint = snapshot.visibleText

        guard let previous else {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        if previous.lastFingerprint != fingerprint {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        if quietFor < quietPeriod {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
    }
}
