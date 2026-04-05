import XCTest
@testable import AgentNotify

final class TerminalSnapshotParserTests: XCTestCase {
    func test_parserBuildsSnapshotFromPollOutput() throws {
        let raw = try fixture(named: "terminal_poll_output")
        let snapshots = try TerminalSnapshotParser().parse(raw)
        let snapshot = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshot.windowID, 43)
        XCTAssertEqual(snapshot.tabIndex, 1)
        XCTAssertEqual(snapshot.tty, "/dev/ttys000")
        XCTAssertEqual(snapshot.processes, ["login", "-zsh", "claude"])
        XCTAssertFalse(snapshot.busy)
        XCTAssertEqual(snapshot.visibleText, "Claude is waiting\n❯\t")
    }
}
