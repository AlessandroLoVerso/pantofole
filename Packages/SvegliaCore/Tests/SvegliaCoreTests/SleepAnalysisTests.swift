import Foundation
import Testing
@testable import SvegliaCore

private let quiet = SleepMinute(level: 1, peak: 3)
private let restless = SleepMinute(level: 6, peak: 20, events: 4)
private let snoring = SleepMinute(level: 9, peak: 14, events: 6, snoring: true)
private let bedtime = Date(timeIntervalSince1970: 1_792_000_000)

private func minutes(_ parts: (SleepMinute, Int)...) -> [SleepMinute] {
    parts.flatMap { Array(repeating: $0.0, count: $0.1) }
}

@Suite struct SleepAnalysisTests {
    @Test func findsOnsetFinalWakeAndAwakenings() {
        let night = minutes((restless, 20), (quiet, 200), (restless, 5), (quiet, 200), (restless, 10))
        let report = SleepAnalysis.analyze(night, start: bedtime)
        #expect(report.fellAsleep == bedtime.addingTimeInterval(20 * 60))
        #expect(report.wokeUp == bedtime.addingTimeInterval(425 * 60))
        #expect(report.minutesInBed == 435)
        #expect(report.awakenings == 1)
        #expect(report.minutesAsleep == 400)
        #expect(report.phases.prefix(20).allSatisfy { $0 == .awake })
        #expect(report.phases[100] == .deep)
        #expect(report.phases[222] == .awake)
        #expect(report.phases[430] == .awake)
    }

    @Test func shortRestlessBlipsAreLightSleepNotAwakenings() {
        let night = minutes((quiet, 100), (restless, 2), (quiet, 100))
        let report = SleepAnalysis.analyze(night, start: bedtime)
        #expect(report.awakenings == 0)
        #expect(report.minutesAsleep == 202)
        #expect(report.phases[100] == .light)
        #expect(report.phases[95] == .light)
        #expect(report.phases[50] == .deep)
    }

    @Test func snoringCountsAsAsleep() {
        let night = minutes((restless, 10), (snoring, 60), (quiet, 300))
        let report = SleepAnalysis.analyze(night, start: bedtime)
        #expect(report.fellAsleep == bedtime.addingTimeInterval(10 * 60))
        #expect(report.snoringMinutes == 60)
        #expect(report.awakenings == 0)
    }

    @Test func aNightThatNeverGetsQuietHasNoSleep() {
        let report = SleepAnalysis.analyze(minutes((restless, 120)), start: bedtime)
        #expect(report.fellAsleep == nil)
        #expect(report.minutesAsleep == 0)
        #expect(report.quality == 0)
        #expect(report.phases.allSatisfy { $0 == .awake })
    }

    @Test func qualityRewardsLongCalmContinuousSleep() {
        #expect(SleepAnalysis.quality(minutesAsleep: 450, minutesInBed: 480, restlessness: 0, awakenings: 0, snoringMinutes: 0) == 100)
        let short = SleepAnalysis.quality(minutesAsleep: 225, minutesInBed: 250, restlessness: 0, awakenings: 0, snoringMinutes: 0)
        #expect(short == 80)
        let broken = SleepAnalysis.quality(minutesAsleep: 450, minutesInBed: 600, restlessness: 0.4, awakenings: 4, snoringMinutes: 225)
        // 40 + 25 × (0.75 − 0.6)/0.3 − 10
        #expect(broken == 43)
    }

    @Test func goodNightScoresHigherThanBrokenNight() {
        let good = SleepAnalysis.analyze(minutes((restless, 10), (quiet, 460), (restless, 5)), start: bedtime)
        let bad = SleepAnalysis.analyze(
            minutes((restless, 60), (quiet, 60), (restless, 10), (quiet, 60), (restless, 10), (quiet, 60), (restless, 30)),
            start: bedtime
        )
        #expect(good.quality >= 90)
        #expect(bad.quality < 60)
    }

    @Test func minutesAndEventsRoundTripThroughTheCodec() {
        let night = [quiet, restless, snoring, SleepMinute(level: 3.5, peak: 40, events: 300, talking: true, coughs: 2, noises: 1)]
        let decoded = SleepCodec.decodeMinutes(SleepCodec.encode(night))
        #expect(decoded.count == 4)
        #expect(decoded[0] == quiet)
        #expect(decoded[2] == snoring)
        #expect(decoded[3].events == 255)
        #expect(decoded[3].talking && decoded[3].coughs == 2 && decoded[3].level == 3.5)
        let events = [SleepEvent(offset: 61, kind: .cough), SleepEvent(offset: 30_000, kind: .talking)]
        #expect(SleepCodec.decodeEvents(SleepCodec.encode(events)) == events)
        #expect(SleepCodec.decodeMinutes(Data()) == [])
    }

    @Test func minuteBuilderAdaptsToTheRoomAndCountsEvents() {
        var builder = MinuteBuilder()
        // A fan at −50 dBFS: after a while it is the new silence.
        for _ in 0..<600 { builder.add(rmsDB: -50, peakDB: -45) }
        #expect(abs((builder.floor ?? 0) + 50) < 0.5)
        _ = builder.finishMinute()
        for _ in 0..<100 { builder.add(rmsDB: -50, peakDB: -45) }
        // Two rustles, each a few buffers long.
        for _ in 0..<3 { builder.add(rmsDB: -38, peakDB: -30) }
        for _ in 0..<10 { builder.add(rmsDB: -50, peakDB: -45) }
        for _ in 0..<3 { builder.add(rmsDB: -38, peakDB: -30) }
        for _ in 0..<5 { builder.addSnoring() }
        let minute = builder.finishMinute()
        #expect(minute.events == 2)
        #expect(minute.snoring)
        #expect(minute.peak > 15)
        #expect(minute.level < 3)
    }
}

@Suite struct DailyScoreTests {
    private let rome: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        rome.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func wakeScoreFavoursAFastScan() {
        #expect(DailyScore.wakeScore(secondsToScan: 45) == 100)
        #expect(DailyScore.wakeScore(secondsToScan: 360) == 70)
        #expect(DailyScore.wakeScore(secondsToScan: 1_500) == 40)
        #expect(DailyScore.wakeScore(secondsToScan: nil) == 15)
    }

    @Test func combinesTwoThirdsSleepAndOneThirdWake() {
        #expect(DailyScore.combine(sleepQuality: 90, wakeScore: 60) == 80)
        #expect(DailyScore.combine(sleepQuality: 72, wakeScore: nil) == 72)
        #expect(DailyScore.combine(sleepQuality: nil, wakeScore: 100) == 100)
        #expect(DailyScore.combine(sleepQuality: nil, wakeScore: nil) == nil)
    }

    @Test func groupsNightsAndWakesByDay() {
        let nights = [
            DailyScore.Night(end: date(21, 7, 2), quality: 90, minutesAsleep: 460),
            DailyScore.Night(end: date(20, 7, 1), quality: 50, minutesAsleep: 300),
        ]
        let wakes = [
            WakeResult(start: date(21, 7), secondsToScan: 40),
            WakeResult(start: date(20, 7), secondsToScan: 400),
            WakeResult(start: date(19, 7), secondsToScan: nil),
        ]
        let days = DailyScore.days(nights: nights, wakes: wakes, calendar: rome)
        #expect(days.map(\.day) == [date(21, 0), date(20, 0), date(19, 0)])
        #expect(days[0].score == 93)
        #expect(days[0].note == .great)
        #expect(days[1].note == .shortSleep)
        #expect(days[2].score == 15)
        #expect(days[2].sleepQuality == nil)
        #expect(days[2].note == .missedWake)
    }

    @Test func bestStreakIsTheLongestRun() {
        let results = [40.0, 30, nil, 20, 25, 35, nil, 10].enumerated().map { i, seconds in
            WakeResult(start: date(10 + i, 7), secondsToScan: seconds)
        }
        #expect(DailyScore.bestStreak(results) == 3)
        #expect(DailyScore.bestStreak([]) == 0)
    }

    @Test func placementNeedsMovementToStandOut() {
        #expect(PlacementCheck.isGood(floorDB: -60, loudestDB: -42))
        #expect(!PlacementCheck.isGood(floorDB: -60, loudestDB: -55))
    }
}
