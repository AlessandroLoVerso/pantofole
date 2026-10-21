import Foundation

/// Stops the "switch it off the night before" escape: in the hours before an alarm, changing or
/// deleting it (or unpairing a tag) needs a scan of the tag, which unlocks edits for a few minutes.
public struct EditLock: Sendable, Equatable {
    public static let standard = EditLock(window: 8 * 3600, unlockDuration: 5 * 60)

    public let window: TimeInterval
    public let unlockDuration: TimeInterval

    public init(window: TimeInterval, unlockDuration: TimeInterval) {
        self.window = window
        self.unlockDuration = unlockDuration
    }

    public func isLocked(now: Date, nextStarts: [Date], chainRunning: Bool, unlockedUntil: Date?) -> Bool {
        if let unlockedUntil, now < unlockedUntil { return false }
        if chainRunning { return true }
        return nextStarts.contains { $0 > now && $0.timeIntervalSince(now) <= window }
    }

    public func unlockedUntil(scanAt date: Date) -> Date {
        date.addingTimeInterval(unlockDuration)
    }
}
