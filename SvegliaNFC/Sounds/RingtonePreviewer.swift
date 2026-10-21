import AVFoundation
import Foundation
import Observation

/// Plays one sound at a time for preview, even with the silent switch on.
@Observable
final class RingtonePreviewer {
    /// The id of the sound playing right now.
    private(set) var playingID: String?

    private var player: AVAudioPlayer?
    private var endTask: Task<Void, Never>?

    func play(id: String, url: URL, from start: TimeInterval = 0, duration: TimeInterval? = nil) {
        stop(deactivatingSession: false)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.currentTime = min(max(0, start), max(0, player.duration - 0.5))
            player.play()
            self.player = player
            playingID = id
            let remaining = player.duration - player.currentTime
            let length = min(duration ?? remaining, remaining)
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(length))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            stop()
        }
    }

    func stop() {
        stop(deactivatingSession: true)
    }

    private func stop(deactivatingSession: Bool) {
        endTask?.cancel()
        endTask = nil
        player?.stop()
        player = nil
        playingID = nil
        if deactivatingSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
