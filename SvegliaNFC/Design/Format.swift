import Foundation

enum Format {
    /// Weekdays in Italian order, Monday first (Calendar numbering).
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    static func time(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func days(_ weekdays: [Int]) -> String {
        let set = Set(weekdays)
        switch set {
        case []: return String(localized: "Una volta")
        case Set(1...7): return String(localized: "Ogni giorno")
        case Set(2...6): return String(localized: "Feriali")
        case [1, 7]: return String(localized: "Weekend")
        default:
            let symbols = Calendar.current.shortStandaloneWeekdaySymbols
            return mondayFirst.filter(set.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// "Oggi", "Domani" or the weekday name.
    static func day(of date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Oggi") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Domani")
        }
        return date.formatted(.dateTime.weekday(.wide)).capitalized
    }

    /// "tra 7 h 12 min", "tra 5 min".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "tra \(rest) min") }
        if rest == 0 { return String(localized: "tra \(hours) h") }
        return String(localized: "tra \(hours) h \(rest) min")
    }

    /// "42 s", "1 min 42 s".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 { return String(localized: "\(rest) s") }
        if rest == 0 { return String(localized: "\(minutes) min") }
        return String(localized: "\(minutes) min \(rest) s")
    }

    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Buongiorno")
        case 12..<18: String(localized: "Buon pomeriggio")
        default: String(localized: "Buonasera")
        }
    }
}
