import XCTest
@testable import DailyReportKit

final class CodexCollectorTests: XCTestCase {
    private var root = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root + "/2026/08/12", withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private func writeRollout(_ name: String, _ lines: [String]) throws {
        fm.createFile(atPath: root + "/2026/08/12/" + name,
                      contents: Data((lines.joined(separator: "\n") + "\n").utf8))
    }
    private func config() -> DayConfig {
        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.codexSessionsDir = root
        return c
    }

    func test_missing_dir_reports_unavailable() {
        var c = DayConfig.defaultConfig
        c.sources.codexSessionsDir = root + "/nope"
        let out = CodexCollector(config: c).collect(date: "2026-08-12")
        XCTAssertFalse(out.stats.available)
        XCTAssertTrue(out.projects.isEmpty)
    }

    func test_collects_prompt_under_cwd_in_window() throws {
        try writeRollout("rollout-a.jsonl", [
            #"{"type":"session_meta","payload":{"cwd":"/work/proj","git":{"branch":"main"},"id":"r1"}}"#,
            #"{"type":"response_item","timestamp":"2026-08-12T10:00:00+09:00","payload":{"type":"user_message","message":"hello codex"}}"#,
        ])
        let out = CodexCollector(config: config()).collect(date: "2026-08-12")
        XCTAssertTrue(out.stats.available)
        XCTAssertEqual(out.projects["/work/proj"]?.prompts, ["hello codex"])
        XCTAssertEqual(out.projects["/work/proj"]?.sessions, ["r1"])
    }

    func test_out_of_window_record_is_skipped() throws {
        try writeRollout("rollout-b.jsonl", [
            #"{"type":"session_meta","payload":{"cwd":"/work/proj","id":"r2"}}"#,
            #"{"type":"response_item","timestamp":"2026-08-11T10:00:00+09:00","payload":{"type":"user_message","message":"yesterday"}}"#,
        ])
        let out = CodexCollector(config: config()).collect(date: "2026-08-12")
        XCTAssertNil(out.projects["/work/proj"])   // no in-window records → no bucket
    }

    // Codex writes bare NaN in numeric fields; Python's json.loads keeps such
    // records, JSONSerialization rejects them. LenientJSON must recover them.
    func test_record_with_nan_field_is_recovered() throws {
        try writeRollout("rollout-nan.jsonl", [
            #"{"type":"session_meta","payload":{"cwd":"/work/proj","id":"r3"}}"#,
            #"{"type":"response_item","timestamp":"2026-08-12T10:00:00+09:00","payload":{"type":"user_message","message":"with nan"},"score":NaN}"#,
        ])
        let out = CodexCollector(config: config()).collect(date: "2026-08-12")
        XCTAssertEqual(out.projects["/work/proj"]?.prompts, ["with nan"])
    }
}
