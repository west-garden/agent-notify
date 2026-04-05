import AppKit

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitorController: MonitorController
    private let permissionCoordinator: PermissionCoordinator
    private let launchAtLoginController: LaunchAtLoginController

    private let statusMenuItem = NSMenuItem(title: "Status: Starting…", action: nil, keyEquivalent: "")
    private let trackedMenuItem = NSMenuItem(title: "Tracked Tabs: 0", action: nil, keyEquivalent: "")
    private let lastAlertMenuItem = NSMenuItem(title: "Last Alert: None", action: nil, keyEquivalent: "")
    private let permissionsMenuItem = NSMenuItem(title: "Notifications: Unknown", action: nil, keyEquivalent: "")
    private lazy var startStopMenuItem = NSMenuItem(title: "Start Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
    private lazy var muteMenuItem = NSMenuItem(title: "Mute Alerts", action: #selector(toggleMute), keyEquivalent: "")
    private lazy var launchAtLoginMenuItem = NSMenuItem(title: launchAtLoginTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    init(
        monitorController: MonitorController = MonitorController(
            poller: TerminalPoller(runner: AppleScriptRunner()),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: NotificationService(),
            soundPlayer: SoundPlayer()
        ),
        permissionCoordinator: PermissionCoordinator = PermissionCoordinator(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.monitorController = monitorController
        self.permissionCoordinator = permissionCoordinator
        self.launchAtLoginController = launchAtLoginController
        super.init()
        self.monitorController.onStatusChange = { [weak self] status in
            self?.updateMenu(status: status)
        }
    }

    func start() {
        configureMenu()
        statusItem.button?.title = "Moo"

        Task { [weak self] in
            guard let self else {
                return
            }

            _ = await permissionCoordinator.requestNotificationAuthorizationIfNeeded()
            let permissions = await permissionCoordinator.currentState()
            await MainActor.run {
                self.updatePermissions(permissions)
                self.updateLaunchAtLoginTitle()
                self.monitorController.start(pollInterval: 2)
                self.startStopMenuItem.title = "Stop Monitoring"
            }
        }
    }

    @objc
    private func toggleMonitoring() {
        if monitorController.isRunning {
            monitorController.stop()
            startStopMenuItem.title = "Start Monitoring"
            return
        }

        monitorController.start(pollInterval: 2)
        startStopMenuItem.title = "Stop Monitoring"
    }

    @objc
    private func toggleMute() {
        let muted = !monitorController.isMuted
        monitorController.setMuted(muted)
        muteMenuItem.title = muted ? "Unmute Alerts" : "Mute Alerts"
    }

    @objc
    private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginController.isEnabled {
                try launchAtLoginController.disable()
            } else {
                try launchAtLoginController.enable()
            }

            updateLaunchAtLoginTitle()
        } catch {
            updateLaunchAtLoginTitle()
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        [statusMenuItem, trackedMenuItem, lastAlertMenuItem, permissionsMenuItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }

        startStopMenuItem.target = self
        muteMenuItem.target = self
        launchAtLoginMenuItem.target = self

        menu.addItem(.separator())
        menu.addItem(startStopMenuItem)
        menu.addItem(muteMenuItem)
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    private func updateMenu(status: MonitorStatus) {
        if let error = status.lastErrorDescription, !error.isEmpty {
            statusMenuItem.title = "Status: Error"
            trackedMenuItem.title = "Tracked Tabs: 0"
            lastAlertMenuItem.title = "Last Alert: \(error)"
            return
        }

        statusMenuItem.title = status.isRunning ? "Status: Monitoring" : "Status: Paused"
        trackedMenuItem.title = "Tracked Tabs: \(status.trackedSessionCount)"
        lastAlertMenuItem.title = "Last Alert: \(status.lastTriggeredTTY ?? "None")"
    }

    private func updatePermissions(_ permissions: PermissionState) {
        let notificationsText = permissions.notificationsGranted ? "Granted" : "Missing"
        let automationText = permissions.automationLikelyGranted ? "Granted" : "Needs Approval"
        permissionsMenuItem.title = "Notifications: \(notificationsText) · Automation: \(automationText)"
    }

    private var launchAtLoginTitle: String {
        launchAtLoginController.isEnabled ? "Disable Launch at Login" : "Enable Launch at Login"
    }

    private func updateLaunchAtLoginTitle() {
        launchAtLoginMenuItem.title = launchAtLoginTitle
    }
}
