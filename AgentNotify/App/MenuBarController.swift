import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitorController: MonitorController
    private let permissionCoordinator: PermissionCoordinator
    private let launchAtLoginController: LaunchAtLoginController
    private let settingsStore: MonitorSettingsStoring
    private let dashboardPresenter: DashboardPresenting
    private let terminalNavigator: TerminalNavigating

    private var latestStatus: MonitorStatus

    init(
        monitorController: MonitorController,
        permissionCoordinator: PermissionCoordinator = PermissionCoordinator(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        settingsStore: MonitorSettingsStoring,
        dashboardPresenter: DashboardPresenting,
        terminalNavigator: TerminalNavigating = TerminalNavigator()
    ) {
        self.monitorController = monitorController
        self.permissionCoordinator = permissionCoordinator
        self.launchAtLoginController = launchAtLoginController
        self.settingsStore = settingsStore
        self.dashboardPresenter = dashboardPresenter
        self.terminalNavigator = terminalNavigator
        self.latestStatus = MonitorStatus(
            isRunning: monitorController.isRunning,
            isMuted: monitorController.isMuted,
            trackedSessionCount: monitorController.trackedSessionCount,
            waitingSessionCount: monitorController.waitingSessionCount,
            lastTriggeredTTY: monitorController.lastTriggeredTTY,
            lastErrorDescription: monitorController.lastErrorDescription,
            tabs: monitorController.tabs
        )
        super.init()

        self.monitorController.onStatusChange = { [weak self] status in
            guard let self else {
                return
            }

            self.latestStatus = status
            self.refreshDashboard()
        }

        self.dashboardPresenter.onRowSelected = { [weak self] row in
            self?.focus(row: row)
        }
        self.dashboardPresenter.onMutedChanged = { [weak self] muted in
            self?.monitorController.setMuted(muted)
        }
        self.dashboardPresenter.onAlertCooldownChanged = { [weak self] cooldown in
            self?.monitorController.setAlertCooldown(cooldown)
            self?.refreshDashboard()
        }
        self.dashboardPresenter.onLaunchAtLoginToggle = { [weak self] in
            self?.toggleLaunchAtLogin()
        }
        self.dashboardPresenter.onTestMoo = { [weak self] in
            self?.monitorController.playTestSound()
        }
    }

    func start() {
        configureStatusItem()

        Task { [weak self] in
            guard let self else {
                return
            }

            _ = await permissionCoordinator.requestNotificationAuthorizationIfNeeded()
            monitorController.start(pollInterval: 2)
            refreshDashboard()
        }
    }

    func openDashboard() {
        dashboardPresenter.show()
        refreshDashboard()
    }

    @objc
    func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        openDashboard()
    }

    private func configureStatusItem() {
        statusItem.menu = nil

        let image = Bundle.main.image(forResource: NSImage.Name("MenuBarCow"))
        if let image {
            image.size = NSSize(width: 18, height: 18)
        }

        if let button = statusItem.button {
            MenuBarButtonStyler.apply(to: button, image: image)
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: monitorController.isRunning ? String(localized: "Stop Monitoring") : String(localized: "Start Monitoring"),
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: monitorController.isMuted ? String(localized: "Unmute Alerts") : String(localized: "Mute Alerts"),
            action: #selector(toggleMute),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func showContextMenu() {
        let menu = makeContextMenu()
        guard let button = statusItem.button else {
            return
        }

        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    private func refreshDashboard() {
        Task { [weak self] in
            guard let self else {
                return
            }

            let permissions = await permissionCoordinator.currentState()
            dashboardPresenter.apply(
                status: latestStatus,
                permissions: permissions,
                launchAtLoginEnabled: launchAtLoginController.isEnabled,
                alertCooldown: settingsStore.alertCooldown
            )
        }
    }

    private func focus(row: DashboardRow) {
        do {
            try terminalNavigator.focus(windowID: row.windowID, tabIndex: row.tabIndex)
            dashboardPresenter.showInlineError(nil)
        } catch {
            dashboardPresenter.showInlineError(String(localized: "That Terminal tab is no longer available."))
        }
    }

    @objc
    private func toggleMonitoring() {
        if monitorController.isRunning {
            monitorController.stop()
        } else {
            monitorController.start(pollInterval: 2)
        }

        refreshDashboard()
    }

    @objc
    private func toggleMute() {
        monitorController.setMuted(!monitorController.isMuted)
        refreshDashboard()
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginController.isEnabled {
                try launchAtLoginController.disable()
            } else {
                try launchAtLoginController.enable()
            }
            dashboardPresenter.showInlineError(nil)
        } catch {
            dashboardPresenter.showInlineError(String(localized: "Could not update Launch at Login."))
        }

        refreshDashboard()
    }
}
