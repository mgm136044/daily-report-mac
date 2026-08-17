import XCTest
@testable import DailyReportKit

final class SessionAbsorbTests: XCTestCase {
    private let collector = ClaudeSessionCollector(config: .defaultConfig)
    private let t = ISO8601DateFormatter().date(from: "2026-08-10T05:00:00Z")!

    private func absorbed(_ records: [[String: Any]]) -> [String: SessionProject] {
        var buckets: [String: ClaudeSessionCollector.Bucket] = [:]
        for r in records { collector.absorb(r, stamp: t, into: &buckets) }
        return ClaudeSessionCollector.finalize(buckets)
    }

    func test_user_prompt_string_is_captured_under_its_cwd() {
        let out = absorbed([[
            "cwd": "/Users/me/app", "sessionId": "s1", "gitBranch": "main",
            "message": ["role": "user", "content": "오늘 할 일"]]])
        XCTAssertEqual(out["/Users/me/app"]?.prompts, ["오늘 할 일"])
        XCTAssertEqual(out["/Users/me/app"]?.sessions, ["s1"])
        XCTAssertEqual(out["/Users/me/app"]?.branches, ["main"])
    }

    func test_tool_use_blocks_are_absorbed_by_kind() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "Write", "input": ["file_path": "/p/a.swift"]],
            ["type": "tool_use", "name": "Edit", "input": ["file_path": "/p/b.swift"]],
            ["type": "tool_use", "name": "Bash", "input": ["command": "swift build"]],
            ["type": "tool_use", "name": "Skill", "input": ["skill": "brainstorming"]],
            ["type": "tool_use", "name": "TodoWrite",
             "input": ["todos": [["content": "task one"]]]],
        ]
        let out = absorbed([["cwd": "/p", "message": ["role": "assistant", "content": content]]])
        XCTAssertEqual(out["/p"]?.filesWritten, ["/p/a.swift"])
        XCTAssertEqual(out["/p"]?.filesEdited, ["/p/b.swift"])
        XCTAssertEqual(out["/p"]?.bashCommands, ["swift build"])
        XCTAssertEqual(out["/p"]?.skillsUsed, ["brainstorming"])
        XCTAssertEqual(out["/p"]?.todos, ["task one"])
    }

    func test_file_history_delta_places_by_backup_dir_not_cwd() {
        let out = absorbed([[
            "type": "file-history-delta",
            "backup": ["realParentDir": "/Users/me/app"],
            "trackingPath": "/whatever/CONTEXT.md"]])
        XCTAssertEqual(out["/Users/me/app"]?.filesTracked, ["/Users/me/app/CONTEXT.md"])
    }

    func test_excluded_cwd_is_dropped() {
        var c = DayConfig.defaultConfig; c.exclude.paths = ["/node_modules/"]
        let col = ClaudeSessionCollector(config: c)
        var buckets: [String: ClaudeSessionCollector.Bucket] = [:]
        col.absorb(["cwd": "/x/node_modules/y", "message": ["role": "user", "content": "hi"]],
                   stamp: t, into: &buckets)
        XCTAssertTrue(ClaudeSessionCollector.finalize(buckets).isEmpty)
    }

    func test_long_prompt_is_truncated_with_a_visible_mark() {
        var c = DayConfig.defaultConfig; c.noise.promptMaxChars = 5
        let col = ClaudeSessionCollector(config: c)
        var buckets: [String: ClaudeSessionCollector.Bucket] = [:]
        col.absorb(["cwd": "/p", "message": ["role": "user", "content": "abcdefghij"]],
                   stamp: t, into: &buckets)
        let p = ClaudeSessionCollector.finalize(buckets)["/p"]!.prompts[0]
        XCTAssertEqual(p, "abcde …[truncated]")
    }
}
