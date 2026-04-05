import AppKit
import AVFoundation

protocol SoundPlaying {
    func playCowSound()
}

final class SoundPlayer: SoundPlaying {
    private var player: AVAudioPlayer?

    func playCowSound() {
        guard let url = Bundle.main.url(forResource: "moo", withExtension: "wav") else {
            NSSound.beep()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            NSSound.beep()
        }
    }
}
