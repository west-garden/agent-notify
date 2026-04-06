import AppKit
import XCTest
@testable import AgentNotify

@MainActor
final class MenuBarButtonStylerTests: XCTestCase {
    func test_applyUsesImageOnlyPresentationWhenImageExists() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        let image = NSImage(size: NSSize(width: 18, height: 18))

        MenuBarButtonStyler.apply(to: button, image: image)

        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertNotNil(button.image)
        XCTAssertFalse(button.image?.isTemplate ?? true)
        XCTAssertEqual(button.toolTip, "AgentNotify")
        XCTAssertEqual(button.accessibilityTitle(), "AgentNotify")
    }

    func test_applyFallsBackToMooTitleWhenImageIsMissing() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))

        MenuBarButtonStyler.apply(to: button, image: nil)

        XCTAssertEqual(button.title, "Moo")
        XCTAssertNil(button.image)
        XCTAssertEqual(button.toolTip, "AgentNotify")
        XCTAssertEqual(button.accessibilityTitle(), "AgentNotify")
    }
}
