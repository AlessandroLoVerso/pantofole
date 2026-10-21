import Foundation

/// When an alarm rings: a time of day plus the weekdays it repeats on.
///
/// Weekdays use `Calendar` numbering (1 = Sunday … 7 = Saturday). An empty set means the alarm rings once.
public struct AlarmRule: Hashable, Sendable, Codable {
    public var hour: Int
    public var minute: Int
    public var weekdays: Set<Int>

    public init(hour: Int, minute: Int, weekdays: Set<Int> = []) {
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
    }

    public var repeats: Bool { !weekdays.isEmpty }

    /// The first ring strictly after `date`.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        matchingDates(calendar: calendar) { components in
            calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }.min()
    }

    /// The latest ring at or before `date`.
    public func previousStart(atOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        matchingDates(calendar: calendar) { components in
            calendar.nextDate(
                after: date.addingTimeInterval(1),
                matching: components,
                matchingPolicy: .nextTime,
                direction: .backward
            )
        }.max()
    }

    private func matchingDates(calendar: Calendar, _ search: (DateComponents) -> Date?) -> [Date] {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard repeats else { return search(components).map { [$0] } ?? [] }
        return weekdays.compactMap { weekday in
            var day = components
            day.weekday = weekday
            return search(day)
        }
    }
}
