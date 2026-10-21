import Foundation

extension AppModel {
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

    /// The sound of the trial alarm: the one of the next alarm, or the default ringtone.
    var testAlarmSound: String {
        nextAlarm()?.item.soundName
            ?? alarms.first(where: \.isEnabled)?.soundName
            ?? RingtoneCatalog.defaultSoundName
    }
}
