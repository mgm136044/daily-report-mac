import XCTest
@testable import DailyReportKit

final class RefineHelpersTests: XCTestCase {
    private var cfg: DayConfig { var c = DayConfig.defaultConfig; c.day.timezoneOffsetHours = 9; return c }

    func test_filterCommands_drops_noise_and_near_duplicates() {
        // ls and cd are noise prefixes; the two long commands share their first 60
        // chars so the second collapses into the first by the dedupe prefix.
        let long = "git commit -m " + String(repeating: "x", count: 60)   // >60 chars before the tail
        let (kept, dropped) = Refine.filterCommands(
            ["ls -la", "  cd /tmp  ", long + " one", long + " two"], config: cfg)
        XCTAssertEqual(kept, [long + " one"])
        XCTAssertEqual(dropped, 3)
    }

    func test_filterCommands_collapses_whitespace_and_caps() {
        var c = cfg; c.noise.commandMaxChars = 7
        // "git" is not a noise prefix; whitespace collapses to "git add ." (9),
        // which exceeds the 7-char cap → truncated.
        let (kept, _) = Refine.filterCommands(["git    add     ."], config: c)
        XCTAssertEqual(kept, ["git add" + " …[truncated]"])
    }

    func test_dedupe_preserves_order_drops_repeats() {
        let (kept, dropped) = Refine.dedupe(["design the api", "design  the   api", "build it"])
        XCTAssertEqual(kept, ["design the api", "build it"])
        XCTAssertEqual(dropped, 1)
    }

    func test_localTime_converts_utc_to_local() {
        // 2026-08-12T01:00:00Z == 10:00 in +09
        XCTAssertEqual(Refine.localTime("2026-08-12T01:00:00Z", config: cfg), "2026-08-12 10:00")
        XCTAssertNil(Refine.localTime(nil, config: cfg))
    }

    func test_config_extra_session_globs_default_empty() {
        XCTAssertEqual(DayConfig.defaultConfig.sources.extraSessionGlobs, [])
    }
}
