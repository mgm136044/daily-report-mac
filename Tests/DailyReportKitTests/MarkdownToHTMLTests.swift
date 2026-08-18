import XCTest
@testable import DailyReportKit

final class MarkdownToHTMLTests: XCTestCase {
    func test_h1_is_demoted_to_section_heading() {
        // Body H1 becomes h2.sec (the app generates the real title chrome).
        XCTAssertEqual(MarkdownToHTML.convert("# 제목"), #"<h2 class="sec">제목</h2>"#)
    }
    func test_h2_and_h3_map_to_section_and_project() {
        XCTAssertEqual(MarkdownToHTML.convert("## 오늘의 요약"), #"<h2 class="sec">오늘의 요약</h2>"#)
        XCTAssertEqual(MarkdownToHTML.convert("### 프로젝트"), #"<h3 class="proj">프로젝트</h3>"#)
    }
    func test_paragraph_becomes_p_body() {
        XCTAssertEqual(MarkdownToHTML.convert("평범한 문장."), #"<p class="body">평범한 문장.</p>"#)
    }
    func test_thematic_break_is_hr() {
        XCTAssertEqual(MarkdownToHTML.convert("---"), "<hr>")
    }
}
