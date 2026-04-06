import AVFoundation
import XCTest
@testable import AgentNotify

final class SoundPlayerTests: XCTestCase {
    func test_alertSoundAssetIsBundledShortAndPlayable() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "moo", withExtension: "wav"))
        let player = try AVAudioPlayer(contentsOf: url)

        XCTAssertLessThanOrEqual(player.duration, 0.4)
    }
}
