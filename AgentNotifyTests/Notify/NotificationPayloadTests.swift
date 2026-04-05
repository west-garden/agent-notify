import XCTest
@testable import AgentNotify

final class NotificationPayloadTests: XCTestCase {
    func test_codexPayloadUsesAgentSpecificTitle() {
        let payload = NotificationPayload(
            sessionID: "45:1:/dev/ttys004",
            agent: .codex,
            tty: "/dev/ttys004"
        )

        XCTAssertEqual(payload.title, "Codex Waiting")
        XCTAssertEqual(payload.body, "Terminal tab on /dev/ttys004 is waiting for your input.")
    }

    func test_claudePayloadUsesAgentSpecificTitle() {
        let payload = NotificationPayload(
            sessionID: "46:2:/dev/ttys007",
            agent: .claude,
            tty: "/dev/ttys007"
        )

        XCTAssertEqual(payload.title, "Claude Waiting")
        XCTAssertEqual(payload.body, "Terminal tab on /dev/ttys007 is waiting for your input.")
    }
}
