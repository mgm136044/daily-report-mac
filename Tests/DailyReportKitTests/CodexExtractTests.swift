import XCTest
@testable import DailyReportKit

final class CodexExtractTests: XCTestCase {
    func test_scanQuoted_reads_backtick_literal() {
        let r = Substring("`codex exec \"hi\"` trailing")
        XCTAssertEqual(CodexExtract.scanQuoted(r, quote: "`"), "codex exec \"hi\"")
    }

    func test_scanQuoted_honors_escaped_quote() {
        let r = Substring(#"'it\'s here' rest"#)          // 'it\'s here'
        XCTAssertEqual(CodexExtract.scanQuoted(r, quote: "'"), #"it\'s here"#)
    }

    func test_scanQuoted_unterminated_returns_nil() {
        let r = Substring("`never closes")
        XCTAssertNil(CodexExtract.scanQuoted(r, quote: "`"))
    }

    func test_decodeStringAt_double_quote_json_unescapes() {
        let text = "cmd: \"line1\\nline2\""                // JSON \n → newline
        let idx = text.range(of: "cmd: ")!.upperBound
        XCTAssertEqual(CodexExtract.decodeStringAt(text, from: idx), "line1\nline2")
    }

    func test_decodeStringAt_double_quote_bad_escape_falls_back_to_raw() {
        let text = #"cmd: "it\'s ok""#                     // \' invalid JSON → raw scan
        let idx = text.range(of: "cmd: ")!.upperBound
        XCTAssertEqual(CodexExtract.decodeStringAt(text, from: idx), #"it\'s ok"#)
    }

    func test_decodeStringAt_backtick_returns_raw() {
        let text = "cmd: `echo hi`"
        let idx = text.range(of: "cmd: ")!.upperBound
        XCTAssertEqual(CodexExtract.decodeStringAt(text, from: idx), "echo hi")
    }

    func test_decodeStringAt_non_string_returns_nil() {
        let text = "cmd: 42"
        let idx = text.range(of: "cmd: ")!.upperBound
        XCTAssertNil(CodexExtract.decodeStringAt(text, from: idx))
    }

    func test_decodeStringAt_double_quote_over_4000_is_not_capped() {
        // Python's `"` path uses raw_decode (uncapped); a long heredoc-style
        // command must still decode in full.
        let long = String(repeating: "a", count: 4100)
        let text = "cmd: \"\(long)\""
        let idx = text.range(of: "cmd: ")!.upperBound
        XCTAssertEqual(CodexExtract.decodeStringAt(text, from: idx), long)
    }

    func test_scanQuoted_stays_bounded_at_4000() {
        // backtick / single-quote paths keep the MAX_LITERAL_CHARS bound.
        let long = String(repeating: "b", count: 4100)
        XCTAssertNil(CodexExtract.scanQuoted(Substring("`\(long)`"), quote: "`"))
    }

    func test_extractCommands_pulls_cmd_literals() {
        let payload: [String: Any] = [
            "name": "exec",
            "input": "tools.exec_command({cmd: \"git status\"}); tools.exec_command({cmd: `ls -la`})"]
        XCTAssertEqual(CodexExtract.extractCommands(payload), ["git status", "ls -la"])
    }

    func test_extractCommands_ignores_non_tool_names() {
        let payload: [String: Any] = ["name": "other", "input": "tools.exec_command({cmd: \"x\"})"]
        XCTAssertEqual(CodexExtract.extractCommands(payload), [])
    }

    func test_extractCommands_no_cmd_returns_empty_not_raw() {
        let payload: [String: Any] = ["name": "exec", "input": "store(\"k\", {plan: 1})"]
        XCTAssertEqual(CodexExtract.extractCommands(payload), [])
    }

    func test_extractPlanSteps_from_standalone_update_plan_json() {
        let payload: [String: Any] = [
            "name": "update_plan",
            "arguments": "{\"plan\": [{\"step\": \"design\"}, {\"step\": \"build\"}]}"]
        XCTAssertEqual(CodexExtract.extractPlanSteps(payload), ["design", "build"])
    }

    func test_extractPlanSteps_from_inline_tools_update_plan() {
        let payload: [String: Any] = [
            "name": "exec",
            "input": "tools.update_plan({plan:[{step: \"scan\"}, {step: `patch`}]})"]
        XCTAssertEqual(CodexExtract.extractPlanSteps(payload), ["scan", "patch"])
    }

    func test_extractPlanSteps_without_marker_returns_empty() {
        let payload: [String: Any] = ["name": "exec", "input": "tools.exec_command({cmd: \"x\"})"]
        XCTAssertEqual(CodexExtract.extractPlanSteps(payload), [])
    }
}
