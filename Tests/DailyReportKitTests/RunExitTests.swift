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

    // MARK: - "no activity" exit code (produced nothing, no failures)

    func test_noActivity_exit_code_is_73() {
        // A distinct code so the app can tell "finished but made nothing" apart from
        // 0 (finished) and 75 (busy). 73 == EX_CANTCREAT ("can't create output").
        XCTAssertEqual(RunExit.noActivity, 73)
    }

    func test_finalCode_no_reports_and_no_failures_is_noActivity() {
        // Ran to completion but produced zero reports (every target had no activity).
        XCTAssertEqual(RunExit.finalCode(produced: 0, failed: 0), RunExit.noActivity)
    }

    func test_finalCode_with_produced_reports_is_zero() {
        XCTAssertEqual(RunExit.finalCode(produced: 1, failed: 0), 0)
    }

    func test_finalCode_failures_stay_zero_conservative() {
        // Conservative scope: failures keep the existing exit-0 behavior (improving the
        // failure exit code is out of scope); only produced==0 && failed==0 is noActivity.
        XCTAssertEqual(RunExit.finalCode(produced: 0, failed: 2), 0)
    }

    func test_noActivity_code_maps_to_noActivity_outcome() {
        XCTAssertEqual(RunExit.outcome(for: RunExit.noActivity), .noActivity)
    }
}
