import AVFoundation
import XCTest
@testable import AgentNotify

final class SoundPlayerTests: XCTestCase {
    func test_alertSoundAssetMatchesBundledLongStereoMoo() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "moo", withExtension: "wav"))
        let player = try AVAudioPlayer(contentsOf: url)

        XCTAssertEqual(player.format.channelCount, 2)
        XCTAssertEqual(player.format.sampleRate, 44_100, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(player.duration, 2.0)
    }
}
