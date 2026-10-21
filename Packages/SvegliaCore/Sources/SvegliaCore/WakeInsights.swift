import Foundation

/// One morning: when the alarm started and how long it took to reach the tag.
/// `secondsToScan == nil` means nobody scanned and the emergency exit ended the chain.
public struct WakeResult: Sendable, Equatable {
    public let start: Date
    public let secondsToScan: TimeInterval?

    public init(start: Date, secondsToScan: TimeInterval?) {
        self.start = start
        self.secondsToScan = secondsToScan
    }
}

public enum WakeInsights {
    /// Consecutive mornings, most recent first, on which the user got up and scanned the tag.
    public static func streak(_ results: [WakeResult]) -> Int {
        results
            .sorted { $0.start > $1.start }
            .prefix { $0.secondsToScan != nil }
            .count
    }

    /// A tag reached within a few seconds, several mornings in a row, is probably within reach of the bed.
    public static func tagSeemsTooClose(
        _ results: [WakeResult],
        threshold: TimeInterval = 15,
        mornings: Int = 3
    ) -> Bool {
        let recent = results.sorted { $0.start > $1.start }.prefix(mornings)
        guard recent.count == mornings else { return false }
        return recent.allSatisfy { ($0.secondsToScan ?? .infinity) < threshold }
    }
}

/// Bedtime advice based on 90-minute sleep cycles, plus about a quarter of an hour to fall asleep.
public enum Bedtime {
    public static let cycle: TimeInterval = 90 * 60
    public static let fallingAsleep: TimeInterval = 15 * 60
    public static let recommendedCycles = 5

    public static func suggestion(forWakeUp wake: Date, cycles: Int = recommendedCycles) -> Date {
        wake.addingTimeInterval(-(Double(cycles) * cycle + fallingAsleep))
    }
}
