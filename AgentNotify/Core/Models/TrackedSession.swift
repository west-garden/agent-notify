import Foundation

struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
    let lastStabilityFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool
    let windowID: Int
    let tabIndex: Int
    let tty: String

    init(
        id: String,
        agent: AgentKind,
        state: SessionState,
        lastFingerprint: String,
        lastStabilityFingerprint: String? = nil,
        lastChangeAt: Date,
        hasNotifiedForCurrentWait: Bool,
        windowID: Int,
        tabIndex: Int,
        tty: String
    ) {
        let fingerprinting = StatusFingerprinting()

        self.id = id
        self.agent = agent
        self.state = state
        self.lastFingerprint = lastFingerprint
        self.lastStabilityFingerprint = lastStabilityFingerprint
            ?? fingerprinting.stabilityFingerprint(from: fingerprinting.statusRegion(from: lastFingerprint))
        self.lastChangeAt = lastChangeAt
        self.hasNotifiedForCurrentWait = hasNotifiedForCurrentWait
        self.windowID = windowID
        self.tabIndex = tabIndex
        self.tty = tty
    }

    var locationLabel: String {
        String(localized: "Window \(windowID) / Tab \(tabIndex)")
    }

    func updating(
        snapshot: TerminalTabSnapshot,
        agent: AgentKind? = nil,
        state: SessionState,
        fingerprint: String,
        stabilityFingerprint: String,
        now: Date,
        markNotified: Bool
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            agent: agent ?? self.agent,
            state: state,
            lastFingerprint: fingerprint,
            lastStabilityFingerprint: stabilityFingerprint,
            lastChangeAt: lastStabilityFingerprint == stabilityFingerprint ? lastChangeAt : now,
            hasNotifiedForCurrentWait: markNotified,
            windowID: snapshot.windowID,
            tabIndex: snapshot.tabIndex,
            tty: snapshot.tty
        )
    }
}
