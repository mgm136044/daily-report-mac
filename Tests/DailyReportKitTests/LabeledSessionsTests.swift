import XCTest
@testable import DailyReportKit

final class LabeledSessionsTests: XCTestCase {
    private var dir = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("labeled-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: dir + "/nested", withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: dir) }

    func test_labeled_transcript_grouped_under_fixed_label() throws {
        let line = #"{"timestamp":"2026-08-12T10:00:00.000Z","sessionId":"lab1","message":{"role":"user","content":"agent do X"}}"#
        fm.createFile(atPath: dir + "/nested/t.jsonl", contents: Data((line + "\n").utf8))

        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.extraSessionGlobs = [SessionGlob(glob: dir + "/**/*.jsonl", label: "Agent Mode")]

        let out = ClaudeSessionCollector(config: c).collectLabeled(date: "2026-08-12")
        XCTAssertEqual(out["Agent Mode"]?.prompts, ["agent do X"])
        XCTAssertEqual(out["Agent Mode"]?.sessions, ["lab1"])
        XCTAssertEqual(out["Agent Mode"]?.branches, [])       // labeled has no branches
    }

    func test_empty_label_dropped_when_no_activity() throws {
        // a file with only an out-of-window record → no bucket kept
        let line = #"{"timestamp":"2026-08-11T10:00:00.000Z","message":{"role":"user","content":"old"}}"#
        fm.createFile(atPath: dir + "/nested/t.jsonl", contents: Data((line + "\n").utf8))
        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.extraSessionGlobs = [SessionGlob(glob: dir + "/**/*.jsonl", label: "Agent Mode")]
        XCTAssertNil(ClaudeSessionCollector(config: c).collectLabeled(date: "2026-08-12")["Agent Mode"])
    }
}
