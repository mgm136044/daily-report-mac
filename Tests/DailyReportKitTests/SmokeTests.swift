import XCTest
@testable import DailyReportKit

final class SmokeTests: XCTestCase {
    func test_package_exposes_a_version() {
        XCTAssertFalse(DailyReport.version.isEmpty)
    }
}
