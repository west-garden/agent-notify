import XCTest
@testable import AgentNotify

final class AppleScriptRunnerTests: XCTestCase {
    func test_runnerExecutesAppleScript() throws {
        let output = try AppleScriptRunner().run("return \"ok\"")

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    func test_runnerExecutesJavaScript() throws {
        let output = try AppleScriptRunner().run("JSON.stringify({ ok: true });", language: .javaScript)

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "{\"ok\":true}")
    }
}
