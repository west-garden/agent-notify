import Foundation

struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool
}
