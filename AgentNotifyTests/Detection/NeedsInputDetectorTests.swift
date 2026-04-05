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
}
