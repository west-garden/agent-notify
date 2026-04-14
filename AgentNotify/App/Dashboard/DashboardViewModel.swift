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
    @Published private(set) var summaryText = "Paused · 0 tracked · 0 waiting"
    @Published private(set) var needsAttentionRows: [DashboardRow] = []
    @Published private(set) var allMonitoredRows: [DashboardRow] = []
    @Published private(set) var needsAttentionEmptyText: String?
    @Published private(set) var notificationsStatusText = String(localized: "Unknown")
    @Published private(set) var automationStatusText = String(localized: "Unknown")
    @Published private(set) var isNotificationsGranted = false
    @Published private(set) var isAutomationGranted = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published var isMuted = false
    @Published var alertCooldownSeconds: TimeInterval = 60
    @Published var inlineErrorText: String?

    var onRowSelected: ((DashboardRow) -> Void)?
    var onMutedChanged: ((Bool) -> Void)?
    var onAlertCooldownChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggle: (() -> Void)?
    var onTestMoo: (() -> Void)?
    var onQuitRequested: (() -> Void)?

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        let stateLabel = status.isRunning ? String(localized: "Monitoring") : String(localized: "Paused")
        let trackedLabel = String(localized: "\(status.trackedSessionCount) tracked")
        let waitingLabel = String(localized: "\(status.waitingSessionCount) waiting")
        summaryText = "\(stateLabel) · \(trackedLabel) · \(waitingLabel)"

        let rows = status.tabs.map { tab in
            DashboardRow(
                id: tab.id,
                windowID: tab.windowID,
                tabIndex: tab.tabIndex,
                title: tab.title,
                badge: tab.isWaiting ? String(localized: "Waiting") : String(localized: "Running"),
                isWaiting: tab.isWaiting,
                isCoolingDown: tab.isCoolingDown
            )
        }

        allMonitoredRows = rows
        needsAttentionRows = rows.filter(\.isWaiting)
        needsAttentionEmptyText = needsAttentionRows.isEmpty
            ? String(localized: "No tracked tabs need attention right now. Monitoring is still active.")
            : nil

        isNotificationsGranted = permissions.notificationsGranted
        isAutomationGranted = permissions.automationLikelyGranted
        notificationsStatusText = permissions.notificationsGranted ? String(localized: "Granted") : String(localized: "Missing")
        automationStatusText = permissions.automationLikelyGranted ? String(localized: "Granted") : String(localized: "Needs Approval")
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

    func quit() {
        onQuitRequested?()
    }
}
