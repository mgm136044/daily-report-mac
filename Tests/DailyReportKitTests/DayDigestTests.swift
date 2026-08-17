import XCTest
@testable import DailyReportKit

final class DayDigestTests: XCTestCase {
    func test_digest_round_trips_and_status_is_a_string() throws {
        let digest = DayDigest(
            date: "2026-08-10", markdown: "# hi", summary: "did things",
            projects: ["app"], tags: ["swift"], sessions: 3, commits: 5,
            files: 12, status: .done, source: "runner")
        let data = try JSONEncoder().encode(digest)
        let back = try JSONDecoder().decode(DayDigest.self, from: data)
        XCTAssertEqual(back, digest)
        XCTAssertEqual(DayStatus.done.rawValue, "done")
    }

    func test_status_is_case_iterable_with_three_cases() {
        XCTAssertEqual(DayStatus.allCases, [.done, .draft, .failed])
    }
}
