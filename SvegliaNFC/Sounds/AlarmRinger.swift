import AVFoundation
import Foundation

/// Plays the alarm's ringtone in a loop while an alarm rings and the app is open, at full player
/// volume and even with the silent switch on. The system alarm (AlarmKit) rings on its own.
final class AlarmRinger {
    private var player: AVAudioPlayer?
    private var soundName: String?

    func start(soundName: String) {
        guard player == nil || self.soundName != soundName else { return }
        stop()
        let file = RingtoneCatalog.url(for: soundName) ?? RingtoneCatalog.url(for: RingtoneCatalog.defaultSoundName)
        guard let file else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: file)
            player.numberOfLoops = -1
            player.volume = 1
            player.play()
            self.player = player
            self.soundName = soundName
        } catch {
            stop()
        }
    }

    func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        soundName = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
