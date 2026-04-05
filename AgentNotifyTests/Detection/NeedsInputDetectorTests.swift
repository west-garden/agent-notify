import XCTest
@testable import AgentNotify

final class NeedsInputDetectorTests: XCTestCase {
    func test_recentOutputKeepsSessionRunning() {
        let snapshot = TerminalTabSnapshot(
            windowID: 43,
            tabIndex: 0,
            tty: "/dev/ttys003",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: "Streaming tokens...\nThinking..."
        )

        let previous = TrackedSession(
            id: "43:0:/dev/ttys003",
            agent: .codex,
            state: .running,
            lastFingerprint: "Streaming tokens...\nThinking...",
            lastChangeAt: Date(timeIntervalSince1970: 8),
            hasNotifiedForCurrentWait: false
        )

        let detector = NeedsInputDetector(quietPeriod: 3)
        let decision = detector.evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(decision.state, .running)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, "Streaming tokens...\nThinking...")
    }

    func test_quietCodexPromptTriggersNeedsInput() throws {
        let waiting = try fixture(named: "codex_waiting")
        let snapshot = TerminalTabSnapshot(
            windowID: 45,
            tabIndex: 1,
            tty: "/dev/ttys004",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "45:1:/dev/ttys004",
            agent: .codex,
            state: .running,
            lastFingerprint: TextNormalizer().normalize(waiting),
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .needsInput)
        XCTAssertTrue(decision.shouldNotify)
    }

    func test_quietCodexPromptAtBottomOverridesOlderActiveMarkers() throws {
        let waiting = try fixture(named: "codex_waiting")
        let mixed = [
            "Thinking...",
            "tool uses: reading files",
            waiting
        ].joined(separator: "\n")
        let normalized = TextNormalizer().normalize(mixed)
        let snapshot = TerminalTabSnapshot(
            windowID: 51,
            tabIndex: 6,
            tty: "/dev/ttys010",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: mixed
        )

        let previous = TrackedSession(
            id: "51:6:/dev/ttys010",
            agent: .codex,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .needsInput)
        XCTAssertTrue(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, normalized)
    }

    func test_streamingClaudeOutputStaysRunning() throws {
        let streaming = try fixture(named: "claude_streaming")
        let normalized = TextNormalizer().normalize(streaming)
        let snapshot = TerminalTabSnapshot(
            windowID: 46,
            tabIndex: 0,
            tty: "/dev/ttys005",
            processes: ["login", "-zsh", "claude"],
            busy: false,
            visibleText: streaming
        )

        let previous = TrackedSession(
            id: "46:0:/dev/ttys005",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .running)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, normalized)
    }

    func test_knownClaudeSessionUsesClaudeMatcherWithWrapperLikeProcessList() throws {
        let waiting = try fixture(named: "claude_waiting")
        let normalized = TextNormalizer().normalize(waiting)
        let snapshot = TerminalTabSnapshot(
            windowID: 47,
            tabIndex: 2,
            tty: "/dev/ttys006",
            processes: ["login", "-zsh", "node"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "47:2:/dev/ttys006",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .needsInput)
        XCTAssertTrue(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, normalized)
    }

    func test_previousClaudeSessionDoesNotTriggerNeedsInputOnPlainShellFallback() throws {
        let waiting = try fixture(named: "claude_waiting")
        let normalized = TextNormalizer().normalize(waiting)
        let snapshot = TerminalTabSnapshot(
            windowID: 48,
            tabIndex: 3,
            tty: "/dev/ttys007",
            processes: ["login", "-zsh"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "48:3:/dev/ttys007",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .running)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, normalized)
    }

    func test_plainShellWithoutKnownAgentStaysRunning() throws {
        let snapshot = TerminalTabSnapshot(
            windowID: 49,
            tabIndex: 4,
            tty: "/dev/ttys008",
            processes: ["login", "-zsh"],
            busy: false,
            visibleText: "❯"
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: nil,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .running)
        XCTAssertFalse(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, "❯")
    }

    func test_explicitCurrentCodexProcessOverridesPreviousClaudeAgent() throws {
        let waiting = try fixture(named: "codex_waiting")
        let normalized = TextNormalizer().normalize(waiting)
        let snapshot = TerminalTabSnapshot(
            windowID: 50,
            tabIndex: 5,
            tty: "/dev/ttys009",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "50:5:/dev/ttys009",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(decision.state, .needsInput)
        XCTAssertTrue(decision.shouldNotify)
        XCTAssertEqual(decision.fingerprint, normalized)
    }
}
