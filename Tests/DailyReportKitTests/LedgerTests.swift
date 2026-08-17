import XCTest
@testable import DailyReportKit

final class LedgerTests: XCTestCase {
    private var dir = ""
    private let fm = FileManager.default
    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: dir) }

    func test_config_run_default() {
        XCTAssertEqual(DayConfig.defaultConfig.run.watchdogSec, 2400)
    }

    func test_missing_ledger_reads_empty() {
        let state = Ledger.read(dir + "/lastrun.json")
        XCTAssertTrue(Ledger.completedDates(state).isEmpty)
    }

    func test_record_then_roundtrip() throws {
        let url = dir + "/lastrun.json"
        var state = Ledger.read(url)
        state = Ledger.record(state, date: "2026-08-12", entry: ["at": "t", "sessions": 3])
        try Ledger.write(state, to: url)
        let reloaded = Ledger.read(url)
        XCTAssertEqual(Ledger.completedDates(reloaded), ["2026-08-12"])
        let entry = (reloaded["completed"] as? [String: Any])?["2026-08-12"] as? [String: Any]
        XCTAssertEqual(entry?["sessions"] as? Int, 3)
    }

    func test_corrupt_ledger_reads_empty() throws {
        let url = dir + "/lastrun.json"
        try "{ not json".write(toFile: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(Ledger.completedDates(Ledger.read(url)).isEmpty)
    }
}
