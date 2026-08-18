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

extension MarkdownToHTMLTests {
    func test_inline_bold_becomes_b() {
        XCTAssertEqual(MarkdownToHTML.convert("**굵게** 보통"),
                       #"<p class="body"><b>굵게</b> 보통</p>"#)
    }
    func test_inline_code_becomes_code() {
        XCTAssertEqual(MarkdownToHTML.convert("`swift build` 실행"),
                       #"<p class="body"><code>swift build</code> 실행</p>"#)
    }
    func test_link_becomes_anchor() {
        XCTAssertEqual(MarkdownToHTML.convert("[릴리스](https://x/y) 참고"),
                       #"<p class="body"><a href="https://x/y">릴리스</a> 참고</p>"#)
    }
    func test_html_is_escaped_before_inline() {
        // Raw HTML/special chars are neutralized; inline runs on escaped text.
        XCTAssertEqual(MarkdownToHTML.convert("a < b & <script>"),
                       #"<p class="body">a &lt; b &amp; &lt;script&gt;</p>"#)
    }
    func test_unordered_list() {
        XCTAssertEqual(MarkdownToHTML.convert("- 하나\n- 둘"),
            #"<ul class="body"><li>하나</li><li>둘</li></ul>"#)
    }
    func test_ordered_list() {
        XCTAssertEqual(MarkdownToHTML.convert("1. 하나\n2. 둘"),
            #"<ol class="body"><li>하나</li><li>둘</li></ol>"#)
    }
    func test_nested_unordered_list() {
        XCTAssertEqual(MarkdownToHTML.convert("- 상위\n  - 하위"),
            #"<ul class="body"><li>상위<ul class="body"><li>하위</li></ul></li></ul>"#)
    }
    func test_blockquote_joins_lines() {
        XCTAssertEqual(MarkdownToHTML.convert("> 한 줄\n> 두 줄"),
            "<blockquote>한 줄 두 줄</blockquote>")
    }
    func test_fenced_code_block_is_preserved_and_escaped() {
        XCTAssertEqual(MarkdownToHTML.convert("```\na < b\n```"),
            "<pre><code>a &lt; b</code></pre>")
    }
}

extension MarkdownToHTMLTests {
    func test_paragraph_immediately_followed_by_list_stays_separate_blocks() {
        // No blank line between the paragraph and the list: the paragraph gather
        // must still stop at the list start instead of swallowing it into the <p>.
        XCTAssertEqual(MarkdownToHTML.convert("문단\n- 항목"),
            #"<p class="body">문단</p>"# + "\n" + #"<ul class="body"><li>항목</li></ul>"#)
    }
    func test_paragraph_immediately_followed_by_blockquote_stays_separate_blocks() {
        XCTAssertEqual(MarkdownToHTML.convert("문단\n> 인용"),
            #"<p class="body">문단</p>"# + "\n<blockquote>인용</blockquote>")
    }
    func test_paragraph_immediately_followed_by_fenced_code_stays_separate_blocks() {
        XCTAssertEqual(MarkdownToHTML.convert("문단\n```\n코드\n```"),
            #"<p class="body">문단</p>"# + "\n<pre><code>코드</code></pre>")
    }
    func test_double_quote_in_paragraph_is_escaped() {
        XCTAssertEqual(MarkdownToHTML.convert(#"그는 "안녕"이라 했다"#),
            #"<p class="body">그는 &quot;안녕&quot;이라 했다</p>"#)
    }
    func test_double_quote_in_link_url_is_escaped_in_href() {
        // escape() runs before the link regex captures the URL, so a raw '"' inside
        // the URL becomes &quot; and can no longer break out of the href attribute.
        XCTAssertEqual(MarkdownToHTML.convert(#"[링크](https://x/y?q="v") 설명"#),
            #"<p class="body"><a href="https://x/y?q=&quot;v&quot;">링크</a> 설명</p>"#)
    }
}
