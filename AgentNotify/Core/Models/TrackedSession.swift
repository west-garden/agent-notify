import Foundation

struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
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
        lastChangeAt: Date,
        hasNotifiedForCurrentWait: Bool,
        windowID: Int,
        tabIndex: Int,
        tty: String
    ) {
        self.id = id
        self.agent = agent
        self.state = state
        self.lastFingerprint = lastFingerprint
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
        now: Date,
        markNotified: Bool
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            agent: agent ?? self.agent,
            state: state,
            lastFingerprint: fingerprint,
            lastChangeAt: lastFingerprint == fingerprint ? lastChangeAt : now,
            hasNotifiedForCurrentWait: markNotified,
            windowID: snapshot.windowID,
            tabIndex: snapshot.tabIndex,
            tty: snapshot.tty
        )
    }
}
