import AppKit
import SwiftUI

@MainActor
protocol DashboardPresenting: AnyObject {
    @MainActor func show()
    @MainActor func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    )
    @MainActor func showInlineError(_ message: String?)
    @MainActor var onRowSelected: ((DashboardRow) -> Void)? { get set }
    @MainActor var onMutedChanged: ((Bool) -> Void)? { get set }
    @MainActor var onAlertCooldownChanged: ((TimeInterval) -> Void)? { get set }
    @MainActor var onLaunchAtLoginToggle: (() -> Void)? { get set }
    @MainActor var onTestMoo: (() -> Void)? { get set }
    @MainActor var onQuitRequested: (() -> Void)? { get set }
}

@MainActor
final class DashboardWindowController: NSObject, DashboardPresenting {
    private let viewModel = DashboardViewModel()

    private lazy var window: NSWindow = {
        let hostingController = NSHostingController(rootView: DashboardView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "AgentNotify"
        window.setContentSize(NSSize(width: 560, height: 680))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }()

    var onRowSelected: ((DashboardRow) -> Void)? {
        get { viewModel.onRowSelected }
        set { viewModel.onRowSelected = newValue }
    }

    var onMutedChanged: ((Bool) -> Void)? {
        get { viewModel.onMutedChanged }
        set { viewModel.onMutedChanged = newValue }
    }

    var onAlertCooldownChanged: ((TimeInterval) -> Void)? {
        get { viewModel.onAlertCooldownChanged }
        set { viewModel.onAlertCooldownChanged = newValue }
    }

    var onLaunchAtLoginToggle: (() -> Void)? {
        get { viewModel.onLaunchAtLoginToggle }
        set { viewModel.onLaunchAtLoginToggle = newValue }
    }

    var onTestMoo: (() -> Void)? {
        get { viewModel.onTestMoo }
        set { viewModel.onTestMoo = newValue }
    }

    var onQuitRequested: (() -> Void)? {
        get { viewModel.onQuitRequested }
        set { viewModel.onQuitRequested = newValue }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        viewModel.apply(
            status: status,
            permissions: permissions,
            launchAtLoginEnabled: launchAtLoginEnabled,
            alertCooldown: alertCooldown
        )
    }

    func showInlineError(_ message: String?) {
        viewModel.inlineErrorText = message
    }
}
