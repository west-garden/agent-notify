import XCTest
@testable import AgentNotify

private struct StaticPoller: TerminalPolling {
    let snapshots: [TerminalTabSnapshot]

    func poll() throws -> [TerminalTabSnapshot] {
        snapshots
    }
}

private struct FailingNavigator: TerminalNavigating {
    func focus(windowID: Int, tabIndex: Int) throws {
        throw AppleScriptRunnerError.executionFailed("No such tab")
    }
}

private final class SpyNotifier: Notifying {
    func notify(_ payload: NotificationPayload) {}
}

private final class SpySoundPlayer: SoundPlaying {
    func playCowSound() {}
}

private final class InMemoryMonitorSettingsStore: MonitorSettingsStoring {
    var isMuted = false
    var alertCooldown: TimeInterval = 60
}

@MainActor
private final class SpyDashboardPresenter: DashboardPresenting {
    var showCount = 0
    var lastInlineError: String?
    var lastApply: (status: MonitorStatus, permissions: PermissionState, launchAtLoginEnabled: Bool, alertCooldown: TimeInterval)?

    var onRowSelected: ((DashboardRow) -> Void)?
    var onMutedChanged: ((Bool) -> Void)?
    var onAlertCooldownChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggle: (() -> Void)?
    var onTestMoo: (() -> Void)?

    func show() {
        showCount += 1
    }

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        lastApply = (status, permissions, launchAtLoginEnabled, alertCooldown)
    }

    func showInlineError(_ message: String?) {
        lastInlineError = message
    }
}

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func test_primaryClickShowsDashboard() {
        let presenter = SpyDashboardPresenter()
        let settingsStore = InMemoryMonitorSettingsStore()
        let monitorController = MonitorController(
            poller: StaticPoller(snapshots: []),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: SpyNotifier(),
            soundPlayer: SpySoundPlayer(),
            settingsStore: settingsStore
        )
        let controller = MenuBarController(
            monitorController: monitorController,
            settingsStore: settingsStore,
            dashboardPresenter: presenter,
            terminalNavigator: FailingNavigator()
        )

        controller.openDashboard()

        XCTAssertEqual(presenter.showCount, 1)
    }

    func test_selectingRowWithMissingTabShowsInlineError() {
        let presenter = SpyDashboardPresenter()
        let settingsStore = InMemoryMonitorSettingsStore()
        let monitorController = MonitorController(
            poller: StaticPoller(snapshots: []),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: SpyNotifier(),
            soundPlayer: SpySoundPlayer(),
            settingsStore: settingsStore
        )
        let controller = MenuBarController(
            monitorController: monitorController,
            settingsStore: settingsStore,
            dashboardPresenter: presenter,
            terminalNavigator: FailingNavigator()
        )

        withExtendedLifetime(controller) {
            presenter.onRowSelected?(
                DashboardRow(
                    id: "row-1",
                    windowID: 4,
                    tabIndex: 2,
                    title: "Window 4 / Tab 2",
                    badge: "Waiting",
                    isWaiting: true,
                    isCoolingDown: false
                )
            )
        }

        XCTAssertEqual(presenter.lastInlineError, "That Terminal tab is no longer available.")
    }
}
