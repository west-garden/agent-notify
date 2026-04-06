import Foundation

protocol TerminalNavigating {
    func focus(windowID: Int, tabIndex: Int) throws
}

struct TerminalNavigator: TerminalNavigating {
    let runner: AppleScriptRunning

    init(runner: AppleScriptRunning = AppleScriptRunner()) {
        self.runner = runner
    }

    func focus(windowID: Int, tabIndex: Int) throws {
        let script = """
        tell application "Terminal"
            activate
            set frontWindow to first window whose id is \(windowID)
            set index of frontWindow to 1
            set selected tab of frontWindow to tab \(tabIndex) of frontWindow
        end tell
        """

        _ = try runner.run(script, language: .appleScript)
    }
}
