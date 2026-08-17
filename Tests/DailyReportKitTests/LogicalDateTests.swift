import XCTest
@testable import DailyReportKit

final class LogicalDateTests: XCTestCase {
    // Pin a fixed +09:00 zone so the test is deterministic anywhere.
    private func config(boundary: Int = 4, offset: Int? = 9) -> DayConfig {
        var c = DayConfig.defaultConfig
        c.day.boundaryHour = boundary
        c.day.timezoneOffsetHours = offset
        return c
    }

    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    func test_two_am_belongs_to_the_previous_logical_day() {
        // 2026-08-11 02:00 +09:00, boundary 4 → logical 2026-08-10
        let d = LogicalDate.logicalDate(at("2026-08-11T02:00:00+09:00"), config: config())
        XCTAssertEqual(d, "2026-08-10")
    }

    func test_five_am_belongs_to_the_same_logical_day() {
        let d = LogicalDate.logicalDate(at("2026-08-11T05:00:00+09:00"), config: config())
        XCTAssertEqual(d, "2026-08-11")
    }

    func test_day_window_starts_at_the_boundary_hour() {
        let w = LogicalDate.dayWindow("2026-08-10", config: config())!
        XCTAssertEqual(w.start, at("2026-08-10T04:00:00+09:00"))
        XCTAssertEqual(w.end, at("2026-08-11T04:00:00+09:00"))
    }

    func test_configured_offset_overrides_the_machine_zone() {
        let tz = LogicalDate.timeZone(config(offset: 9))
        XCTAssertEqual(tz.secondsFromGMT(), 9 * 3600)
    }

    func test_calendarString_ignores_the_boundary_shift() {
        // 02:00 falls before the 04:00 boundary: logicalDate() buckets it into the
        // previous day, but a user-picked calendar date must stay put.
        let moment = at("2026-08-01T02:00:00+09:00")
        XCTAssertEqual(LogicalDate.logicalDate(moment, config: config()), "2026-07-31")
        XCTAssertEqual(LogicalDate.calendarString(moment, config: config()), "2026-08-01")
    }

    func test_parse_iso_tolerates_trailing_z() {
        XCTAssertNotNil(LogicalDate.parseISO("2026-08-10T00:00:00Z"))
        XCTAssertNil(LogicalDate.parseISO(nil))
        XCTAssertNil(LogicalDate.parseISO("not-a-date"))
    }
}
