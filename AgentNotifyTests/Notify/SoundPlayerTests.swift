import AVFoundation
import XCTest
@testable import AgentNotify

final class SoundPlayerTests: XCTestCase {
    func test_cowSoundAssetIsBundledAndPlayable() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "moo", withExtension: "wav"))
        XCTAssertNoThrow(try AVAudioPlayer(contentsOf: url))
    }
}
