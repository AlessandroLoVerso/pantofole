#if DEBUG
import Foundation
import SwiftData

extension AppModel {
    /// Launch with `-seedDemo` (debug builds only) for App Store screenshots: two alarms and a
    /// paired tag, which in the Simulator is the fake one every scan returns. Add `-noTag` to skip
    /// the tag (alarms then ring with the math mission) and `-ringTest` to start the trial alarm.
    func seedDemoData() {
        guard alarms.isEmpty else { return }
        let context = container.mainContext
        context.insert(AlarmItem(hour: 7, minute: 0, weekdays: Array(2...6)))
        context.insert(AlarmItem(hour: 9, minute: 30, weekdays: [7, 1], label: String(localized: "Con calma")))
        if tags.isEmpty, !ProcessInfo.processInfo.arguments.contains("-noTag") {
            context.insert(PairedTag(name: String(localized: "Bagno"), serial: TagScanner.simulatorSerial, linkToken: nil))
        }
        try? context.save()
    }
}
#endif
