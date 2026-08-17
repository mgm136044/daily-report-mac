import XCTest
@testable import DailyReportKit

final class PromptTests: XCTestCase {
    func test_config_summary_defaults() {
        XCTAssertEqual(DayConfig.defaultConfig.summary.modelTimeoutSec, 900)
        XCTAssertEqual(DayConfig.defaultConfig.summary.maxTurns, 1)
    }

    func test_build_substitutes_fields_and_unescapes_braces() {
        let p = Prompts.build(digestJSON: #"{"a": {"b": 1}}"#, date: "2026-08-12",
                              weekday: "수", targetChars: 5000, language: "ko")
        XCTAssertTrue(p.contains("2026-08-12(수)"))          // date_str + weekday
        XCTAssertTrue(p.contains("5000자 안팎"))              // target_chars
        XCTAssertTrue(p.contains(#"{"a": {"b": 1}}"#))       // digest JSON braces intact
        XCTAssertTrue(p.contains("### {프로젝트명}"))         // {{프로젝트명}} unescaped to single braces
        XCTAssertFalse(p.contains("{date_str}"))             // no leftover fields
        XCTAssertFalse(p.contains("{{"))                     // no leftover escaped braces
    }

    func test_digestJSON_shape() {
        let refined = RefinedDay(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            projects: [RefinedProject(label: "proj", root: "/p", tools: ["Claude Code"],
                sessionCount: 2, branches: [], titles: [], skillsUsed: [], prompts: ["a"],
                filesWritten: ["/p/x.md"], filesEdited: [], filesTracked: [], filesOnDisk: [],
                bashCommands: [], todos: [], plans: [], outcomes: [], commits: [],
                activeFrom: "2026-08-12 10:00", activeTo: "2026-08-12 11:00")],
            stats: RefinedStats(projects: 1, sessions: 2, files: 1, commits: 0,
                                noiseCommandsDropped: 0, cwdsDropped: 0), droppedCwds: [])
        let obj = DigestJSON.object(refined)
        XCTAssertEqual(obj["date"] as? String, "2026-08-12")
        let projects = obj["projects"] as? [[String: Any]]
        XCTAssertEqual(projects?.first?["session_count"] as? Int, 2)
        XCTAssertEqual(projects?.first?["files_written"] as? [String], ["/p/x.md"])
    }
}
