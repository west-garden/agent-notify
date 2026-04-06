import Foundation

struct NotificationPayload {
    let sessionID: String
    let agent: AgentKind
    let tty: String

    var title: String {
        switch agent {
        case .claude:
            return String(localized: "Claude Waiting")
        case .codex:
            return String(localized: "Codex Waiting")
        }
    }

    var body: String {
        String(localized: "Terminal tab on \(tty) is waiting for your input.")
    }
}
