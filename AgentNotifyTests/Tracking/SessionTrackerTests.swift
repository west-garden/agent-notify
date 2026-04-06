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

    func test_wrapperProcessContinuationStillTracksKnownAgent() throws {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let waiting = try fixture(named: "claude_waiting")
        let initial = snapshot(
            windowID: 60,
            tabIndex: 2,
            tty: "/dev/ttys011",
            processes: ["login", "-zsh", "claude"],
            visibleText: waiting
        )
        let wrapper = snapshot(
            windowID: 60,
            tabIndex: 2,
            tty: "/dev/ttys011",
            processes: ["login", "-zsh", "node"],
            visibleText: waiting
        )

        XCTAssertNil(tracker.process(snapshot: initial, now: Date(timeIntervalSince1970: 10))?.notification)

        let event = tracker.process(snapshot: wrapper, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(event?.session.agent, .claude)
        XCTAssertEqual(event?.notification?.agent, .claude)
    }

    func test_plainShellClearsStateSoNextRunCanNotifyAgain() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let waiting = snapshot(
            windowID: 61,
            tabIndex: 3,
            tty: "/dev/ttys012",
            processes: ["login", "-zsh", "codex"],
            visibleText: "Chat about this\nEnter to select"
        )
        let plainShell = snapshot(
            windowID: 61,
            tabIndex: 3,
            tty: "/dev/ttys012",
            processes: ["login", "-zsh"],
            visibleText: "❯"
        )

        XCTAssertNil(tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 10))?.notification)
        XCTAssertEqual(tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 20))?.notification?.agent, .codex)
        XCTAssertNil(tracker.process(snapshot: plainShell, now: Date(timeIntervalSince1970: 30)))

        let firstAfterReset = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 40))
        let secondAfterReset = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 50))

        XCTAssertNil(firstAfterReset?.notification)
        XCTAssertEqual(secondAfterReset?.notification?.agent, .codex)
    }

    func test_outputChangesRearmNotifications() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let waiting = snapshot(
            windowID: 62,
            tabIndex: 4,
            tty: "/dev/ttys013",
            processes: ["login", "-zsh", "codex"],
            visibleText: "Chat about this\nEnter to select"
        )
        let running = snapshot(
            windowID: 62,
            tabIndex: 4,
            tty: "/dev/ttys013",
            processes: ["login", "-zsh", "codex"],
            visibleText: "Streaming tokens...\nThinking..."
        )

        XCTAssertNil(tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 10))?.notification)
        XCTAssertEqual(tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 20))?.notification?.agent, .codex)
        XCTAssertNil(tracker.process(snapshot: running, now: Date(timeIntervalSince1970: 30))?.notification)
        XCTAssertNil(tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 40))?.notification)

        let rearmed = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(rearmed?.notification?.agent, .codex)
    }

    func test_explicitAgentSwitchRefreshesTrackedSessionAndPayload() throws {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let claudeWaiting = try fixture(named: "claude_waiting")
        let codexWaiting = try fixture(named: "codex_waiting")
        let claude = snapshot(
            windowID: 63,
            tabIndex: 5,
            tty: "/dev/ttys014",
            processes: ["login", "-zsh", "claude"],
            visibleText: claudeWaiting
        )
        let codex = snapshot(
            windowID: 63,
            tabIndex: 5,
            tty: "/dev/ttys014",
            processes: ["login", "-zsh", "codex"],
            visibleText: codexWaiting
        )

        XCTAssertNil(tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 10))?.notification)

        let switched = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 20))
        let notified = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(switched?.session.agent, .codex)
        XCTAssertNil(switched?.notification)
        XCTAssertEqual(notified?.session.agent, .codex)
        XCTAssertEqual(notified?.notification?.agent, .codex)
    }

    func test_explicitAgentSwitchWithSameTextRearmsDebounceAfterPriorNotification() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let sharedWaiting = """
        ❯ What would you like to do?
        Chat about this
        Enter to select
        """
        let claude = snapshot(
            windowID: 64,
            tabIndex: 6,
            tty: "/dev/ttys015",
            processes: ["login", "-zsh", "claude"],
            visibleText: sharedWaiting
        )
        let codex = snapshot(
            windowID: 64,
            tabIndex: 6,
            tty: "/dev/ttys015",
            processes: ["login", "-zsh", "codex"],
            visibleText: sharedWaiting
        )

        XCTAssertNil(tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 10))?.notification)
        XCTAssertEqual(tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 20))?.notification?.agent, .claude)

        let switched = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 30))
        let rearmed = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 40))

        XCTAssertEqual(switched?.session.agent, .codex)
        XCTAssertNil(switched?.notification)
        XCTAssertEqual(rearmed?.session.agent, .codex)
        XCTAssertEqual(rearmed?.notification?.agent, .codex)
    }

    func test_activeSessionsCarryWindowTabIdentityAndPruneMissingTabs() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let codex = snapshot(
            windowID: 70,
            tabIndex: 1,
            tty: "/dev/ttys020",
            processes: ["login", "-zsh", "codex"],
            visibleText: "Chat about this\nEnter to select"
        )
        let claude = snapshot(
            windowID: 71,
            tabIndex: 3,
            tty: "/dev/ttys021",
            processes: ["login", "-zsh", "claude"],
            visibleText: "What would you like to do?"
        )

        _ = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 10))
        _ = tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 20))
        tracker.finishCycle(activeSessionIDs: ["70:1:/dev/ttys020", "71:3:/dev/ttys021"])

        let identities = tracker.activeSessions().map { ($0.windowID, $0.tabIndex, $0.tty) }
        let expectedIdentities = [(70, 1, "/dev/ttys020"), (71, 3, "/dev/ttys021")]
        XCTAssertEqual(identities.count, expectedIdentities.count)
        XCTAssertTrue(
            zip(identities, expectedIdentities).allSatisfy { pair in
                let actual = pair.0
                let expected = pair.1
                return actual.0 == expected.0 && actual.1 == expected.1 && actual.2 == expected.2
            }
        )

        tracker.finishCycle(activeSessionIDs: ["71:3:/dev/ttys021"])

        let remaining = tracker.activeSessions()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.locationLabel, "Window 71 / Tab 3")
    }
}

private extension SessionTrackerTests {
    func snapshot(
        windowID: Int,
        tabIndex: Int,
        tty: String,
        processes: [String],
        visibleText: String
    ) -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            windowID: windowID,
            tabIndex: tabIndex,
            tty: tty,
            processes: processes,
            busy: false,
            visibleText: visibleText
        )
    }
}
