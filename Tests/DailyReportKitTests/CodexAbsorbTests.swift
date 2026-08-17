import XCTest
@testable import DailyReportKit

final class CodexAbsorbTests: XCTestCase {
    func test_empty_bucket_finalizes_to_empty_project() {
        let p = CodexBucket().finalize(promptCap: 1400)
        XCTAssertEqual(p, CodexProject(
            sessions: [], branches: [], prompts: [], bashCommands: [],
            filesAdded: [], filesUpdated: [], filesDeleted: [], plans: [],
            outcomes: [], subagentThreads: 0, firstTS: nil, lastTS: nil))
    }

    private func meta(cwd: String = "/proj", subagent: Bool = false) -> CodexMeta {
        CodexMeta(cwd: cwd, branch: "main", rolloutId: "r1", isSubagent: subagent)
    }
    private func ts(_ s: String) -> Date { LogicalDate.parseISO(s)! }

    func test_absorb_user_message_becomes_prompt_when_not_subagent() {
        let b = CodexBucket()
        CodexCollector.absorb(bucket: b, meta: meta(),
            pending: [(ts("2026-08-12T10:00:00+09:00"),
                       ["type": "user_message", "message": "do the thing"])],
            promptCap: 1400)
        XCTAssertEqual(b.prompts, ["do the thing"])
    }

    func test_absorb_user_message_dropped_for_subagent() {
        let b = CodexBucket()
        CodexCollector.absorb(bucket: b, meta: meta(subagent: true),
            pending: [(ts("2026-08-12T10:00:00+09:00"),
                       ["type": "user_message", "message": "orchestrator says"])],
            promptCap: 1400)
        XCTAssertTrue(b.prompts.isEmpty)
        XCTAssertEqual(b.subagentThreads, 1)
    }

    func test_absorb_patch_apply_classifies_changes() {
        let b = CodexBucket()
        CodexCollector.absorb(bucket: b, meta: meta(),
            pending: [(ts("2026-08-12T10:00:00+09:00"), [
                "type": "patch_apply_end", "success": true,
                "changes": ["a.txt": ["type": "add"], "b.txt": ["type": "delete"],
                            "c.txt": ["type": "update"]]])],
            promptCap: 1400)
        XCTAssertEqual(b.filesAdded, ["a.txt"])
        XCTAssertEqual(b.filesDeleted, ["b.txt"])
        XCTAssertEqual(b.filesUpdated, ["c.txt"])
    }

    func test_absorb_task_complete_becomes_outcome() {
        let b = CodexBucket()
        CodexCollector.absorb(bucket: b, meta: meta(),
            pending: [(ts("2026-08-12T10:00:00+09:00"),
                       ["type": "task_complete", "last_agent_message": "shipped it"])],
            promptCap: 1400)
        XCTAssertEqual(b.finalize(promptCap: 1400).outcomes, ["shipped it"])
    }
}
