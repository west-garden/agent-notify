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
}
