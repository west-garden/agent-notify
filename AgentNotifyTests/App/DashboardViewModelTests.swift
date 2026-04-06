import XCTest
@testable import AgentNotify

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func test_applyBuildsAlertFirstSectionsAndEmptyState() {
        let viewModel = DashboardViewModel()

        viewModel.apply(
            status: MonitorStatus(
                isRunning: true,
                isMuted: false,
                trackedSessionCount: 2,
                waitingSessionCount: 1,
                lastTriggeredTTY: "/dev/ttys005",
                lastErrorDescription: nil,
                tabs: [
                    MonitoredTabState(
                        id: "1",
                        windowID: 1,
                        tabIndex: 1,
                        agent: .codex,
                        state: .running,
                        isCoolingDown: false
                    ),
                    MonitoredTabState(
                        id: "2",
                        windowID: 2,
                        tabIndex: 3,
                        agent: .claude,
                        state: .needsInput,
                        isCoolingDown: false
                    )
                ]
            ),
            permissions: PermissionState(notificationsGranted: true, automationLikelyGranted: true),
            launchAtLoginEnabled: true,
            alertCooldown: 120
        )

        XCTAssertEqual(
            viewModel.summaryText,
            "\(String(localized: "Monitoring")) · \(String(localized: "\(2) tracked")) · \(String(localized: "\(1) waiting"))"
        )
        XCTAssertEqual(viewModel.needsAttentionRows.map(\.title), [String(localized: "Window \(2) / Tab \(3)")])
        XCTAssertEqual(viewModel.allMonitoredRows.map(\.title), [String(localized: "Window \(1) / Tab \(1)"), String(localized: "Window \(2) / Tab \(3)")])
        XCTAssertNil(viewModel.needsAttentionEmptyText)
        XCTAssertEqual(viewModel.alertCooldownSeconds, 120)
        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertFalse(viewModel.isMuted)
        XCTAssertEqual(viewModel.notificationsStatusText, String(localized: "Granted"))
        XCTAssertEqual(viewModel.automationStatusText, String(localized: "Granted"))
        XCTAssertTrue(viewModel.isNotificationsGranted)
        XCTAssertTrue(viewModel.isAutomationGranted)
        XCTAssertNil(viewModel.inlineErrorText)

        viewModel.apply(
            status: MonitorStatus(
                isRunning: true,
                isMuted: false,
                trackedSessionCount: 1,
                waitingSessionCount: 0,
                lastTriggeredTTY: nil,
                lastErrorDescription: nil,
                tabs: [
                    MonitoredTabState(
                        id: "1",
                        windowID: 1,
                        tabIndex: 1,
                        agent: .codex,
                        state: .running,
                        isCoolingDown: false
                    )
                ]
            ),
            permissions: PermissionState(notificationsGranted: false, automationLikelyGranted: false),
            launchAtLoginEnabled: false,
            alertCooldown: 60
        )

        XCTAssertEqual(
            viewModel.needsAttentionEmptyText,
            String(localized: "No tracked tabs need attention right now. Monitoring is still active.")
        )
        XCTAssertEqual(viewModel.notificationsStatusText, String(localized: "Missing"))
        XCTAssertEqual(viewModel.automationStatusText, String(localized: "Needs Approval"))
        XCTAssertFalse(viewModel.isNotificationsGranted)
        XCTAssertFalse(viewModel.isAutomationGranted)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func test_selectForwardsRowSelection() {
        let viewModel = DashboardViewModel()
        let row = DashboardRow(
            id: "row-1",
            windowID: 4,
            tabIndex: 2,
            title: "Window 4 / Tab 2",
            badge: "Waiting",
            isWaiting: true,
            isCoolingDown: false
        )

        var selectedRow: DashboardRow?
        viewModel.onRowSelected = { selectedRow = $0 }

        viewModel.select(row)

        XCTAssertEqual(selectedRow, row)
    }

    func test_settingsActionsForwardCallbacks() {
        let viewModel = DashboardViewModel()

        var mutedValue: Bool?
        var cooldownValue: TimeInterval?
        var launchToggleCount = 0
        var testMooCount = 0

        viewModel.onMutedChanged = { mutedValue = $0 }
        viewModel.onAlertCooldownChanged = { cooldownValue = $0 }
        viewModel.onLaunchAtLoginToggle = { launchToggleCount += 1 }
        viewModel.onTestMoo = { testMooCount += 1 }

        viewModel.setMuted(true)
        viewModel.setAlertCooldown(120)
        viewModel.toggleLaunchAtLogin()
        viewModel.testMoo()

        XCTAssertEqual(mutedValue, true)
        XCTAssertTrue(viewModel.isMuted)
        XCTAssertEqual(cooldownValue, 120)
        XCTAssertEqual(viewModel.alertCooldownSeconds, 120)
        XCTAssertEqual(launchToggleCount, 1)
        XCTAssertEqual(testMooCount, 1)
    }
}
