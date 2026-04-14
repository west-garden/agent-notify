import XCTest
@testable import AgentNotify

final class CodexMatcherTests: XCTestCase {
    func test_waitingFixtureMatchesInputReady() throws {
        let waiting = try fixture(named: "codex_waiting")
        let normalized = TextNormalizer().normalize(waiting)

        let matcher = CodexMatcher()

        XCTAssertTrue(matcher.matchesInputReady(normalized))
        XCTAssertFalse(matcher.matchesActiveWork(normalized))
    }

    func test_streamingFixtureMatchesActiveWork() throws {
        let streaming = try fixture(named: "codex_streaming")
        let normalized = TextNormalizer().normalize(streaming)

        let matcher = CodexMatcher()

        XCTAssertFalse(matcher.matchesInputReady(normalized))
        XCTAssertTrue(matcher.matchesActiveWork(normalized))
    }

    func test_capitalizedThinkingCountsAsActiveWork() {
        let matcher = CodexMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("Thinking..."))
    }

    func test_currentWorkingFooterCountsAsActiveWorkEvenWhenPromptIsVisible() {
        let matcher = CodexMatcher()

        XCTAssertTrue(matcher.matchesActiveWork("""
        • Working (1m 56s • esc to interrupt) · 1 background terminal running · /ps to view · /stop to close

        › Implement {feature}

          gpt-5.4 xhigh · ~/code/west-garden/agent-notify
        """))
    }

    func test_legacySelectionPromptStillMatchesInputReady() {
        let matcher = CodexMatcher()

        XCTAssertTrue(matcher.matchesInputReady("""
        Chat about this
        Enter to select · ↑/↓ to navigate
        """))
    }
}
