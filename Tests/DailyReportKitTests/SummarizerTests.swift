import XCTest
@testable import DailyReportKit

final class SummarizerTests: XCTestCase {
    private var cfg: DayConfig { var c = DayConfig.defaultConfig; c.day.timezoneOffsetHours = 9; return c }
    private func refined(date: String = "2026-08-12") -> RefinedDay {
        RefinedDay(date: date, windowStart: "s", windowEnd: "e",
            projects: [RefinedProject(label: "proj", root: "/p", tools: ["Claude Code"],
                sessionCount: 1, branches: [], titles: [], skillsUsed: [], prompts: ["a"],
                filesWritten: ["/p/x.md"], filesEdited: [], filesTracked: [], filesOnDisk: [],
                bashCommands: [], todos: [], plans: [], outcomes: [], commits: [],
                activeFrom: nil, activeTo: nil)],
            stats: RefinedStats(projects: 1, sessions: 1, files: 1, commits: 0,
                                noiseCommandsDropped: 0, cwdsDropped: 0), droppedCwds: [])
    }

    func test_summarize_injects_date_and_returns_stripped_report() throws {
        let report = "# 2026-08-12 보고서\n\n" + String(repeating: "내용 ", count: 100)
        let mock = MockClaudeRunner(.completed(ClaudeResult(status: 0, stdout: "여기요:\n" + report, stderr: "")))
        let out = try Summarizer(config: cfg, runner: mock).summarize(refined())
        XCTAssertTrue(out.hasPrefix("# 2026-08-12 보고서"))     // preamble stripped
        XCTAssertTrue(mock.lastPrompt?.contains("2026-08-12") ?? false)   // date injected
    }

    func test_summarize_throws_on_refusal() {
        let mock = MockClaudeRunner(.completed(ClaudeResult(status: 0, stdout: "죄송하지만 할 수 없습니다.", stderr: "")))
        XCTAssertThrowsError(try Summarizer(config: cfg, runner: mock).summarize(refined()))
    }

    func test_summarize_throws_on_nonzero_exit_and_timeout() {
        let bad = MockClaudeRunner(.completed(ClaudeResult(status: 1, stdout: "", stderr: "boom")))
        XCTAssertThrowsError(try Summarizer(config: cfg, runner: bad).summarize(refined()))
        let slow = MockClaudeRunner(.timedOut)
        XCTAssertThrowsError(try Summarizer(config: cfg, runner: slow).summarize(refined()))
    }

    func test_buildDayDigest_maps_fields() {
        let report = "# 제목\n\n오늘은 문서를 썼다. 그리고 커밋했다.\n\n## 다음\n- x"
        let digest = Summarizer(config: cfg, runner: MockClaudeRunner(.timedOut))
            .buildDayDigest(refined: refined(), report: report, source: "work/digest.json")
        XCTAssertEqual(digest.date, "2026-08-12")
        XCTAssertEqual(digest.markdown, report)
        XCTAssertEqual(digest.summary, "오늘은 문서를 썼다. 그리고 커밋했다.")
        XCTAssertEqual(digest.projects, ["proj"])
        XCTAssertEqual(digest.tags, ["문서작성"])                // x.md written
        XCTAssertEqual(digest.sessions, 1)
        XCTAssertEqual(digest.status, .done)
        XCTAssertEqual(digest.source, "work/digest.json")
    }
}
