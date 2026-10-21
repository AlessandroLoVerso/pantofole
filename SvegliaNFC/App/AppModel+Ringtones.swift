import Foundation
import SvegliaCore

extension AppModel {
    /// The ringtone of the alarm ringing now; the trial alarm uses `testAlarmSound`.
    func ringingSoundName(start: Date, now: Date = .now) -> String {
        let item = alarms.first {
            $0.isEnabled
                && Occurrences.active(rule: $0.rule, armedAt: $0.armedAt, now: now, chain: AppConfig.chain) == start
        }
        return item?.soundName ?? testAlarmSound
    }

    /// Moves every alarm ringing with `old` to `new` (e.g. when one of the user's songs is deleted)
    /// and re-registers them with AlarmKit.
    func replaceSound(_ old: String, with new: String) async {
        let affected = alarms.filter { $0.soundName == old }
        guard !affected.isEmpty else { return }
        for item in affected {
            item.soundName = new
        }
        await refresh()
    }

    /// Once: alarms created when the built-in "Pulsar" was the default move to the iPhone alarm sound,
    /// now the default.
    func switchExistingAlarmsToIPhoneSound() {
        let key = "alarmsSwitchedToIPhoneSound"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for item in alarms {
            item.soundName = RingtoneCatalog.systemSoundName
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// The sound of the trial alarm: the one chosen in Settings.
    var testAlarmSound: String {
        RingtoneCatalog.preferredSoundName
    }

    /// The sound chosen in Settings applies to every alarm and to the new ones.
    func setSoundForAllAlarms(_ soundName: String) async {
        RingtoneCatalog.preferredSoundName = soundName
        for item in alarms {
            item.soundName = soundName
        }
        await refresh()
    }
}
