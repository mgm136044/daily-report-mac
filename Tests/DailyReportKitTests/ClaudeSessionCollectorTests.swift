import XCTest
@testable import DailyReportKit

final class ClaudeSessionCollectorTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // config pinned to +09:00 so the day window is deterministic.
    private func config() -> DayConfig {
        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.claudeProjectsDir = root.path
        return c
    }

    private func writeTranscript(_ name: String, _ lines: [[String: Any]]) {
        let dir = root.appendingPathComponent("proj-a"); try? FileManager.default
            .createDirectory(at: dir, withIntermediateDirectories: true)
        let text = lines.map {
            String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!
        }.joined(separator: "\n")
        try! text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func test_only_records_inside_the_logical_day_are_kept() {
        // logical 2026-08-10 = 08-10 04:00 .. 08-11 04:00 (+09:00)
        writeTranscript("a.jsonl", [
            ["cwd": "/p", "timestamp": "2026-08-10T05:00:00+09:00",   // in
             "message": ["role": "user", "content": "안"]],
            ["cwd": "/p", "timestamp": "2026-08-10T02:00:00+09:00",   // before boundary → out
             "message": ["role": "user", "content": "밖"]],
        ])
        let out = ClaudeSessionCollector(config: config()).collect(date: "2026-08-10")
        XCTAssertEqual(out.projects["/p"]?.prompts, ["안"])
        XCTAssertEqual(out.stats.recordsInDay, 1)
        XCTAssertEqual(out.stats.transcriptsScanned, 1)
    }

    func test_malformed_lines_are_skipped_not_fatal() {
        writeTranscript("b.jsonl", [
            ["cwd": "/p", "timestamp": "2026-08-10T05:00:00+09:00",
             "message": ["role": "user", "content": "ok"]]])
        // append a broken line
        let f = root.appendingPathComponent("proj-a/b.jsonl")
        let h = try! FileHandle(forWritingTo: f); h.seekToEndOfFile()
        h.write(Data("\n{not json\n".utf8)); try? h.close()
        let out = ClaudeSessionCollector(config: config()).collect(date: "2026-08-10")
        XCTAssertEqual(out.projects["/p"]?.prompts, ["ok"])
    }

    func test_transcripts_total_counts_all_files() {
        writeTranscript("a.jsonl", [["cwd": "/p", "timestamp": "2026-08-10T05:00:00+09:00",
            "message": ["role": "user", "content": "x"]]])
        writeTranscript("c.jsonl", [])   // empty, still a transcript
        let out = ClaudeSessionCollector(config: config()).collect(date: "2026-08-10")
        XCTAssertEqual(out.stats.transcriptsTotal, 2)
    }
}
