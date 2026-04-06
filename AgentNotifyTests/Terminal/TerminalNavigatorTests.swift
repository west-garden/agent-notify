import XCTest
@testable import AgentNotify

private final class CapturingAppleScriptRunner: AppleScriptRunning {
    var scripts: [(String, OsaLanguage)] = []

    func run(_ script: String, language: OsaLanguage) throws -> String {
        scripts.append((script, language))
        return ""
    }
}

final class TerminalNavigatorTests: XCTestCase {
    func test_focusBuildsAppleTerminalSelectionScript() throws {
        let runner = CapturingAppleScriptRunner()
        let navigator = TerminalNavigator(runner: runner)

        try navigator.focus(windowID: 12, tabIndex: 3)

        XCTAssertEqual(runner.scripts.count, 1)
        XCTAssertEqual(runner.scripts.first?.1, .appleScript)
        XCTAssertTrue(runner.scripts.first?.0.contains("window whose id is 12") == true)
        XCTAssertTrue(runner.scripts.first?.0.contains("selected tab of frontWindow to tab 3") == true)
    }
}
