import Foundation

/// Parses the server's time values: "YYYY-MM-DD" (local day, placed at noon),
/// ISO 8601 timestamps with offset (with or without fractional seconds),
/// timestamps without offset (local) and ISO weeks "YYYY-Www" (Monday noon).
enum BIOSDate {
    private static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if value.count == 10 {
            return day(value)
        }
        if value.count == 8, value.contains("-W") {
            return isoWeek(value)
        }
        if let date = internetFormatter.date(from: value) { return date }
        if let date = fractionalFormatter.date(from: value) { return date }
        if value.count >= 19, let date = localFormatter.date(from: String(value.prefix(19))) {
            return date
        }
        return nil
    }

    /// "YYYY-MM-DD" (or anything starting with it) as local noon.
    static func day(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    /// "2026-W39" as Monday noon of that ISO week.
    static func isoWeek(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]),
              let week = Int(parts[1].dropFirst()) else {
            return nil
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2
        components.hour = 12
        return calendar.date(from: components)
    }
}

/// German formatting, independent of the device language. Built from calendar
/// components with fixed word lists, so the output never depends on CLDR data.
enum BIOSFormat {
    static let locale = Locale(identifier: "de_AT")
    static let weekdaysShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let weekdaysLong = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let monthsLong = ["Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli",
                             "August", "September", "Oktober", "November", "Dezember"]
    static let monthsShort = ["Jän", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    private static var calendar: Calendar { Calendar.current }

    /// Decimal comma, fixed digits. "n. v." for nil.
    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "n. v." }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale).grouping(.never))
    }

    /// "+3" / "−18" / "±0", explicit sign (typographic minus like the server).
    static func signed(_ value: Double?, digits: Int = 0) -> String {
        guard let value, value.isFinite else { return "n. v." }
        let text = number(abs(value), digits: digits)
        if text == number(0, digits: digits) { return "±" + text }
        return (value < 0 ? "\u{2212}" : "+") + text
    }

    static func weekdayShort(_ date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return weekdaysShort[max(0, min(6, index))]
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// "24.09."
    static func shortDate(_ date: Date) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return "\(twoDigits(parts.day ?? 0)).\(twoDigits(parts.month ?? 0))."
    }

    /// "Mi 24.09."
    static func dayLabel(_ date: Date) -> String {
        "\(weekdayShort(date)) \(shortDate(date))"
    }

    /// "13:25"
    static func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(twoDigits(parts.hour ?? 0)):\(twoDigits(parts.minute ?? 0))"
    }

    /// "Freitag, 25. September"
    static func longDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekday = weekdaysLong[max(0, min(6, (parts.weekday ?? 1) - 1))]
        let month = monthsLong[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(weekday), \(parts.day ?? 0). \(month)"
    }

    static func monthShort(_ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        return monthsShort[max(0, min(11, month - 1))]
    }

    /// "25.09.2026, 11:25"
    static func timestamp(_ date: Date) -> String {
        let year = calendar.component(.year, from: date)
        return "\(shortDate(date))\(year), \(time(date))"
    }

    /// "heute 13:25", "gestern 21:40", "Mi 23.09., 13:25".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "heute \(time(date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern \(time(date))"
        }
        return "\(dayLabel(date)), \(time(date))"
    }

    /// Day string "YYYY-MM-DD" relative: "heute", "gestern", "Mi 23.09.".
    static func relativeDay(_ raw: String?, now: Date = Date()) -> String {
        guard let date = BIOSDate.day(raw) else { return raw ?? "" }
        if calendar.isDate(date, inSameDayAs: now) { return "heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern"
        }
        return dayLabel(date)
    }

    /// "vor 25 min", "vor 2 h 55 min", "vor 3 Tagen".
    static func age(minutes: Int) -> String {
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return "vor \(minutes) min" }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "vor \(hours) h" : "vor \(hours) h \(rest) min"
        }
        let days = minutes / (24 * 60)
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    static func age(since date: Date, now: Date = Date()) -> String {
        age(minutes: max(0, Int(now.timeIntervalSince(date) / 60)))
    }
}
