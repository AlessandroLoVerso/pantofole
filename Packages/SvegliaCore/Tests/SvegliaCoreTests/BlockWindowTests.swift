import Foundation
import Testing
@testable import SvegliaCore

@Suite struct BlockWindowTests {
    private let rome: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    /// 2026-10-21 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        rome.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private let night = BlockWindow(startHour: 23, startMinute: 0, endHour: 7, endMinute: 0)

    @Test func overnightWindowContainsLateEveningAndEarlyMorning() {
        #expect(night.crossesMidnight)
        #expect(night.currentInterval(at: date(21, 23, 30), calendar: rome) == DateInterval(start: date(21, 23, 0), end: date(22, 7, 0)))
        #expect(night.currentInterval(at: date(22, 6, 59), calendar: rome) == DateInterval(start: date(21, 23, 0), end: date(22, 7, 0)))
        #expect(night.currentInterval(at: date(22, 7, 0), calendar: rome) == nil)
        #expect(night.currentInterval(at: date(21, 22, 59), calendar: rome) == nil)
    }

    @Test func sameDayWindow() {
        let morning = BlockWindow(startHour: 7, startMinute: 0, endHour: 9, endMinute: 0)
        #expect(!morning.crossesMidnight)
        #expect(morning.currentInterval(at: date(21, 8, 0), calendar: rome)?.end == date(21, 9, 0))
        #expect(morning.currentInterval(at: date(21, 9, 0), calendar: rome) == nil)
        #expect(morning.nextInterval(after: date(21, 9, 0), calendar: rome)?.start == date(22, 7, 0))
    }

    @Test func weekdaysAreTheDayTheWindowStarts() {
        // Only Friday nights (6): Saturday 03:00 is inside, Thursday night is not.
        var friday = night
        friday.weekdays = [6]
        #expect(friday.currentInterval(at: date(24, 3, 0), calendar: rome) != nil)
        #expect(friday.currentInterval(at: date(23, 3, 0), calendar: rome) == nil)
        #expect(friday.endWeekday(forStart: 6) == 7)
        #expect(friday.endWeekday(forStart: 7) == 1)
        #expect(friday.nextInterval(after: date(21, 12, 0), calendar: rome)?.start == date(23, 23, 0))
    }

    @Test func durationAndValidity() {
        #expect(night.durationMinutes == 8 * 60)
        #expect(BlockWindow(startHour: 7, startMinute: 0, endHour: 7, endMinute: 10).isValid == false)
        #expect(BlockWindow(startHour: 7, startMinute: 0, endHour: 7, endMinute: 0).durationMinutes == 1440)
    }

    @Test func survivesDaylightSavingChange() {
        // Clocks go back on 2026-10-25 at 03:00 in Rome: the night still ends at 07:00 local.
        #expect(night.currentInterval(at: date(25, 6, 0), calendar: rome)?.end == date(25, 7, 0))
    }
}
