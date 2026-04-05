import XCTest
@testable import AgentNotify

final class TerminalSnapshotParserTests: XCTestCase {
    func test_parserBuildsSnapshotFromPollOutput() throws {
        let raw = try fixture(named: "terminal_poll_output")
        let snapshots = try TerminalSnapshotParser().parse(raw)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].tty, "/dev/ttys000")
        XCTAssertTrue(snapshots[0].processes.contains("claude"))
    }
}
