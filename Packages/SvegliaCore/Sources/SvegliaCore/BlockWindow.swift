import Foundation

/// The daily time window of an app block ("Notte" 23:00–07:00): when it starts, when it ends and on
/// which days. A window that ends at or before its start crosses midnight; its weekday is the day it starts.
public struct BlockWindow: Sendable, Equatable, Hashable, Codable {
    /// Screen Time refuses schedules shorter than this.
    public static let minimumDuration: TimeInterval = 15 * 60

    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) on which the window starts. Empty means every day.
    public var weekdays: Set<Int>

    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, weekdays: Set<Int> = []) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.weekdays = weekdays
    }

    public var startsEveryDay: Bool { weekdays.isEmpty || weekdays == Set(1...7) }

    public var crossesMidnight: Bool {
        endHour * 60 + endMinute <= startHour * 60 + startMinute
    }

    /// Length in minutes, ignoring daylight-saving jumps (1...1440).
    public var durationMinutes: Int {
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        let length = (end - start + 1440) % 1440
        return length == 0 ? 1440 : length
    }

    public var isValid: Bool {
        TimeInterval(durationMinutes * 60) >= Self.minimumDuration
    }

    /// The weekday on which a window starting on `weekday` ends.
    public func endWeekday(forStart weekday: Int) -> Int {
        crossesMidnight ? weekday % 7 + 1 : weekday
    }

    /// The occurrence of the window that contains `now`, if any.
    public func currentInterval(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let interval = interval(startingOn: day, calendar: calendar)
            else { continue }
            if interval.start <= now && now < interval.end { return interval }
        }
        return nil
    }

    /// The next occurrence that starts after `now` (within a week).
    public func nextInterval(after now: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let interval = interval(startingOn: day, calendar: calendar)
            else { continue }
            if interval.start > now { return interval }
        }
        return nil
    }

    /// The occurrence starting on the calendar day of `day`, or nil when the window doesn't run that day.
    public func interval(startingOn day: Date, calendar: Calendar = .current) -> DateInterval? {
        let weekday = calendar.component(.weekday, from: day)
        guard startsEveryDay || weekdays.contains(weekday),
              let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day)
        else { return nil }
        let endDay = crossesMidnight ? calendar.date(byAdding: .day, value: 1, to: day) ?? day : day
        guard let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: endDay),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}
