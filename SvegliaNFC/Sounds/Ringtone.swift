import ActivityKit
import Foundation

enum RingtoneFamily: String, CaseIterable, Identifiable {
    case gentle, classic, energetic

    var id: Self { self }

    var title: String {
        switch self {
        case .gentle: String(localized: "Dolci")
        case .classic: String(localized: "Classiche")
        case .energetic: String(localized: "Energiche")
        }
    }

    var subtitle: String {
        switch self {
        case .gentle: String(localized: "Partono piano e crescono: per un risveglio morbido.")
        case .classic: String(localized: "Campane, bip e trilli di una volta.")
        case .energetic: String(localized: "Ritmo e volume pieni fin dal primo secondo.")
        }
    }

    var symbol: String {
        switch self {
        case .gentle: "sunrise"
        case .classic: "bell"
        case .energetic: "bolt"
        }
    }
}

/// A sound an alarm can ring with. Built-in ones live in the app bundle, songs imported by the
/// user in `Library/Sounds`: both are places AlarmKit looks into when given a file name.
struct Ringtone: Identifiable, Hashable {
    /// The file name passed to AlarmKit, also stored in `AlarmItem.soundName`.
    let fileName: String
    let name: String
    /// Nil for the user's own songs.
    let family: RingtoneFamily?

    var id: String { fileName }
}

enum RingtoneCatalog {
    /// `AlarmItem.soundName` value meaning "the standard iOS alarm sound".
    static let systemSoundName = ""

    /// Longest clip AlarmKit plays: Apple asks for sounds shorter than 30 seconds, otherwise the
    /// system falls back to the default sound.
    static let maxClipDuration: TimeInterval = 28

    static func ringtones(in family: RingtoneFamily) -> [Ringtone] {
        builtIn.filter { $0.family == family }
    }

    static func builtIn(named fileName: String) -> Ringtone? {
        builtIn.first { $0.fileName == fileName }
    }

    /// Name shown to the user for an alarm's `soundName`.
    static func displayName(for soundName: String) -> String {
        if let ringtone = builtIn(named: soundName) { return ringtone.name }
        if let song = CustomSongLibrary.shared.song(named: soundName), url(for: soundName) != nil { return song.title }
        return String(localized: "Standard di iOS")
    }

    /// Where the sound file is, or nil for the iOS sound and for songs that were deleted.
    static func url(for soundName: String) -> URL? {
        guard !soundName.isEmpty else { return nil }
        if let url = Bundle.main.url(forResource: soundName, withExtension: nil) { return url }
        let imported = CustomSongLibrary.soundsDirectory.appending(path: soundName)
        return FileManager.default.fileExists(atPath: imported.path(percentEncoded: false)) ? imported : nil
    }

    /// The sound handed to AlarmKit. A missing file falls back to the iOS sound, so an alarm never
    /// ends up silent.
    static func alertSound(for soundName: String) -> AlertConfiguration.AlertSound {
        url(for: soundName) == nil ? .default : .named(soundName)
    }
}
