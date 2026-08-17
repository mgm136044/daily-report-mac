import XCTest
@testable import DailyReportKit

/// Soft validation used by the wizard to green-light the "다음" button. It must never
/// be STRICTER than the real parser (`NotionClient.pageId(fromURL:)`) — otherwise it
/// would reject a URL the app itself would happily accept.
final class SetupValidationTests: XCTestCase {

    // MARK: token

    func test_accepts_current_ntn_token() {
        XCTAssertTrue(SetupValidation.looksLikeToken("ntn_v1aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"))
    }

    func test_accepts_legacy_secret_token() {
        // Notion changed the prefix from secret_ to ntn_ in 2024; old tokens still work.
        XCTAssertTrue(SetupValidation.looksLikeToken("secret_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"))
    }

    func test_rejects_prefix_only_or_garbage_or_empty() {
        XCTAssertFalse(SetupValidation.looksLikeToken("ntn_"))     // prefix only, too short
        XCTAssertFalse(SetupValidation.looksLikeToken("hello world"))
        XCTAssertFalse(SetupValidation.looksLikeToken(""))
        XCTAssertFalse(SetupValidation.looksLikeToken("   "))
    }

    // MARK: parent page URL

    func test_accepts_notion_url_with_dashed_id() {
        XCTAssertTrue(SetupValidation.looksLikeNotionURL(
            "https://www.notion.so/My-Page-1a259c31abcd1234ef567890abcdef12"))
    }

    func test_accepts_notion_url_with_bare_id_and_query() {
        XCTAssertTrue(SetupValidation.looksLikeNotionURL(
            "https://notion.so/1a259c31abcd1234ef567890abcdef12?pvs=4"))
    }

    func test_rejects_non_notion_or_incomplete_url() {
        XCTAssertFalse(SetupValidation.looksLikeNotionURL("https://google.com"))
        XCTAssertFalse(SetupValidation.looksLikeNotionURL("not a url"))
        XCTAssertFalse(SetupValidation.looksLikeNotionURL(""))
    }

    func test_matches_the_real_parser() {
        // Whatever the parser accepts, validation must accept — and vice-versa.
        let good = "https://notion.so/x-1a259c31abcd1234ef567890abcdef12"
        let bad  = "https://notion.so/no-id-here"
        XCTAssertEqual(SetupValidation.looksLikeNotionURL(good), (try? NotionClient.pageId(fromURL: good)) != nil)
        XCTAssertEqual(SetupValidation.looksLikeNotionURL(bad),  (try? NotionClient.pageId(fromURL: bad))  != nil)
    }

    func test_pasted_url_with_trailing_whitespace_matches_parser() {
        // Copy-paste often appends a newline/space. Validation trims, so the PARSER
        // must trim too — otherwise a green ✓ leads to a dead-end connect failure.
        for url in ["https://notion.so/x-1a259c31abcd1234ef567890abcdef12\n",
                    "  https://notion.so/x-1a259c31abcd1234ef567890abcdef12  "] {
            XCTAssertTrue(SetupValidation.looksLikeNotionURL(url), url)
            XCTAssertNotNil(try? NotionClient.pageId(fromURL: url), url)   // parser must agree
        }
    }
}
