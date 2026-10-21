#if DEBUG
import Foundation
import SvegliaCore
import SwiftData

/// Plausible nights and mornings for the simulator (whose microphone hears nothing).
/// Launch with `-seedSleepData`, or use the button in the sleep history (debug builds only).
enum SleepSampleData {
    static func seed(into context: ModelContext, nights: Int = 21, now: Date = .now) {
        let existing = (try? context.fetchCount(FetchDescriptor<SleepSession>())) ?? 0
        guard existing == 0 else { return }
        var random = SeededRandom(seed: 7)
        let calendar = Calendar.current
        for daysAgo in 0..<nights {
            guard let morning = calendar.date(byAdding: .day, value: -daysAgo, to: now),
                  let alarm = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: morning),
                  alarm < now
            else { continue }
            let bedtimeMinutes = 380 + Int(random.next() % 140)
            let start = alarm.addingTimeInterval(-Double(bedtimeMinutes) * 60)
            let minutes = night(length: bedtimeMinutes, random: &random)
            let session = SleepSession(start: start)
            session.minutesData = SleepCodec.encode(minutes)
            session.eventsData = SleepCodec.encode(events(in: minutes, random: &random))
            context.insert(session)
            session.close(at: alarm.addingTimeInterval(30))

            let roll = random.next() % 10
            let seconds: TimeInterval? = roll == 0 ? nil : Double(25 + random.next() % (roll < 7 ? 90 : 500))
            context.insert(WakeRecord(alarmStart: alarm, stoppedAt: seconds.map { alarm.addingTimeInterval($0) }))
        }
        try? context.save()
    }

    private static func night(length: Int, random: inout SeededRandom) -> [SleepMinute] {
        let fallAsleep = 8 + Int(random.next() % 25)
        let awakeAt = Int(random.next() % 3) == 0 ? Int(random.next() % UInt64(length)) : -1
        let snoreFrom = Int(random.next() % UInt64(length))
        let snoreLength = Int(random.next() % 50)
        return (0..<length).map { i in
            let cyclePosition = Double((i - fallAsleep) % 90) / 90
            let lightness = 0.5 + 0.5 * cos(cyclePosition * 2 * .pi)
            var minute = SleepMinute(level: 0.5 + lightness * 2, peak: 3 + lightness * 6)
            if i < fallAsleep || i >= length - 6 || (awakeAt...(awakeAt + 4)).contains(i) {
                minute.events = 3 + Int(random.next() % 4)
                minute.level = 5 + Double(random.next() % 4)
                minute.peak = 18 + Double(random.next() % 10)
            } else if lightness > 0.75, random.next() % 3 == 0 {
                minute.events = 1 + Int(random.next() % 2)
            }
            if (snoreFrom..<(snoreFrom + snoreLength)).contains(i), i > fallAsleep { minute.snoring = true }
            if random.next() % 160 == 0 { minute.coughs = 1 }
            if random.next() % 240 == 0 { minute.noises = 1 }
            if random.next() % 400 == 0 { minute.talking = true }
            return minute
        }
    }

    private static func events(in minutes: [SleepMinute], random: inout SeededRandom) -> [SleepEvent] {
        var events: [SleepEvent] = []
        for (i, minute) in minutes.enumerated() {
            let offset = Double(i * 60) + Double(random.next() % 60)
            if minute.snoring, i == 0 || !minutes[i - 1].snoring { events.append(SleepEvent(offset: Double(i * 60), kind: .snoring)) }
            if minute.coughs > 0 { events.append(SleepEvent(offset: offset, kind: .cough)) }
            if minute.noises > 0 { events.append(SleepEvent(offset: offset, kind: .noise)) }
            if minute.talking { events.append(SleepEvent(offset: offset, kind: .talking)) }
        }
        return events
    }
}

private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
#endif
