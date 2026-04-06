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

private final class SequencePoller: TerminalPolling {
    private let sequences: [[TerminalTabSnapshot]]
    private var index = 0

    init(sequences: [[TerminalTabSnapshot]]) {
        self.sequences = sequences
    }

    func poll() throws -> [TerminalTabSnapshot] {
        guard !sequences.isEmpty else {
            return []
        }

        let resolvedIndex = min(index, sequences.count - 1)
        if index < sequences.count - 1 {
            index += 1
        }
        return sequences[resolvedIndex]
    }
}

private final class InMemoryMonitorSettingsStore: MonitorSettingsStoring {
    var isMuted: Bool = false
    var alertCooldown: TimeInterval = 60
}

private struct StubPoller: TerminalPolling {
    let snapshots: [TerminalTabSnapshot]

    func poll() throws -> [TerminalTabSnapshot] {
        snapshots
    }
}

private extension MonitorControllerTests {
    func waitingSnapshot(
        windowID: Int,
        tabIndex: Int,
        tty: String,
        agent: String,
        visibleText: String
    ) -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            windowID: windowID,
            tabIndex: tabIndex,
            tty: tty,
            processes: ["login", "-zsh", agent],
            busy: false,
            visibleText: visibleText
        )
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

    func test_statusIncludesRowsAndSecondAlertWaitsForCooldown() throws {
        let notifier = SpyNotifier()
        let sound = SpySoundPlayer()
        let settings = InMemoryMonitorSettingsStore()
        settings.alertCooldown = 60

        let codexWaiting = try fixture(named: "codex_waiting")
        let claudeWaiting = try fixture(named: "claude_waiting")

        let poller = SequencePoller(sequences: [
            [
                waitingSnapshot(
                    windowID: 45,
                    tabIndex: 1,
                    tty: "/dev/ttys004",
                    agent: "codex",
                    visibleText: codexWaiting
                ),
                waitingSnapshot(
                    windowID: 46,
                    tabIndex: 2,
                    tty: "/dev/ttys005",
                    agent: "claude",
                    visibleText: claudeWaiting
                )
            ],
            [
                waitingSnapshot(
                    windowID: 45,
                    tabIndex: 1,
                    tty: "/dev/ttys004",
                    agent: "codex",
                    visibleText: codexWaiting
                ),
                waitingSnapshot(
                    windowID: 46,
                    tabIndex: 2,
                    tty: "/dev/ttys005",
                    agent: "claude",
                    visibleText: claudeWaiting
                )
            ],
            [
                waitingSnapshot(
                    windowID: 45,
                    tabIndex: 1,
                    tty: "/dev/ttys004",
                    agent: "codex",
                    visibleText: codexWaiting
                ),
                waitingSnapshot(
                    windowID: 46,
                    tabIndex: 2,
                    tty: "/dev/ttys005",
                    agent: "claude",
                    visibleText: claudeWaiting
                )
            ]
        ])

        let controller = MonitorController(
            poller: poller,
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 0)),
            notifier: notifier,
            soundPlayer: sound,
            settingsStore: settings
        )

        var statuses: [MonitorStatus] = []
        var statusCount = 0
        let secondStatusExpectation = expectation(description: "second status update")
        secondStatusExpectation.expectedFulfillmentCount = 2
        let thirdStatusExpectation = expectation(description: "third status update")

        controller.onStatusChange = { status in
            statuses.append(status)
            statusCount += 1

            if statusCount <= 2 {
                secondStatusExpectation.fulfill()
            }

            if statusCount == 3 {
                thirdStatusExpectation.fulfill()
            }
        }

        controller.tick(now: Date(timeIntervalSince1970: 10))
        controller.tick(now: Date(timeIntervalSince1970: 20))

        wait(for: [secondStatusExpectation], timeout: 1)

        XCTAssertEqual(notifier.sent.map(\.tty), ["/dev/ttys004"])
        XCTAssertEqual(sound.playCount, 1)

        guard let secondStatus = statuses.last else {
            return XCTFail("Missing status update")
        }

        XCTAssertEqual(secondStatus.trackedSessionCount, 2)
        XCTAssertEqual(secondStatus.waitingSessionCount, 2)
        XCTAssertEqual(secondStatus.tabs.filter(\.isCoolingDown).count, 1)
        XCTAssertEqual(secondStatus.tabs.map(\.title), ["Window 45 / Tab 1", "Window 46 / Tab 2"])
        XCTAssertEqual(secondStatus.tabs.map(\.isWaiting), [true, true])

        controller.tick(now: Date(timeIntervalSince1970: 81))

        wait(for: [thirdStatusExpectation], timeout: 1)

        XCTAssertEqual(notifier.sent.map(\.tty), ["/dev/ttys004", "/dev/ttys005"])
        XCTAssertEqual(sound.playCount, 2)
    }
}
