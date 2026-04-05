import Foundation

struct NotificationPayload {
    let sessionID: String
    let agent: AgentKind
    let tty: String

    var title: String {
        switch agent {
        case .claude:
            return "Claude Waiting"
        case .codex:
            return "Codex Waiting"
        }
    }

    var body: String {
        "Terminal tab on \(tty) is waiting for your input."
    }
}
