import Foundation

struct MonitoredTabState: Equatable {
    let id: String
    let windowID: Int
    let tabIndex: Int
    let agent: AgentKind
    let state: SessionState
    let isCoolingDown: Bool

    var title: String {
        String(localized: "Window \(windowID) / Tab \(tabIndex)")
    }

    var isWaiting: Bool {
        state == .needsInput
    }
}

struct MonitorStatus: Equatable {
    let isRunning: Bool
    let isMuted: Bool
    let trackedSessionCount: Int
    let waitingSessionCount: Int
    let lastTriggeredTTY: String?
    let lastErrorDescription: String?
    let tabs: [MonitoredTabState]
}
