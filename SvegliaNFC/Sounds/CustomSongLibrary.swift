import AVFoundation
import Foundation
import Observation

struct CustomSong: Codable, Identifiable, Hashable {
    /// File inside `Library/Sounds`, also the value stored in `AlarmItem.soundName`.
    var fileName: String
    var title: String
    var addedAt: Date

    var id: String { fileName }
}

/// The user's own songs, cut to an alarm-sized clip and kept in `Library/Sounds` (where AlarmKit
/// looks for custom sounds). The list of titles lives in UserDefaults; everything stays on the phone.
@Observable
final class CustomSongLibrary {
    static let shared = CustomSongLibrary()

    private(set) var songs: [CustomSong] = []

    static var soundsDirectory: URL {
        URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    private static let key = "customSongs"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([CustomSong].self, from: data) {
            songs = saved.filter { FileManager.default.fileExists(atPath: Self.fileURL($0.fileName).path(percentEncoded: false)) }
        }
    }

    func song(named fileName: String) -> CustomSong? {
        songs.first { $0.fileName == fileName }
    }

    /// Cuts `duration` seconds of `source` starting at `start` and adds the clip to the library.
    func add(from source: URL, start: TimeInterval, title: String) async throws -> CustomSong {
        let fileName = "canzone-\(UUID().uuidString).caf"
        let destination = Self.fileURL(fileName)
        let duration = RingtoneCatalog.maxClipDuration
        try await Task.detached(priority: .userInitiated) {
            try SongClipper.makeClip(from: source, start: start, duration: duration, to: destination)
        }.value
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let song = CustomSong(
            fileName: fileName,
            title: trimmed.isEmpty ? String(localized: "La mia canzone") : trimmed,
            addedAt: .now
        )
        songs.insert(song, at: 0)
        save()
        return song
    }

    func delete(_ song: CustomSong) {
        try? FileManager.default.removeItem(at: Self.fileURL(song.fileName))
        songs.removeAll { $0.fileName == song.fileName }
        save()
    }

    private static func fileURL(_ fileName: String) -> URL {
        soundsDirectory.appending(path: fileName)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(songs) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// Turns any audio file iOS can decode (mp3, m4a, wav, aiff, caf…) into a short CAF clip in a format
/// the system alarm can play (IMA4, or 16-bit PCM as a fallback), with soft fades at both ends.
nonisolated enum SongClipper {
    enum ClipError: LocalizedError {
        case tooShort
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooShort: String(localized: "Il brano è troppo corto: serve almeno un secondo di audio.")
            case .unreadable: String(localized: "Non riesco a leggere questo file audio.")
            }
        }
    }

    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func makeClip(from source: URL, start: TimeInterval, duration: TimeInterval, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let rate = format.sampleRate
        let startFrame = min(AVAudioFramePosition(max(0, start) * rate), max(0, input.length - 1))
        let frames = AVAudioFrameCount(max(0, min(input.length - startFrame, AVAudioFramePosition(duration * rate))))
        guard Double(frames) >= rate else { throw ClipError.tooShort }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw ClipError.unreadable }
        input.framePosition = startFrame
        try input.read(into: buffer, frameCount: frames)
        applyFades(to: buffer, fadeIn: 0.3, fadeOut: 1.5)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        do {
            try write(buffer, to: destination, settings: [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: format.channelCount,
            ])
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try write(buffer, to: destination, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
        }
    }

    private static func write(_ buffer: AVAudioPCMBuffer, to url: URL, settings: [String: Any]) throws {
        let output = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
        )
        try output.write(from: buffer)
        output.close()
    }

    private static func applyFades(to buffer: AVAudioPCMBuffer, fadeIn: TimeInterval, fadeOut: TimeInterval) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        let inFrames = min(count, Int(fadeIn * rate))
        let outFrames = min(count, Int(fadeOut * rate))
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for i in 0..<inFrames {
                samples[i] *= Float(i) / Float(inFrames)
            }
            for i in 0..<outFrames {
                samples[count - 1 - i] *= Float(i) / Float(outFrames)
            }
        }
    }
}

/// Brings a song picked by the user into a temporary file the app can read freely.
enum SongSource {
    /// A file picked in Files: copied out of its security scope.
    nonisolated static func copyFromFiles(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let copy = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    /// A song of the Music library (only purchased or imported tracks have an `assetURL`).
    nonisolated static func exportFromMusicLibrary(_ assetURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SongClipper.ClipError.unreadable
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString).m4a")
        try await session.export(to: output, as: .m4a)
        return output
    }
}
