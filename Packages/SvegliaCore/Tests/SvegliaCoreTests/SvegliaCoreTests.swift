import Foundation
import Testing
@testable import SvegliaCore

private let rome: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    return calendar
}()

/// 2026-10-21 is a Wednesday.
private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, month: Int = 10) -> Date {
    rome.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private let monday = 2, wednesday = 4, thursday = 5, saturday = 7

@Suite struct AlarmRuleTests {
    @Test func oneOffRingsTodayWhenStillAhead() {
        let rule = AlarmRule(hour: 7, minute: 0)
        #expect(rule.nextStart(after: date(21, 6, 0), calendar: rome) == date(21, 7, 0))
    }

    @Test func oneOffRingsTomorrowWhenTimeHasPassed() {
        let rule = AlarmRule(hour: 7, minute: 0)
        #expect(rule.nextStart(after: date(21, 7, 0), calendar: rome) == date(22, 7, 0))
    }

    @Test func weeklyPicksTheNextChosenWeekday() {
        let rule = AlarmRule(hour: 7, minute: 30, weekdays: [monday, saturday])
        #expect(rule.nextStart(after: date(21, 12, 0), calendar: rome) == date(24, 7, 30))
    }

    @Test func previousStartIncludesTheExactMinute() {
        let rule = AlarmRule(hour: 7, minute: 0, weekdays: [wednesday])
        #expect(rule.previousStart(atOrBefore: date(21, 7, 0), calendar: rome) == date(21, 7, 0))
        #expect(rule.previousStart(atOrBefore: date(21, 6, 59), calendar: rome) == date(14, 7, 0))
    }

    @Test func survivesDaylightSavingChange() {
        // Clocks go back on 2026-10-25 in Rome; a 7:00 alarm still rings at 7:00 local time.
        let rule = AlarmRule(hour: 7, minute: 0, weekdays: [1, 2])
        #expect(rule.nextStart(after: date(24, 22, 0), calendar: rome) == date(25, 7, 0))
        #expect(rule.nextStart(after: date(25, 7, 0), calendar: rome) == date(26, 7, 0))
    }
}

@Suite struct WakeChainTests {
    let chain = WakeChain.standard

    @Test func standardChainRingsEveryMinuteForHalfAnHour() {
        let rings = chain.rings(from: date(21, 7, 0))
        #expect(rings.count == 30)
        #expect(rings.first == date(21, 7, 0))
        #expect(rings.last == date(21, 7, 29))
        #expect(chain.end(of: date(21, 7, 0)) == date(21, 7, 30))
    }

    @Test func remainingRingsSkipThePast() {
        let remaining = chain.remainingRings(from: date(21, 7, 0), after: date(21, 7, 27, 30))
        #expect(remaining == [date(21, 7, 28), date(21, 7, 29)])
    }

    @Test func activeOnlyInsideTheWindow() {
        let rule = AlarmRule(hour: 7, minute: 0, weekdays: [wednesday])
        let armed = date(20, 22, 0)
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(21, 7, 10), chain: chain, calendar: rome) == date(21, 7, 0))
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(21, 7, 30), chain: chain, calendar: rome) == nil)
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(21, 6, 59), chain: chain, calendar: rome) == nil)
    }

    @Test func switchingOnAfterTheRingDoesNotStartAChain() {
        let rule = AlarmRule(hour: 7, minute: 0, weekdays: [wednesday])
        let armed = date(21, 7, 10)
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(21, 7, 11), chain: chain, calendar: rome) == nil)
    }

    @Test func oneOffAlarmArmedLateRingsTomorrow() {
        let rule = AlarmRule(hour: 7, minute: 0)
        let armed = date(21, 7, 10)
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(21, 7, 11), chain: chain, calendar: rome) == nil)
        #expect(Occurrences.upcoming(rule: rule, armedAt: armed, now: date(21, 7, 11), count: 2, calendar: rome) == [date(22, 7, 0)])
        #expect(Occurrences.active(rule: rule, armedAt: armed, now: date(22, 7, 5), chain: chain, calendar: rome) == date(22, 7, 0))
    }

    @Test func oneOffAlarmFinishesAfterItsChain() {
        let rule = AlarmRule(hour: 7, minute: 0)
        let armed = date(20, 23, 0)
        #expect(!Occurrences.isFinished(rule: rule, armedAt: armed, now: date(21, 7, 29), chain: chain, calendar: rome))
        #expect(Occurrences.isFinished(rule: rule, armedAt: armed, now: date(21, 7, 30), chain: chain, calendar: rome))
    }

    @Test func upcomingListsTheNextRingsInOrder() {
        let rule = AlarmRule(hour: 7, minute: 0, weekdays: [wednesday, thursday])
        let upcoming = Occurrences.upcoming(rule: rule, armedAt: date(1, 0, 0), now: date(21, 7, 5), count: 2, calendar: rome)
        #expect(upcoming == [date(22, 7, 0), date(28, 7, 0)])
    }
}

@Suite struct EditLockTests {
    let lock = EditLock.standard

    @Test func lockedInTheEightHoursBeforeARing() {
        #expect(lock.isLocked(now: date(20, 23, 30), nextStarts: [date(21, 7, 0)], chainRunning: false, unlockedUntil: nil))
        #expect(!lock.isLocked(now: date(20, 22, 30), nextStarts: [date(21, 7, 0)], chainRunning: false, unlockedUntil: nil))
    }

    @Test func lockedWhileTheChainRuns() {
        #expect(lock.isLocked(now: date(21, 7, 5), nextStarts: [], chainRunning: true, unlockedUntil: nil))
    }

    @Test func aScanUnlocksForFiveMinutes() {
        let until = lock.unlockedUntil(scanAt: date(20, 23, 30))
        #expect(!lock.isLocked(now: date(20, 23, 34), nextStarts: [date(21, 7, 0)], chainRunning: false, unlockedUntil: until))
        #expect(lock.isLocked(now: date(20, 23, 36), nextStarts: [date(21, 7, 0)], chainRunning: false, unlockedUntil: until))
    }
}

@Suite struct TagTests {
    @Test func serialIsUppercaseHexWithColons() {
        #expect(TagSerial.hex([0x04, 0xA2, 0x3F]) == "04:A2:3F")
    }

    @Test func linkRoundTripsItsToken() {
        let link = TagLink(host: "example.com")
        let token = TagLink.makeToken()
        #expect(token.count == 22)
        #expect(!token.contains("+") && !token.contains("/") && !token.contains("="))
        let url = link.url(token: token)!
        #expect(link.token(from: url) == token)
    }

    @Test func foreignLinksAreRejected() {
        let link = TagLink(host: "example.com")
        #expect(link.token(from: URL(string: "https://other.com/t/abc")!) == nil)
        #expect(link.token(from: URL(string: "http://example.com/t/abc")!) == nil)
        #expect(link.token(from: URL(string: "https://example.com/x/abc")!) == nil)
        #expect(link.token(from: URL(string: "https://example.com/t/")!) == nil)
    }
}

@Suite struct InsightTests {
    @Test func streakStopsAtTheFirstMissedMorning() {
        let results = [
            WakeResult(start: date(21, 7, 0), secondsToScan: 80),
            WakeResult(start: date(20, 7, 0), secondsToScan: 120),
            WakeResult(start: date(19, 7, 0), secondsToScan: nil),
            WakeResult(start: date(18, 7, 0), secondsToScan: 60),
        ]
        #expect(WakeInsights.streak(results) == 2)
    }

    @Test func tagTooCloseNeedsThreeFastMornings() {
        let fast = (19...21).map { WakeResult(start: date($0, 7, 0), secondsToScan: 6) }
        #expect(WakeInsights.tagSeemsTooClose(fast))
        #expect(!WakeInsights.tagSeemsTooClose(Array(fast.prefix(2))))
        let oneSlow = fast + [WakeResult(start: date(22, 7, 0), secondsToScan: 90)]
        #expect(!WakeInsights.tagSeemsTooClose(oneSlow))
    }

    @Test func bedtimeLeavesFiveCyclesAndTimeToFallAsleep() {
        #expect(Bedtime.suggestion(forWakeUp: date(22, 7, 0)) == date(21, 23, 15))
    }
}
