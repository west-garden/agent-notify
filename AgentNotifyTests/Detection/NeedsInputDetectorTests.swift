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
            hasNotifiedForCurrentWait: false,
            windowID: 43,
            tabIndex: 0,
            tty: "/dev/ttys003"
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
            hasNotifiedForCurrentWait: false,
            windowID: 45,
            tabIndex: 1,
            tty: "/dev/ttys004"
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
            hasNotifiedForCurrentWait: false,
            windowID: 51,
            tabIndex: 6,
            tty: "/dev/ttys010"
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
            hasNotifiedForCurrentWait: false,
            windowID: 46,
            tabIndex: 0,
            tty: "/dev/ttys005"
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

    func test_currentCodexWorkingFooterDoesNotTriggerNeedsInput() {
        let working = """
        • Working (1m 56s • esc to interrupt) · 1 background terminal running · /ps to view · /stop to close

        › Implement {feature}

          gpt-5.4 xhigh · ~/code/west-garden/agent-notify
        """
        let normalized = TextNormalizer().normalize(working)
        let snapshot = TerminalTabSnapshot(
            windowID: 52,
            tabIndex: 7,
            tty: "/dev/ttys011",
            processes: ["login", "-zsh", "node", "codex"],
            busy: true,
            visibleText: working
        )

        let previous = TrackedSession(
            id: "52:7:/dev/ttys011",
            agent: .codex,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 52,
            tabIndex: 7,
            tty: "/dev/ttys011"
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

    func test_currentClaudeSpinnerDoesNotTriggerNeedsInput() {
        let working = """
        ✳ Flibbertigibbeting…

        ────────────────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────────────────
          [Opus 4.6] │ terrain git:(main)
        """
        let normalized = TextNormalizer().normalize(working)
        let snapshot = TerminalTabSnapshot(
            windowID: 53,
            tabIndex: 8,
            tty: "/dev/ttys012",
            processes: ["login", "-zsh", "claude"],
            busy: true,
            visibleText: working
        )

        let previous = TrackedSession(
            id: "53:8:/dev/ttys012",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 53,
            tabIndex: 8,
            tty: "/dev/ttys012"
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

    func test_currentClaudeActiveStepAboveLongTaskListDoesNotTriggerNeedsInput() {
        let working = """
        ✻ Transitioning to implementation... (1h 16m 17s · ↓ 14.7k tokens · thought for 16s)
        ╰ Transition to implementation
          ✓ Explore project contents
          ✓ Ask clarifying questions
          ✓ Propose 2-3 approaches
          ✓ Present design
          ✓ Write design doc
          ✓ Spec self-review
          ✓ User reviews written spec
          +3 completed

        ❯

          [Opus 4.6] │ ai-drama-script git:(main)
          Context 54%
          2 CLAUDE.md
          ✓ Read ×12 | ✓ Edit ×3 | ✓ Bash ×2
          ⏵⏵ bypass permissions on (shift+tab to cycle)
        """
        let normalized = TextNormalizer().normalize(working)
        let snapshot = TerminalTabSnapshot(
            windowID: 56,
            tabIndex: 11,
            tty: "/dev/ttys015",
            processes: ["login", "-zsh", "claude"],
            busy: true,
            visibleText: working
        )

        let previous = TrackedSession(
            id: "56:11:/dev/ttys015",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 56,
            tabIndex: 11,
            tty: "/dev/ttys015"
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

    func test_currentCodexWorkingLineAboveLongTaskListDoesNotTriggerNeedsInput() {
        let working = """
        • Working (1m 56s • esc to interrupt) · 1 background terminal running · /ps to view · /stop to close
          ✓ Explore project contents
          ✓ Ask clarifying questions
          ✓ Propose 2-3 approaches
          ✓ Present design
          ✓ Write design doc
          ✓ Spec self-review
          ✓ User reviews written spec
          +3 completed

        › Implement {feature}

          gpt-5.4 xhigh · ~/code/west-garden/agent-notify
          Context left until auto-compact: 54%
          2 CLAUDE.md
          ✓ Read ×12 | ✓ Edit ×3 | ✓ Bash ×2
          ⏵⏵ bypass permissions on (shift+tab to cycle)
        """
        let normalized = TextNormalizer().normalize(working)
        let snapshot = TerminalTabSnapshot(
            windowID: 57,
            tabIndex: 12,
            tty: "/dev/ttys016",
            processes: ["login", "-zsh", "node", "codex"],
            busy: true,
            visibleText: working
        )

        let previous = TrackedSession(
            id: "57:12:/dev/ttys016",
            agent: .codex,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 57,
            tabIndex: 12,
            tty: "/dev/ttys016"
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

    func test_claudePromptAboveFooterStillTriggersNeedsInput() {
        let waiting = """
        ✻ Sautéed for 10m 26s

        ────────────────────────────────────────────────────────────────────────
        ❯ 提交这个 fix
        ────────────────────────────────────────────────────────────────────────
          [Opus 4.6] │ terrain git:(main*) │ temporal-noodling-clover │ ⏱️ 18m
          Context ███░░░░░░░ 28%
          2 CLAUDE.md
          ✓ Bash ×11 | ✓ Read ×8 | ✓ Edit ×1
          ✓ Explore [sonnet]: Check project progress (4m 52s)
          ⏵⏵ bypass permissions on (shift+tab to cycle)
        """
        let normalized = TextNormalizer().normalize(waiting)
        let snapshot = TerminalTabSnapshot(
            windowID: 54,
            tabIndex: 9,
            tty: "/dev/ttys013",
            processes: ["login", "-zsh", "claude"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "54:9:/dev/ttys013",
            agent: .claude,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 54,
            tabIndex: 9,
            tty: "/dev/ttys013"
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

    func test_codexPromptAboveFooterStillTriggersNeedsInput() {
        let waiting = """
        › Implement {feature}

          gpt-5.4 xhigh · ~/code/west-garden/agent-notify
          Context left until auto-compact: 54%
          2 CLAUDE.md
          ✓ Read ×12 | ✓ Edit ×3 | ✓ Bash ×2
          ⏵⏵ bypass permissions on (shift+tab to cycle)
        """
        let normalized = TextNormalizer().normalize(waiting)
        let snapshot = TerminalTabSnapshot(
            windowID: 55,
            tabIndex: 10,
            tty: "/dev/ttys014",
            processes: ["login", "-zsh", "node", "codex"],
            busy: false,
            visibleText: waiting
        )

        let previous = TrackedSession(
            id: "55:10:/dev/ttys014",
            agent: .codex,
            state: .running,
            lastFingerprint: normalized,
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false,
            windowID: 55,
            tabIndex: 10,
            tty: "/dev/ttys014"
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
            hasNotifiedForCurrentWait: false,
            windowID: 47,
            tabIndex: 2,
            tty: "/dev/ttys006"
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
            hasNotifiedForCurrentWait: false,
            windowID: 48,
            tabIndex: 3,
            tty: "/dev/ttys007"
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
            hasNotifiedForCurrentWait: false,
            windowID: 50,
            tabIndex: 5,
            tty: "/dev/ttys009"
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
