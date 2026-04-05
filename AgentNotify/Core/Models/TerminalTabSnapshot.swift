import Foundation

struct TerminalTabSnapshot {
    let windowID: Int
    let tabIndex: Int
    let tty: String
    let processes: [String]
    let busy: Bool
    let visibleText: String
}
