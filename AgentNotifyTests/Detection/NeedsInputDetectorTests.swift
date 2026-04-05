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
}
