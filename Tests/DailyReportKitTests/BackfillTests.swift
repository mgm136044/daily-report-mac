import XCTest
@testable import DailyReportKit

final class BackfillTests: XCTestCase {
    func test_pending_days_are_closed_days_not_in_ledger() {
        let state: [String: Any] = ["completed": ["2026-08-11": ["at": "x"]]]
        let pending = Backfill.pendingDays(state: state, today: "2026-08-13")
        XCTAssertTrue(pending.contains("2026-08-12"))         // yesterday, closed, not done
        XCTAssertFalse(pending.contains("2026-08-11"))        // already completed
        XCTAssertFalse(pending.contains("2026-08-13"))        // today has not closed
        XCTAssertEqual(pending, pending.sorted())             // sorted ascending
        XCTAssertEqual(pending.count, 13)                     // 14-day window minus the one done
    }

    func test_seed_first_run_marks_pre_install_days_skipped() {
        let seeded = Backfill.seedFirstRun(state: ["completed": [String: Any]()],
                                           ledgerExists: false, today: "2026-08-13")
        let done = Ledger.completedDates(seeded)
        XCTAssertFalse(done.contains("2026-08-12"))           // most recent closed day is left to run
        XCTAssertTrue(done.contains("2026-08-11"))            // older days marked skipped
        XCTAssertTrue(done.contains("2026-07-30"))            // down to the 14-day edge
    }

    func test_seed_first_run_is_noop_when_ledger_exists() {
        let state: [String: Any] = ["completed": ["2026-08-10": ["at": "x"]]]
        let seeded = Backfill.seedFirstRun(state: state, ledgerExists: true, today: "2026-08-13")
        XCTAssertEqual(Ledger.completedDates(seeded), ["2026-08-10"])   // untouched
    }

    func test_seed_first_run_marks_notion_dates_synced_not_preinstall() {
        // Dates already reported in Notion must be seeded "synced", not "설치 이전 날짜" —
        // so the runner converges with the app's reconcile (no flaky race).
        let synced: Set<String> = ["2026-08-11", "2026-08-09"]
        let seeded = Backfill.seedFirstRun(state: ["completed": [String: Any]()],
                                           ledgerExists: false, today: "2026-08-13", syncedDates: synced)
        let completed = seeded["completed"] as! [String: [String: Any]]
        XCTAssertEqual(completed["2026-08-11"]?["synced"] as? String, "notion")
        XCTAssertNil(completed["2026-08-11"]?["skipped"])
        XCTAssertEqual(completed["2026-08-09"]?["synced"] as? String, "notion")
        XCTAssertEqual(completed["2026-08-10"]?["skipped"] as? String, "설치 이전 날짜")   // not in Notion → skip
    }
}
