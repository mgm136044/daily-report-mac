import XCTest
@testable import DailyReportKit

final class NotionPayloadsTests: XCTestCase {
    func test_clean_option_replaces_commas_and_caps_length() {
        XCTAssertEqual(NotionPayloads.cleanOption("a, b ,  c"), "a b c")
        XCTAssertEqual(NotionPayloads.cleanOption(String(repeating: "x", count: 150)).count, 100)
    }

    func test_options_drop_empty_dedupe_and_cap_at_100() {
        let raw = [","] + ["dup", "dup"] + (1...120).map { "p\($0)" }
        let opts = NotionPayloads.options(raw)
        XCTAssertEqual(opts.count, 100)                 // capped
        let names = opts.map { $0["name"] as! String }
        XCTAssertFalse(names.contains(""))              // empty (only-comma) dropped
        XCTAssertEqual(names.filter { $0 == "dup" }.count, 1)   // deduped
    }

    func test_build_properties_truncates_summary_and_titles_with_weekday() {
        let schema = NotionSchema(config: .defaultConfig)   // ko
        var d = DayDigest(date: "2026-08-10", markdown: "b",
                          summary: String(repeating: "s", count: 2500),
                          projects: ["app"], tags: [], sessions: 42, commits: 45,
                          files: 240, status: .done, source: "runner")
        d.tags = ["swift"]
        let props = NotionPayloads.buildProperties(d, schema: schema,
                                                   config: .defaultConfig, now: Date())
        // 2026-08-10 is a Monday → "월"
        let title = ((props["이름"] as! [String: Any])["title"] as! [[String: Any]])
        let text = ((title[0]["text"] as! [String: Any])["content"] as! String)
        XCTAssertEqual(text, "2026-08-10 (월)")
        let summary = ((props["요약"] as! [String: Any])["rich_text"] as! [[String: Any]])
        let content = ((summary[0]["text"] as! [String: Any])["content"] as! String)
        XCTAssertEqual(content.count, 2000)             // capped
        XCTAssertEqual((props["세션 수"] as! [String: Any])["number"] as! Int, 42)
    }

    func test_markdown_to_blocks_maps_headings_and_bullets() {
        let blocks = NotionPayloads.markdownToBlocks("# Title\n- item\nplain\n")
        XCTAssertEqual(blocks[0]["type"] as? String, "heading_1")
        XCTAssertEqual(blocks[1]["type"] as? String, "bulleted_list_item")
        XCTAssertEqual(blocks[2]["type"] as? String, "paragraph")
    }
}
