import XCTest
@testable import DailyReportKit

final class HTTPTransportTests: XCTestCase {
    func test_mock_returns_enqueued_responses_in_order_and_records_requests() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["a": 1])
        mock.enqueue(status: 500, json: ["code": "boom"])

        let first = try await mock.send(method: "GET",
            url: URL(string: "https://x/1")!, headers: [:], body: nil)
        let second = try await mock.send(method: "POST",
            url: URL(string: "https://x/2")!, headers: [:], body: Data("hi".utf8))

        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(second.status, 500)
        XCTAssertEqual(mock.sentRequests.count, 2)
        XCTAssertEqual(mock.sentRequests[1].method, "POST")
    }
}
