import Foundation
import SvegliaCore
import SwiftData

@Model
final class AlarmItem {
    var id = UUID()
    var hour = 7
    var minute = 0
    /// Calendar weekdays (1 = Sunday … 7 = Saturday); empty means the alarm rings once.
    var weekdays: [Int] = []
    var isEnabled = true
    var label = ""
    /// Last time the alarm was switched on or changed: rings before this moment don't count.
    var armedAt = Date.now
    var createdAt = Date.now
    /// Raw value of `DismissMethod`: how this alarm is switched off.
    var dismissMethod = DismissMethod.tag.rawValue
    /// Raw value of `MissionDifficulty`, used when `dismissMethod` is the math mission.
    var missionDifficulty = MissionDifficulty.medium.rawValue
    /// Sound file the alarm rings with (see `RingtoneCatalog`); empty means the standard iOS sound.
    var soundName = RingtoneCatalog.systemSoundName

    init(hour: Int, minute: Int, weekdays: [Int], label: String = "") {
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.label = label
    }

    var rule: AlarmRule { AlarmRule(hour: hour, minute: minute, weekdays: Set(weekdays)) }

    var method: DismissMethod {
        get { DismissMethod(rawValue: dismissMethod) ?? .tag }
        set { dismissMethod = newValue.rawValue }
    }

    var difficulty: MissionDifficulty {
        get { MissionDifficulty(rawValue: missionDifficulty) ?? .medium }
        set { missionDifficulty = newValue.rawValue }
    }
}

/// How a ringing alarm is switched off.
enum DismissMethod: String, CaseIterable {
    /// Walk to the paired NFC tag and scan it.
    case tag
    /// Solve a few math problems that get harder one by one.
    case math
}

@Model
final class PairedTag {
    var id = UUID()
    var name = ""
    /// Factory serial number (UID) in hex, e.g. "04:A2:3F:…".
    var serial = ""
    /// Token of the link written on the tag, when a link domain is configured.
    var linkToken: String?
    var pairedAt = Date.now

    init(name: String, serial: String, linkToken: String?) {
        self.name = name
        self.serial = serial
        self.linkToken = linkToken
    }
}

@Model
final class WakeRecord {
    var id = UUID()
    var alarmStart = Date.now
    /// Nil when nobody scanned and the emergency exit ended the chain.
    var stoppedAt: Date?

    init(alarmStart: Date, stoppedAt: Date?) {
        self.alarmStart = alarmStart
        self.stoppedAt = stoppedAt
    }

    var result: WakeResult {
        WakeResult(start: alarmStart, secondsToScan: stoppedAt.map { $0.timeIntervalSince(alarmStart) })
    }
}
