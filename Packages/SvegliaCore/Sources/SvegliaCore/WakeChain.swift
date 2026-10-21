import Foundation

/// The anti-snooze mechanism: one alarm becomes a chain of rings, one every `interval`,
/// until the tag is scanned or `duration` runs out (the emergency exit).
///
/// iOS lets anyone silence a single alarm with the Stop button or a hardware key,
/// so the next ring of the chain is already scheduled with the system before that happens.
public struct WakeChain: Sendable, Equatable {
    public static let standard = WakeChain(interval: 60, duration: 30 * 60)

    public let interval: TimeInterval
    public let duration: TimeInterval

    public init(interval: TimeInterval, duration: TimeInterval) {
        precondition(interval > 0 && duration >= interval)
        self.interval = interval
        self.duration = duration
    }

    /// Every ring of the chain that starts at `start`, the first one included.
    public func rings(from start: Date) -> [Date] {
        let count = Int((duration / interval).rounded(.up))
        return (0..<count).map { start.addingTimeInterval(Double($0) * interval) }
    }

    /// The rings of the chain still to come after `now`.
    public func remainingRings(from start: Date, after now: Date) -> [Date] {
        rings(from: start).filter { $0 > now }
    }

    /// The moment the emergency exit kicks in and the chain stops on its own.
    public func end(of start: Date) -> Date {
        start.addingTimeInterval(duration)
    }

    public func contains(_ date: Date, start: Date) -> Bool {
        date >= start && date < end(of: start)
    }
}

/// Which rings of an alarm count, given when the user last switched it on or changed it.
///
/// A ring earlier than `armedAt` never counts: turning on a 7:00 alarm at 7:10 must not start
/// a chain that is already ten minutes in.
public enum Occurrences {
    /// The ring whose chain is running at `now`, if any.
    public static func active(
        rule: AlarmRule,
        armedAt: Date,
        now: Date,
        chain: WakeChain,
        calendar: Calendar = .current
    ) -> Date? {
        let start: Date?
        if rule.repeats {
            start = rule.previousStart(atOrBefore: now, calendar: calendar)
        } else {
            start = rule.nextStart(after: armedAt, calendar: calendar)
        }
        guard let start, start >= armedAt, chain.contains(now, start: start) else { return nil }
        return start
    }

    /// The next `count` rings strictly after `now`. A one-off alarm has at most one.
    public static func upcoming(
        rule: AlarmRule,
        armedAt: Date,
        now: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard rule.repeats else {
            guard let start = rule.nextStart(after: armedAt, calendar: calendar), start > now else { return [] }
            return [start]
        }
        var result: [Date] = []
        var cursor = max(now, armedAt.addingTimeInterval(-1))
        while result.count < count, let next = rule.nextStart(after: cursor, calendar: calendar) {
            result.append(next)
            cursor = next
        }
        return result
    }

    /// Whether a one-off alarm has already rung and its chain is over, so it can be switched off.
    public static func isFinished(
        rule: AlarmRule,
        armedAt: Date,
        now: Date,
        chain: WakeChain,
        calendar: Calendar = .current
    ) -> Bool {
        guard !rule.repeats, let start = rule.nextStart(after: armedAt, calendar: calendar) else { return false }
        return now >= chain.end(of: start)
    }
}
