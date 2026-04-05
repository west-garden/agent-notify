import Foundation

struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool

    func updating(
        state: SessionState,
        fingerprint: String,
        now: Date,
        markNotified: Bool
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            agent: agent,
            state: state,
            lastFingerprint: fingerprint,
            lastChangeAt: lastFingerprint == fingerprint ? lastChangeAt : now,
            hasNotifiedForCurrentWait: markNotified
        )
    }
}
