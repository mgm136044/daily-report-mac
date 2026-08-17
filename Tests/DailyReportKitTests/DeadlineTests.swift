import XCTest
@testable import DailyReportKit

final class DeadlineTests: XCTestCase {
    func test_fast_work_returns_its_value() {
        let r = Deadline.run(seconds: 1.0) { 40 + 2 }
        XCTAssertEqual(r, 42)
    }

    func test_work_exceeding_deadline_returns_nil() {
        // Simulates a folder access blocked on a TCC prompt: the closure never
        // returns in time, so the caller gets nil and can skip the root.
        let r: Int? = Deadline.run(seconds: 0.05) {
            Thread.sleep(forTimeInterval: 0.6)
            return 99
        }
        XCTAssertNil(r)
    }
}

final class RootAccessTests: XCTestCase {
    private let fm = FileManager.default

    func test_existing_readable_dir_is_reachable() {
        let dir = fm.temporaryDirectory.appendingPathComponent("ra-\(UUID().uuidString)").path
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        XCTAssertTrue(RootAccess.reachable(dir, timeoutSec: 2))
    }

    func test_reachable_is_about_responsiveness_not_existence() {
        // A non-existent path fails FAST (no block), so it is "reachable" (responsive).
        // Only a path that BLOCKS past the deadline is treated as unreachable.
        XCTAssertTrue(RootAccess.reachable("/no/such/path/\(UUID().uuidString)", timeoutSec: 2))
    }
}
