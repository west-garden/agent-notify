import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settingsStore = MonitorSettingsStore()
        let monitorController = MonitorController(
            poller: TerminalPoller(runner: AppleScriptRunner()),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: NotificationService(),
            soundPlayer: SoundPlayer(),
            settingsStore: settingsStore
        )

        menuBarController = MenuBarController(
            monitorController: monitorController,
            settingsStore: settingsStore,
            dashboardPresenter: DashboardWindowController(),
            terminalNavigator: TerminalNavigator()
        )
        menuBarController?.start()
    }
}
