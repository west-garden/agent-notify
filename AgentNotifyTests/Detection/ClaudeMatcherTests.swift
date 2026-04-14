import XCTest
@testable import AgentNotify

final class ClaudeMatcherTests: XCTestCase {
    func test_waitingFixtureMatchesInputReady() throws {
        let waiting = try fixture(named: "claude_waiting")
        let normalized = TextNormalizer().normalize(waiting)

        let matcher = ClaudeMatcher()

        XCTAssertTrue(matcher.matchesInputReady(normalized))
        XCTAssertFalse(matcher.matchesActiveWork(normalized))
    }

    func test_streamingFixtureMatchesActiveWork() throws {
        let streaming = try fixture(named: "claude_streaming")
        let normalized = TextNormalizer().normalize(streaming)

        let matcher = ClaudeMatcher()

        XCTAssertFalse(matcher.matchesInputReady(normalized))
        XCTAssertTrue(matcher.matchesActiveWork(normalized))
    }

    func test_capitalizedThinkingCountsAsActiveWork() {
        let matcher = ClaudeMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("Thinking..."))
    }

    func test_currentSpinnerLineCountsAsActiveWorkEvenWhenPromptIsVisible() {
        let matcher = ClaudeMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("""
        ✳ Flibbertigibbeting…

        ────────────────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────────────────
          [Opus 4.6] │ terrain git:(main)
        """))
    }

    func test_newSpinnerGlyphCountsAsActiveWorkEvenWhenPromptIsVisible() {
        let matcher = ClaudeMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("""
        ✢ Quantumizing…

        ────────────────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────────────────
          [Opus 4.6] │ terrain git:(main)
        """))
    }

    func test_longTaskListStillPreservesAnimatedStatusLine() {
        let matcher = ClaudeMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("""
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
        """))
    }
}
