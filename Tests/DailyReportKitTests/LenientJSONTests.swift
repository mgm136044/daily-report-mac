import XCTest
@testable import DailyReportKit

final class LenientJSONTests: XCTestCase {
    func test_valid_json_parses_normally() {
        let obj = LenientJSON.object(#"{"a": 1, "b": "x"}"#) as? [String: Any]
        XCTAssertEqual(obj?["a"] as? Int, 1)
        XCTAssertEqual(obj?["b"] as? String, "x")
    }

    func test_bare_nan_value_is_recovered_as_null() {
        let obj = LenientJSON.object(#"{"score": NaN, "name": "ok"}"#) as? [String: Any]
        XCTAssertNotNil(obj)                       // JSONSerialization alone returns nil here
        XCTAssertTrue(obj?["score"] is NSNull)
        XCTAssertEqual(obj?["name"] as? String, "ok")
    }

    func test_infinity_values_are_recovered() {
        let obj = LenientJSON.object(#"{"a": Infinity, "b": -Infinity, "c": [NaN, 2]}"#) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertTrue(obj?["a"] is NSNull)
        XCTAssertTrue(obj?["b"] is NSNull)
        XCTAssertEqual((obj?["c"] as? [Any])?.count, 2)
    }

    func test_nan_inside_a_string_is_not_touched() {
        // A record that is valid JSON whose string value merely contains "NaN".
        let obj = LenientJSON.object(#"{"msg": "the value is NaN here"}"#) as? [String: Any]
        XCTAssertEqual(obj?["msg"] as? String, "the value is NaN here")
    }

    func test_unrecoverable_line_returns_nil() {
        XCTAssertNil(LenientJSON.object("{not json at all"))
    }
}
