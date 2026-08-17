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
}
