import Combine
import Foundation

struct DashboardRow: Identifiable, Equatable {
    let id: String
    let windowID: Int
    let tabIndex: Int
    let title: String
    let badge: String
    let isWaiting: Bool
    let isCoolingDown: Bool
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var summaryText = "Paused | 0 tracked | 0 waiting"
    @Published private(set) var needsAttentionRows: [DashboardRow] = []
    @Published private(set) var allMonitoredRows: [DashboardRow] = []
    @Published private(set) var needsAttentionEmptyText: String?
    @Published private(set) var notificationsStatusText = "Unknown"
    @Published private(set) var automationStatusText = "Unknown"
    @Published var launchAtLoginEnabled = false
    @Published var isMuted = false
    @Published var alertCooldownSeconds: TimeInterval = 60
    @Published var inlineErrorText: String?

    var onRowSelected: ((DashboardRow) -> Void)?
    var onMutedChanged: ((Bool) -> Void)?
    var onAlertCooldownChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggle: (() -> Void)?
    var onTestMoo: (() -> Void)?

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        summaryText = "\(status.isRunning ? "Monitoring" : "Paused") | \(status.trackedSessionCount) tracked | \(status.waitingSessionCount) waiting"

        let rows = status.tabs.map { tab in
            DashboardRow(
                id: tab.id,
                windowID: tab.windowID,
                tabIndex: tab.tabIndex,
                title: tab.title,
                badge: tab.isWaiting ? "Waiting" : "Running",
                isWaiting: tab.isWaiting,
                isCoolingDown: tab.isCoolingDown
            )
        }

        allMonitoredRows = rows
        needsAttentionRows = rows.filter(\.isWaiting)
        needsAttentionEmptyText = needsAttentionRows.isEmpty
            ? "No tracked tabs need attention right now. Monitoring is still active."
            : nil

        notificationsStatusText = permissions.notificationsGranted ? "Granted" : "Missing"
        automationStatusText = permissions.automationLikelyGranted ? "Granted" : "Needs Approval"
        self.launchAtLoginEnabled = launchAtLoginEnabled
        isMuted = status.isMuted
        alertCooldownSeconds = alertCooldown
        inlineErrorText = status.lastErrorDescription
    }

    func select(_ row: DashboardRow) {
        onRowSelected?(row)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        onMutedChanged?(muted)
    }

    func setAlertCooldown(_ seconds: TimeInterval) {
        alertCooldownSeconds = seconds
        onAlertCooldownChanged?(seconds)
    }

    func toggleLaunchAtLogin() {
        onLaunchAtLoginToggle?()
    }

    func testMoo() {
        onTestMoo?()
    }
}
