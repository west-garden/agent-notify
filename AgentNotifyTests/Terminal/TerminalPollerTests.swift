import XCTest
@testable import AgentNotify

final class TerminalPollerTests: XCTestCase {
    func test_pollRequestsJavaScriptAndParsesJSONPayload() throws {
        let runner = RunnerStub(output: try fixture(named: "terminal_poll_output"))
        let snapshots = try TerminalPoller(runner: runner).poll()
        let snapshot = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(runner.language, .javaScript)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshot.windowID, 43)
        XCTAssertEqual(snapshot.visibleText, "Claude is waiting\n❯\t")
        XCTAssertTrue(runner.script.contains("JSON.stringify"))
    }
}

private final class RunnerStub: AppleScriptRunning {
    let output: String
    private(set) var script = ""
    private(set) var language: OsaLanguage?

    init(output: String) {
        self.output = output
    }

    func run(_ script: String, language: OsaLanguage) throws -> String {
        self.script = script
        self.language = language
        return output
    }
}
