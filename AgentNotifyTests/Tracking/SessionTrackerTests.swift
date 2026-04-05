import XCTest
@testable import AgentNotify

final class SessionTrackerTests: XCTestCase {
    func test_waitingTabNotifiesOnlyOnceUntilOutputChanges() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let waiting = TerminalTabSnapshot(
            windowID: 45,
            tabIndex: 1,
            tty: "/dev/ttys004",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: "Chat about this\nEnter to select"
        )

        let first = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 10))
        let second = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 20))

        XCTAssertNil(first?.notification)
        XCTAssertEqual(second?.notification?.agent, .codex)

        let third = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 30))
        XCTAssertNil(third?.notification)
    }
}
