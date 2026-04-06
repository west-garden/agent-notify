import AppKit

enum MenuBarButtonStyler {
    private static let accessibilityTitle = "AgentNotify"

    @MainActor
    static func apply(to button: NSStatusBarButton, image: NSImage?) {
        button.toolTip = accessibilityTitle
        button.setAccessibilityTitle(accessibilityTitle)

        guard let image else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "Moo"
            return
        }

        image.isTemplate = false
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
    }
}
