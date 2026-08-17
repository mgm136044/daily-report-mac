import XCTest
@testable import DailyReportKit

final class ReportHelpersTests: XCTestCase {
    func test_stripPreamble_drops_chatty_lead_in() {
        let text = "여기 정리했습니다:\n\n# 2026-08-12 보고서\n\n내용"
        XCTAssertEqual(ReportHelpers.stripPreamble(text), "# 2026-08-12 보고서\n\n내용")
    }

    func test_validate_rejects_headingless_and_short() {
        XCTAssertThrowsError(try ReportHelpers.validate("죄송합니다, 도와드릴 수 없습니다."))  // no heading
        let longNoHeading = String(repeating: "가", count: 300)
        XCTAssertThrowsError(try ReportHelpers.validate(longNoHeading))                     // still no heading
        XCTAssertThrowsError(try ReportHelpers.validate("# 짧음"))                          // heading but < 200
        XCTAssertNoThrow(try ReportHelpers.validate("# 제목\n\n" + String(repeating: "내용 ", count: 100)))
    }

    func test_firstSentences_takes_opening_prose() {
        let md = "# 제목\n\n오늘은 A를 했다. 그리고 B도 했다. 마지막으로 C. 넷째 문장.\n\n## 다음\n- 항목"
        XCTAssertEqual(ReportHelpers.firstSentences(md, count: 3),
                       "오늘은 A를 했다. 그리고 B도 했다. 마지막으로 C.")
    }

    func test_deriveTags_from_project_contents() {
        func proj(written: [String] = [], commits: [GitCommit] = [], skills: [String] = []) -> RefinedProject {
            RefinedProject(label: "p", root: nil, tools: [], sessionCount: 0, branches: [],
                titles: [], skillsUsed: skills, prompts: [], filesWritten: written, filesEdited: [],
                filesTracked: [], filesOnDisk: [], bashCommands: [], todos: [], plans: [],
                outcomes: [], commits: commits, activeFrom: nil, activeTo: nil)
        }
        let commit = GitCommit(repo: "r", project: "p", sha: "s", at: "", authoredAt: "",
            author: "", subject: "", files: 0, insertions: 0, deletions: 0, paths: [])
        let refined = RefinedDay(date: "d", windowStart: "", windowEnd: "", projects: [
            proj(written: ["a.md", "b.swift", "c.css"], commits: [commit],
                 skills: ["insane-research:main"])],
            stats: RefinedStats(projects: 1, sessions: 0, files: 0, commits: 1,
                                noiseCommandsDropped: 0, cwdsDropped: 0), droppedCwds: [])
        XCTAssertEqual(ReportHelpers.deriveTags(refined), ["디자인", "리서치", "문서작성", "커밋", "코드작성"])
    }
}
