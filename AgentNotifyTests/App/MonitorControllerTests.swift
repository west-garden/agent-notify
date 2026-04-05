import XCTest
@testable import AgentNotify

private final class SpyNotifier: Notifying {
    var sent: [NotificationPayload] = []

    func notify(_ payload: NotificationPayload) {
        sent.append(payload)
    }
}

private final class SpySoundPlayer: SoundPlaying {
    var playCount = 0

    func playCowSound() {
        playCount += 1
    }
}

private struct StubPoller: TerminalPolling {
    let snapshots: [TerminalTabSnapshot]

    func poll() throws -> [TerminalTabSnapshot] {
        snapshots
    }
}

final class MonitorControllerTests: XCTestCase {
    func test_eventWithNotificationCallsNotifierAndSound() {
        let notifier = SpyNotifier()
        let sound = SpySoundPlayer()
        let controller = MonitorController(
            poller: StubPoller(snapshots: [
                TerminalTabSnapshot(
                    windowID: 45,
                    tabIndex: 1,
                    tty: "/dev/ttys004",
                    processes: ["login", "-zsh", "codex"],
                    busy: false,
                    visibleText: """
                    › Run /review on my current changes

                    gpt-5.4 xhigh · 27% left · ~/code/west-garden/agent-notify · Main [default]
                    """
                )
            ]),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 0)),
            notifier: notifier,
            soundPlayer: sound
        )

        controller.tick(now: Date(timeIntervalSince1970: 10))
        controller.tick(now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(notifier.sent.count, 1)
        XCTAssertEqual(sound.playCount, 1)
        XCTAssertEqual(notifier.sent.first?.title, "Codex Waiting")
    }
}
