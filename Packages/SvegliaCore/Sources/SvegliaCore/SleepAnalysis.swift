import Foundation

// Sleep tracking from sound, analysed on the phone. Audio never leaves memory: the app only keeps
// one `SleepMinute` of numbers per minute, and everything below works on those numbers.

// MARK: - Per-minute data

/// What one minute of the night sounded like. No audio, only numbers.
public struct SleepMinute: Sendable, Equatable {
    /// Mean loudness in dB above the adaptive noise floor (0 = as quiet as the room gets).
    public var level: Double
    /// Loudest moment in dB above the noise floor.
    public var peak: Double
    /// Short noises: rustling, turning over, small movements.
    public var events: Int
    /// The on-device classifier heard snoring for a good part of the minute.
    public var snoring: Bool
    /// Speech or sleep talking.
    public var talking: Bool
    public var coughs: Int
    /// Other loud noises (a door, a car, a dog).
    public var noises: Int

    public init(level: Double = 0, peak: Double = 0, events: Int = 0, snoring: Bool = false,
                talking: Bool = false, coughs: Int = 0, noises: Int = 0) {
        self.level = level
        self.peak = peak
        self.events = events
        self.snoring = snoring
        self.talking = talking
        self.coughs = coughs
        self.noises = noises
    }
}

/// Something worth listing in the night detail. Time only, never audio.
public struct SleepEvent: Sendable, Equatable {
    public enum Kind: UInt8, Sendable, CaseIterable {
        case snoring, talking, cough, noise
    }

    /// Seconds from the start of the session.
    public let offset: TimeInterval
    public let kind: Kind

    public init(offset: TimeInterval, kind: Kind) {
        self.offset = offset
        self.kind = kind
    }
}

/// Compact storage: 6 bytes per minute (a full night is about 3 KB), 5 bytes per event.
public enum SleepCodec {
    private static let version: UInt8 = 1

    public static func encode(_ minutes: [SleepMinute]) -> Data {
        var data = Data([version])
        data.reserveCapacity(1 + minutes.count * 6)
        for minute in minutes {
            let flags: UInt8 = (minute.snoring ? 1 : 0) | (minute.talking ? 2 : 0)
            data.append(contentsOf: [
                halfDB(minute.level), halfDB(minute.peak), byte(minute.events),
                byte(minute.coughs), byte(minute.noises), flags,
            ])
        }
        return data
    }

    public static func decodeMinutes(_ data: Data) -> [SleepMinute] {
        let bytes = [UInt8](data)
        guard bytes.first == version else { return [] }
        return stride(from: 1, to: bytes.count - 5, by: 6).map { (i: Int) -> SleepMinute in
            let flags: UInt8 = bytes[i + 5]
            return SleepMinute(
                level: Double(bytes[i]) / 2, peak: Double(bytes[i + 1]) / 2, events: Int(bytes[i + 2]),
                snoring: flags & 1 != 0, talking: flags & 2 != 0,
                coughs: Int(bytes[i + 3]), noises: Int(bytes[i + 4])
            )
        }
    }

    public static func encode(_ events: [SleepEvent]) -> Data {
        var data = Data([version])
        for event in events {
            let seconds = UInt32(clamping: Int(max(0, event.offset).rounded()))
            data.append(contentsOf: withUnsafeBytes(of: seconds.littleEndian, Array.init))
            data.append(event.kind.rawValue)
        }
        return data
    }

    public static func decodeEvents(_ data: Data) -> [SleepEvent] {
        let bytes = [UInt8](data)
        guard bytes.first == version else { return [] }
        return stride(from: 1, to: bytes.count - 4, by: 5).compactMap { i in
            var seconds = UInt32(bytes[i])
            seconds |= UInt32(bytes[i + 1]) << 8
            seconds |= UInt32(bytes[i + 2]) << 16
            seconds |= UInt32(bytes[i + 3]) << 24
            return SleepEvent.Kind(rawValue: bytes[i + 4]).map { SleepEvent(offset: TimeInterval(seconds), kind: $0) }
        }
    }

    private static func halfDB(_ value: Double) -> UInt8 { UInt8(clamping: Int((max(0, value) * 2).rounded())) }
    private static func byte(_ value: Int) -> UInt8 { UInt8(clamping: value) }
}

// MARK: - From audio levels to minutes

/// Turns a stream of short audio measurements (one per buffer, ~0.1 s) into `SleepMinute`s.
/// The noise floor follows the room: it drops at once to quieter levels and rises slowly (about a minute
/// with ~0.1 s buffers),
/// so a fan or white noise becomes the new "silence" instead of counting as noise all night.
public struct MinuteBuilder: Sendable {
    /// dB above the floor that starts a short noise event; it must fall below `eventEnd` before the next one.
    public var eventStart: Double = 8
    public var eventEnd: Double = 4
    /// dB above the floor for a sound to count as a loud noise.
    public var loudNoise: Double = 25
    /// Classifier windows (~1.5 s each, half overlapping) of snoring needed to call the minute "snoring".
    public var snoringWindows = 4

    public private(set) var floor: Double?
    private var inEvent = false
    private var energySum = 0.0
    private var count = 0
    private var peak = 0.0
    private var events = 0
    private var snoreHits = 0
    private var talking = false
    private var coughs = 0
    private var noises = 0

    public init() {}

    /// One audio buffer, in dBFS. Returns true when a short noise event starts with this buffer.
    @discardableResult
    public mutating func add(rmsDB: Double, peakDB: Double) -> Bool {
        let current = floor ?? rmsDB
        // Fast down, slow up (time constant ~ 500 buffers).
        let newFloor = rmsDB < current ? current + (rmsDB - current) * 0.3 : current + (rmsDB - current) * 0.002
        floor = newFloor
        let above = max(0, rmsDB - newFloor)
        energySum += pow(10, above / 10)
        count += 1
        peak = max(peak, peakDB - newFloor)
        if !inEvent, above >= eventStart {
            inEvent = true
            events += 1
            return true
        }
        if inEvent, above < eventEnd { inEvent = false }
        return false
    }

    /// dB above the floor of the latest buffer-sized measurement.
    public func loudness(of rmsDB: Double) -> Double { max(0, rmsDB - (floor ?? rmsDB)) }

    public mutating func addSnoring() { snoreHits += 1 }
    public mutating func addTalking() { talking = true }
    public mutating func addCough() { coughs += 1 }
    public mutating func addNoise() { noises += 1 }

    /// Closes the minute and starts the next one (the noise floor is kept).
    public mutating func finishMinute() -> SleepMinute {
        let level = count == 0 ? 0 : 10 * log10(energySum / Double(count))
        let minute = SleepMinute(
            level: level, peak: peak, events: events, snoring: snoreHits >= snoringWindows,
            talking: talking, coughs: coughs, noises: noises
        )
        energySum = 0
        count = 0
        peak = 0
        events = 0
        snoreHits = 0
        talking = false
        coughs = 0
        noises = 0
        return minute
    }
}

// MARK: - The night

/// Rough sleep phase from sound and movement only. An estimate, not a medical measure.
public enum SleepPhase: UInt8, Sendable, CaseIterable {
    case awake, light, deep
}

public struct SleepReport: Sendable, Equatable {
    public let start: Date
    public let end: Date
    /// When sustained quiet began. Nil when the night never got quiet.
    public let fellAsleep: Date?
    /// End of the last quiet stretch.
    public let wokeUp: Date?
    public let minutesInBed: Int
    public let minutesAsleep: Int
    /// Restless stretches (3+ minutes) between falling asleep and the final awakening.
    public let awakenings: Int
    /// Share of the sleep window with movement or noise, 0...1.
    public let restlessness: Double
    public let snoringMinutes: Int
    /// One phase per minute of the session.
    public let phases: [SleepPhase]
    /// 0...100, see `SleepAnalysis.quality`.
    public let quality: Int
}

public enum SleepAnalysis {
    /// A minute with at most this much activity is quiet.
    public static let quietActivity = 1.0
    /// A minute with at least this much activity is restless.
    public static let restlessActivity = 3.0
    /// Quiet minutes in a row that mean "asleep".
    public static let onsetMinutes = 10
    /// The last quiet stretch of at least this many minutes ends the night.
    public static let finalQuietMinutes = 5
    /// Restless minutes in a row that count as an awakening.
    public static let awakeningMinutes = 3
    /// Half-width of the window used to call a stretch "deep" (15 minutes in total).
    public static let deepHalfWindow = 7
    public static let deepActivity = 0.4
    /// Full marks for duration from this much sleep (7.5 h, five cycles).
    public static let idealSleepMinutes = 450

    /// How "awake" a minute sounds. Snoring means asleep, so it counts very little.
    /// activity = events + coughs + 0.5·noises + 3 if talking + (level − 3 dB)/3
    public static func activity(_ minute: SleepMinute) -> Double {
        if minute.snoring { return 0.5 }
        return Double(minute.events) + Double(minute.coughs) + Double(minute.noises) * 0.5
            + (minute.talking ? 3 : 0) + max(0, minute.level - 3) / 3
    }

    public static func analyze(_ minutes: [SleepMinute], start: Date) -> SleepReport {
        let end = start.addingTimeInterval(Double(minutes.count) * 60)
        let activity = minutes.map(Self.activity)
        let quiet = activity.map { $0 <= quietActivity }

        guard let onset = firstRun(of: onsetMinutes, in: quiet) else {
            return SleepReport(
                start: start, end: end, fellAsleep: nil, wokeUp: nil, minutesInBed: minutes.count,
                minutesAsleep: 0, awakenings: 0, restlessness: minutes.isEmpty ? 0 : 1,
                snoringMinutes: minutes.filter(\.snoring).count,
                phases: Array(repeating: .awake, count: minutes.count), quality: 0
            )
        }
        let finalWake = lastRunEnd(of: finalQuietMinutes, in: quiet, from: onset)
        let window = onset..<finalWake

        // Awakenings: runs of restless minutes inside the sleep window.
        var awakeInside = Set<Int>()
        var awakenings = 0
        var run: [Int] = []
        for i in window {
            if activity[i] >= restlessActivity {
                run.append(i)
            } else {
                if run.count >= awakeningMinutes { awakenings += 1; awakeInside.formUnion(run) }
                run = []
            }
        }
        if run.count >= awakeningMinutes { awakenings += 1; awakeInside.formUnion(run) }

        var phases = Array(repeating: SleepPhase.awake, count: minutes.count)
        for i in window where !awakeInside.contains(i) {
            let around = max(window.lowerBound, i - deepHalfWindow)...min(window.upperBound - 1, i + deepHalfWindow)
            let mean = around.map { activity[$0] }.reduce(0, +) / Double(around.count)
            phases[i] = mean <= deepActivity && quiet[i] ? .deep : .light
        }

        let asleep = window.count - awakeInside.count
        let restless = Double(window.filter { !quiet[$0] }.count) / Double(window.count)
        let snoring = window.filter { minutes[$0].snoring }.count
        return SleepReport(
            start: start, end: end,
            fellAsleep: start.addingTimeInterval(Double(onset) * 60),
            wokeUp: start.addingTimeInterval(Double(finalWake) * 60),
            minutesInBed: minutes.count, minutesAsleep: asleep, awakenings: awakenings,
            restlessness: restless, snoringMinutes: snoring, phases: phases,
            quality: quality(minutesAsleep: asleep, minutesInBed: minutes.count, restlessness: restless,
                             awakenings: awakenings, snoringMinutes: snoring)
        )
    }

    /// Sleep quality, 0...100:
    /// 40 × duration (asleep / 7.5 h, capped) + 25 × efficiency ((asleep/in bed − 60%) / 30%, capped)
    /// + 20 × calm (1 − restlessness / 40%) + 15 × continuity (1 − awakenings / 4)
    /// − snoring (up to 10 points, reached when snoring half of the time asleep).
    public static func quality(minutesAsleep: Int, minutesInBed: Int, restlessness: Double,
                               awakenings: Int, snoringMinutes: Int) -> Int {
        guard minutesAsleep > 0, minutesInBed > 0 else { return 0 }
        let duration = clamp(Double(minutesAsleep) / Double(idealSleepMinutes))
        let efficiency = clamp((Double(minutesAsleep) / Double(minutesInBed) - 0.6) / 0.3)
        let calm = 1 - clamp(restlessness / 0.4)
        let continuity = 1 - clamp(Double(awakenings) / 4)
        let snoring = min(10, Double(snoringMinutes) / Double(minutesAsleep) * 20)
        let score = 40 * duration + 25 * efficiency + 20 * calm + 15 * continuity - snoring
        return Int(score.rounded()).clamped(to: 0...100)
    }

    private static func firstRun(of length: Int, in flags: [Bool]) -> Int? {
        var count = 0
        for (i, flag) in flags.enumerated() {
            count = flag ? count + 1 : 0
            if count == length { return i - length + 1 }
        }
        return nil
    }

    /// Index right after the last run of `length` true values starting at or after `from`.
    private static func lastRunEnd(of length: Int, in flags: [Bool], from: Int) -> Int {
        var count = 0
        var end = from + length
        for i in from..<flags.count {
            count = flags[i] ? count + 1 : 0
            if count >= length { end = i + 1 }
        }
        return end
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - Daily score

/// One day's score: the night's sleep quality (when it was tracked) and how the morning went.
public struct DayScore: Sendable, Equatable {
    /// What the one-line explanation on Home talks about.
    public enum Note: Sendable, Equatable {
        case great, good, shortSleep, restlessNight, slowWake, missedWake
    }

    /// Start of the calendar day.
    public let day: Date
    public let score: Int
    public let sleepQuality: Int?
    public let minutesAsleep: Int?
    public let wakeScore: Int?
    public let note: Note
}

public enum DailyScore {
    /// What a night contributes to its day (the day the session ended).
    public struct Night: Sendable, Equatable {
        public let end: Date
        public let quality: Int
        public let minutesAsleep: Int

        public init(end: Date, quality: Int, minutesAsleep: Int) {
            self.end = end
            self.quality = quality
            self.minutesAsleep = minutesAsleep
        }
    }

    /// Wake-up score, 0...100: tag scanned within a minute = 100, then −6 points per extra minute
    /// down to 40; nobody scanned (emergency exit after 30 minutes) = 15.
    public static func wakeScore(secondsToScan: TimeInterval?) -> Int {
        guard let seconds = secondsToScan else { return 15 }
        guard seconds > 60 else { return 100 }
        return max(40, Int((100 - (seconds - 60) / 10).rounded()))
    }

    /// Two thirds sleep quality, one third wake-up; just one of them when the other is missing.
    public static func combine(sleepQuality: Int?, wakeScore: Int?) -> Int? {
        switch (sleepQuality, wakeScore) {
        case let (sleep?, wake?): Int((Double(sleep) * 2 / 3 + Double(wake) / 3).rounded())
        case let (sleep?, nil): sleep
        case let (nil, wake?): wake
        case (nil, nil): nil
        }
    }

    /// Scores per day, most recent first. A night counts for the day it ended (the longest one if
    /// several), a wake-up for the day its alarm rang (the first one if several).
    public static func days(nights: [Night], wakes: [WakeResult], calendar: Calendar = .current) -> [DayScore] {
        var nightByDay: [Date: Night] = [:]
        for night in nights {
            let day = calendar.startOfDay(for: night.end)
            if let other = nightByDay[day], other.minutesAsleep >= night.minutesAsleep { continue }
            nightByDay[day] = night
        }
        var wakeByDay: [Date: WakeResult] = [:]
        for wake in wakes {
            let day = calendar.startOfDay(for: wake.start)
            if let other = wakeByDay[day], other.start <= wake.start { continue }
            wakeByDay[day] = wake
        }
        return Set(nightByDay.keys).union(wakeByDay.keys).sorted(by: >).compactMap { (day: Date) -> DayScore? in
            let night = nightByDay[day]
            let wake = wakeByDay[day]
            let wakeScore: Int? = wake.map { Self.wakeScore(secondsToScan: $0.secondsToScan) }
            guard let score = combine(sleepQuality: night?.quality, wakeScore: wakeScore) else { return nil }
            return DayScore(
                day: day, score: score, sleepQuality: night?.quality, minutesAsleep: night?.minutesAsleep,
                wakeScore: wakeScore,
                note: note(score: score, night: night, wake: wake, wakeScore: wakeScore)
            )
        }
    }

    /// The weakest part of the day, or praise when nothing stands out.
    static func note(score: Int, night: Night?, wake: WakeResult?, wakeScore: Int?) -> DayScore.Note {
        if let wake, wake.secondsToScan == nil { return .missedWake }
        if let night, night.minutesAsleep < 6 * 60 { return .shortSleep }
        if let night, night.quality < 60 { return .restlessNight }
        if let wakeScore, wakeScore < 70 { return .slowWake }
        return score >= 85 ? .great : .good
    }

    /// Longest run of consecutive mornings (in alarm order) on which the tag was scanned.
    public static func bestStreak(_ results: [WakeResult]) -> Int {
        var best = 0
        var current = 0
        for result in results.sorted(by: { $0.start < $1.start }) {
            current = result.secondsToScan == nil ? 0 : current + 1
            best = max(best, current)
        }
        return best
    }
}

// MARK: - Phone placement

/// The 10-second test before the first night: the user moves a little under the covers while the phone
/// listens. If that movement stands out from the room's noise, the microphone is close enough.
public enum PlacementCheck {
    public static let minimumContrast = 10.0

    /// `floorDB` and `loudestDB` in dBFS, measured over the test.
    public static func isGood(floorDB: Double, loudestDB: Double) -> Bool {
        loudestDB - floorDB >= minimumContrast
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
