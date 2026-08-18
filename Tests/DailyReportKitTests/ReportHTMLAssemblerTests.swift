import XCTest
@testable import DailyReportKit

final class ReportHTMLAssemblerTests: XCTestCase {
    private func chrome() -> ReportChrome {
        ReportChrome(date: "2026-08-17", weekday: "일", projects: 2, sessions: 30,
                     commits: 7, files: 140, generatedAt: "2026-08-18 04:05", appVersion: "1.4.0")
    }

    func test_embeds_css_verbatim_in_style_block() {
        let css = "/* CANON */ .page { color: #000; }"
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "## 요약", css: css)
        XCTAssertTrue(html.contains("<style>\n\(css)\n</style>"))
    }

    func test_header_shows_title_and_date() {
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "", css: "")
        XCTAssertTrue(html.contains(#"<div class="title">하루 마감 보고서</div>"#))
        XCTAssertTrue(html.contains(#"<div class="date">2026-08-17 (일)</div>"#))
    }

    func test_stats_row_shows_the_four_totals() {
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "", css: "")
        XCTAssertTrue(html.contains(#"<div class="n">2</div><div class="l">프로젝트</div>"#))
        XCTAssertTrue(html.contains(#"<div class="n">30</div><div class="l">세션</div>"#))
        XCTAssertTrue(html.contains(#"<div class="n">7</div><div class="l">커밋</div>"#))
        XCTAssertTrue(html.contains(#"<div class="n">140</div><div class="l">파일</div>"#))
    }

    func test_body_is_converted_markdown() {
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "## 요약", css: "")
        XCTAssertTrue(html.contains(#"<h2 class="sec">요약</h2>"#))
    }

    func test_footer_has_generated_time_version_and_pageno() {
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "", css: "")
        XCTAssertTrue(html.contains("2026-08-18 04:05 생성"))
        XCTAssertTrue(html.contains("DailyReport v1.4.0"))
        XCTAssertTrue(html.contains(#"<span class="pageno">"#))
    }

    func test_body_h1_is_demoted_so_only_chrome_owns_the_title() {
        // A body "# ..." must not become a second document title.
        let html = ReportHTMLAssembler.assemble(chrome: chrome(), markdownBody: "# 안녕", css: "")
        XCTAssertFalse(html.contains("<h1"))
    }
}
