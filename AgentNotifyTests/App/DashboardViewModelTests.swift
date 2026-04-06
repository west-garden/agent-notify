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

        XCTAssertEqual(viewModel.summaryText, "Monitoring | 2 tracked | 1 waiting")
        XCTAssertEqual(viewModel.needsAttentionRows.map(\.title), ["Window 2 / Tab 3"])
        XCTAssertEqual(viewModel.allMonitoredRows.map(\.title), ["Window 1 / Tab 1", "Window 2 / Tab 3"])
        XCTAssertNil(viewModel.needsAttentionEmptyText)
        XCTAssertEqual(viewModel.alertCooldownSeconds, 120)
        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertFalse(viewModel.isMuted)
        XCTAssertEqual(viewModel.notificationsStatusText, "Granted")
        XCTAssertEqual(viewModel.automationStatusText, "Granted")
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
            "No tracked tabs need attention right now. Monitoring is still active."
        )
        XCTAssertEqual(viewModel.notificationsStatusText, "Missing")
        XCTAssertEqual(viewModel.automationStatusText, "Needs Approval")
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
}
