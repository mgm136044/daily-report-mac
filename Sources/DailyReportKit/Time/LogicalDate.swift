import Foundation

public enum LogicalDate {
    /// The reporting timezone: an explicit config offset wins, else the machine
    /// zone, so a fresh install is correct without editing anything.
    public static func timeZone(_ config: DayConfig) -> TimeZone {
        if let hours = config.day.timezoneOffsetHours,
           let tz = TimeZone(secondsFromGMT: hours * 3600) {
            return tz
        }
        return TimeZone.current
    }

    private static func ymd(_ config: DayConfig) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone(config)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Which logical day an instant belongs to — the boundary hour shifts
    /// late-night work back into the day it felt like.
    public static func logicalDate(_ moment: Date, config: DayConfig) -> String {
        let shifted = moment.addingTimeInterval(-Double(config.day.boundaryHour) * 3600)
        return ymd(config).string(from: shifted)
    }

    /// Format a calendar date as yyyy-MM-dd with the pinned Gregorian/POSIX calendar
    /// and the config timezone, WITHOUT the boundary shift — for a user-picked date
    /// (a date picker already means "the day", not "an instant to bucket").
    public static func calendarString(_ date: Date, config: DayConfig) -> String {
        ymd(config).string(from: date)
    }

    /// The [start, end) instants of the logical day, or nil if the string is
    /// not a valid yyyy-MM-dd date.
    public static func dayWindow(_ dateStr: String, config: DayConfig) -> (start: Date, end: Date)? {
        guard let midnight = ymd(config).date(from: dateStr) else { return nil }
        let start = midnight.addingTimeInterval(Double(config.day.boundaryHour) * 3600)
        return (start, start.addingTimeInterval(86_400))
    }

    /// Serialize an instant as ISO-8601 with the reporting zone's offset,
    /// matching Python's `datetime.isoformat()` on a tz-aware value.
    public static func isoString(_ date: Date, config: DayConfig = .defaultConfig) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone(config)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Parse an ISO-8601 timestamp, tolerating the trailing Z form.
    public static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: value) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)
    }

    /// Single-character Korean weekday ("일","월","화","수","목","금","토") for a
    /// "yyyy-MM-dd" calendar date string, in the config's reporting timezone/calendar
    /// (same parsing as `calendarString` — no boundary shift, since the string already
    /// names a logical day, not an instant). Empty string if the input isn't a valid date.
    public static func weekdaySymbol(_ dateStr: String, config: DayConfig) -> String {
        guard let date = ymd(config).date(from: dateStr) else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone(config)
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]   // Calendar.weekday: 1 = Sunday
        return symbols[cal.component(.weekday, from: date) - 1]
    }

    /// Format `date` as "yyyy-MM-dd HH:mm" in the config's reporting timezone. Split out
    /// from `nowString` so it can be exercised with a fixed `Date` instead of wall-clock
    /// time, keeping the test deterministic.
    static func timestampString(_ date: Date, config: DayConfig) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone(config)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// The current wall-clock instant, formatted per `timestampString` — used to stamp
    /// "generated at" in the report PDF chrome.
    public static func nowString(config: DayConfig) -> String {
        timestampString(Date(), config: config)
    }
}
