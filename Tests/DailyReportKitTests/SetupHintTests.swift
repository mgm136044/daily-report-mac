import XCTest
@testable import DailyReportKit

/// The setup wizard's final step turns a raw NotionError into a human remedy that
/// names WHICH earlier step to go back and fix. These tests pin that mapping — the
/// #1 real-world failure (page not shared with the integration) must route to the
/// "connect page" step, not a dead-end error string.
final class SetupHintTests: XCTestCase {

    func test_unauthorized_points_to_token_step() {
        let r = SetupHint.remedy(for: .http(401, "unauthorized", "API token is invalid."))
        XCTAssertEqual(r.returnToStep, 2)
        XCTAssertTrue(r.message.contains("토큰"), r.message)
    }

    func test_object_not_found_points_to_share_step() {
        let r = SetupHint.remedy(for: .http(404, "object_not_found",
            "Could not find page. Make sure it is shared with your integration."))
        XCTAssertEqual(r.returnToStep, 4)
        XCTAssertTrue(r.message.contains("연결"), r.message)
    }

    func test_restricted_resource_points_to_share_step() {
        let r = SetupHint.remedy(for: .http(403, "restricted_resource", "Insufficient permissions."))
        XCTAssertEqual(r.returnToStep, 4)
    }

    func test_validation_error_points_to_link_step() {
        let r = SetupHint.remedy(for: .http(400, "validation_error", "body failed validation"))
        XCTAssertEqual(r.returnToStep, 3)
        XCTAssertTrue(r.message.contains("링크"), r.message)
    }

    func test_unknown_http_is_generic_and_shows_detail() {
        let r = SetupHint.remedy(for: .http(500, "internal_server_error", "boom on notion side"))
        XCTAssertNil(r.returnToStep)               // no single step to blame
        XCTAssertTrue(r.message.contains("boom on notion side"), r.message)
    }

    func test_shape_error_is_generic_no_step() {
        let r = SetupHint.remedy(for: .shape("could not parse response"))
        XCTAssertNil(r.returnToStep)
    }

    func test_shape_url_parse_failure_points_to_link_step() {
        // pageId(fromURL:) throws .shape("page id not found in url: …") for a bad link;
        // that is a step-3 (link) problem, not a transient server error.
        let r = SetupHint.remedy(for: .shape("page id not found in url: https://notion.so/no-id"))
        XCTAssertEqual(r.returnToStep, 3)
        XCTAssertTrue(r.message.contains("링크"), r.message)
    }
}
