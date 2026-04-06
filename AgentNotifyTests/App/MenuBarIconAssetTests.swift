import AppKit
import XCTest
@testable import AgentNotify

final class MenuBarIconAssetTests: XCTestCase {
    func test_menuBarCowAssetLoadsFromAppBundle() {
        let bundle = Bundle(for: SoundPlayer.self)
        let image = bundle.image(forResource: NSImage.Name("MenuBarCow"))

        XCTAssertNotNil(image)
    }
}
