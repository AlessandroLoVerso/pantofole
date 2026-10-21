import Foundation
import SvegliaCore
import SwiftData

/// One tracked night. Only numbers are stored: one `SleepMinute` per minute (6 bytes) and a short list
/// of timed events. Audio is analysed in memory and never recorded, saved or sent.
@Model
final class SleepSession {
    var id = UUID()
    var start = Date.now
    /// Nil while the night is being tracked.
    var end: Date?
    /// `SleepCodec`-encoded minutes.
    var minutesData = Data()
    /// `SleepCodec`-encoded events.
    var eventsData = Data()
    /// Cached from the analysis when the night ends, for lists and the daily score.
    var quality = 0
    var minutesAsleep = 0

    init(start: Date) {
        self.start = start
    }

    var minutes: [SleepMinute] { SleepCodec.decodeMinutes(minutesData) }
    var events: [SleepEvent] { SleepCodec.decodeEvents(eventsData) }
    var report: SleepReport { SleepAnalysis.analyze(minutes, start: start) }

    var night: DailyScore.Night? {
        end.map { DailyScore.Night(end: $0, quality: quality, minutesAsleep: minutesAsleep) }
    }

    /// Stores the analysis of the minutes so far and closes the night.
    func close(at date: Date) {
        end = date
        let report = report
        quality = report.quality
        minutesAsleep = report.minutesAsleep
    }
}
