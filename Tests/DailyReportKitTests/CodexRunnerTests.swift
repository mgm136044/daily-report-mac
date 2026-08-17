import XCTest
@testable import DailyReportKit

final class CodexRunnerTests: XCTestCase {
    /// True iff `pair` appears as a contiguous subsequence of `arr`.
    private func hasPair(_ arr: [String], _ pair: [String]) -> Bool {
        guard pair.count <= arr.count else { return false }
        for i in 0...(arr.count - pair.count) where Array(arr[i..<i + pair.count]) == pair { return true }
        return false
    }

    func test_codex_arguments_use_live_flags_not_dead_ones() {
        let a = ProcessCodexRunner.arguments(prompt: "요약해줘", model: "gpt-5.5")
        XCTAssertEqual(a.first, "codex")
        XCTAssertTrue(a.contains("exec"))
        XCTAssertTrue(hasPair(a, ["--model", "gpt-5.5"]))
        XCTAssertTrue(hasPair(a, ["--sandbox", "read-only"]))
        XCTAssertTrue(a.contains("--skip-git-repo-check"))
        XCTAssertEqual(a.last, "요약해줘")   // prompt is a positional arg, not stdin

        // dead flags/models per the codex-delegation rule must never appear
        XCTAssertFalse(a.contains("--full-auto"))
        XCTAssertFalse(a.contains("gpt-5.2-codex"))
        XCTAssertFalse(a.contains("gpt-5-codex"))
    }

    func test_engine_selection() {
        var cfg = DayConfig.defaultConfig
        cfg.summary.engine = nil          // old config, field absent
        XCTAssertTrue(SummaryEngine.runner(for: cfg) is ProcessClaudeRunner)
        cfg.summary.engine = "claude"
        XCTAssertTrue(SummaryEngine.runner(for: cfg) is ProcessClaudeRunner)
        cfg.summary.engine = "codex"
        XCTAssertTrue(SummaryEngine.runner(for: cfg) is ProcessCodexRunner)
    }

    func test_summary_settings_decodes_without_engine_field() throws {
        // Existing config.json predates `engine`; must still decode (else the user's
        // saved config silently falls back to defaults, losing token/DB settings).
        let json = #"{"modelTimeoutSec":900,"maxTurns":1}"#
        let s = try JSONDecoder().decode(SummarySettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.modelTimeoutSec, 900)
        XCTAssertEqual(s.maxTurns, 1)
        XCTAssertNil(s.engine)            // absent → nil → treated as claude
    }
}
