import XCTest
@testable import DailyReportKit

final class RunExitTests: XCTestCase {
    func test_alreadyRunning_exit_code_is_75() {
        // The runner returns this distinct code when the flock is held, so the
        // app can tell "already running" apart from "finished" (both used to be 0).
        XCTAssertEqual(RunExit.alreadyRunning, 75)
    }

    func test_zero_maps_to_ok() {
        XCTAssertEqual(RunExit.outcome(for: 0), .ok)
    }

    func test_lock_contention_is_busy_not_error() {
        guard case .busy(let msg) = RunExit.outcome(for: RunExit.alreadyRunning) else {
            return XCTFail("expected .busy for the already-running code")
        }
        XCTAssertTrue(msg.contains("생성 중"), "busy message should explain a run is in progress")
    }

    func test_other_nonzero_is_failed_and_names_the_code() {
        guard case .failed(let msg) = RunExit.outcome(for: 3) else {
            return XCTFail("expected .failed for an unexpected non-zero code")
        }
        XCTAssertTrue(msg.contains("3"), "failure message should include the exit code")
    }
}
