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
        let claude = snapshot(
            windowID: 71,
            tabIndex: 3,
            tty: "/dev/ttys021",
            processes: ["login", "-zsh", "claude"],
            visibleText: "What would you like to do?"
        )
        let codex = snapshot(
            windowID: 70,
            tabIndex: 1,
            tty: "/dev/ttys020",
            processes: ["login", "-zsh", "codex"],
            visibleText: "Chat about this\nEnter to select"
        )

        _ = tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 10))
        _ = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 20))
        tracker.finishCycle(activeSessionIDs: ["70:1:/dev/ttys020", "71:3:/dev/ttys021"])

        let identities = tracker.activeSessions().map { ($0.windowID, $0.tabIndex, $0.tty) }
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(identities[0].0, 70)
        XCTAssertEqual(identities[0].1, 1)
        XCTAssertEqual(identities[0].2, "/dev/ttys020")
        XCTAssertEqual(identities[1].0, 71)
        XCTAssertEqual(identities[1].1, 3)
        XCTAssertEqual(identities[1].2, "/dev/ttys021")

        tracker.finishCycle(activeSessionIDs: ["71:3:/dev/ttys021"])

        let remaining = tracker.activeSessions()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "71:3:/dev/ttys021")
        XCTAssertEqual(remaining.first?.tty, "/dev/ttys021")
        XCTAssertEqual(remaining.first?.locationLabel, String(localized: "Window \(71) / Tab \(3)"))
    }

    func test_claudeWaitingStillNotifiesWhenOnlyFooterTimingChanges() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let first = snapshot(
            windowID: 72,
            tabIndex: 1,
            tty: "/dev/ttys022",
            processes: ["login", "-zsh", "claude"],
            visibleText: """
            ✻ Sautéed for 33s

            ────────────────────────────────────────────────────────────────────────
            ❯ 我觉得只需要看后面三项，其他没有必要看
            ────────────────────────────────────────────────────────────────────────
              [Opus 4.6] │ terrain git:(main*) │ temporal-noodling-clover │ ⏱️   29m
              Context ███░░░░░░░ 34%
              2 CLAUDE.md
              ✓ Bash ×11 | ✓ Read ×8 | ✓ Edit ×1
              ⏵⏵ bypass permissions on (shift+tab to cycle)
            """
        )
        let second = snapshot(
            windowID: 72,
            tabIndex: 1,
            tty: "/dev/ttys022",
            processes: ["login", "-zsh", "claude"],
            visibleText: """
            ✻ Sautéed for 34s

            ────────────────────────────────────────────────────────────────────────
            ❯ 我觉得只需要看后面三项，其他没有必要看
            ────────────────────────────────────────────────────────────────────────
              [Opus 4.6] │ terrain git:(main*) │ temporal-noodling-clover │ ⏱️   30m
              Context ████░░░░░░ 36%
              2 CLAUDE.md
              ✓ Bash ×11 | ✓ Read ×8 | ✓ Edit ×1
              ⏵⏵ bypass permissions on (shift+tab to cycle)
            """
        )

        XCTAssertNil(tracker.process(snapshot: first, now: Date(timeIntervalSince1970: 10))?.notification)

        let event = tracker.process(snapshot: second, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(event?.session.state, .needsInput)
        XCTAssertEqual(event?.notification?.agent, .claude)
    }

    func test_codexWaitingStillNotifiesWhenOnlyFooterMetadataChanges() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let first = snapshot(
            windowID: 73,
            tabIndex: 2,
            tty: "/dev/ttys023",
            processes: ["login", "-zsh", "node", "codex"],
            visibleText: """
            › Implement {feature}

              gpt-5.4 xhigh · ~/code/west-garden/agent-notify
              Context left until auto-compact: 54%
              2 CLAUDE.md
              ✓ Read ×12 | ✓ Edit ×3 | ✓ Bash ×2
              ⏵⏵ bypass permissions on (shift+tab to cycle)
            """
        )
        let second = snapshot(
            windowID: 73,
            tabIndex: 2,
            tty: "/dev/ttys023",
            processes: ["login", "-zsh", "node", "codex"],
            visibleText: """
            › Implement {feature}

              gpt-5.4 xhigh · ~/code/west-garden/agent-notify
              Context left until auto-compact: 53%
              2 CLAUDE.md
              ✓ Read ×12 | ✓ Edit ×3 | ✓ Bash ×2
              ⏵⏵ bypass permissions on (shift+tab to cycle)
            """
        )

        XCTAssertNil(tracker.process(snapshot: first, now: Date(timeIntervalSince1970: 10))?.notification)

        let event = tracker.process(snapshot: second, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(event?.session.state, .needsInput)
        XCTAssertEqual(event?.notification?.agent, .codex)
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
