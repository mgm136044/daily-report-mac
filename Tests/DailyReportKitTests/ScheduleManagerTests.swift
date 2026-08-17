import XCTest
@testable import DailyReportKit

final class ScheduleManagerTests: XCTestCase {
    private func plist(hour: Int, minute: Int,
                       runner: String = "/Applications/DailyReport.app/Contents/MacOS/daily-report-runner",
                       logsDir: String = "/Users/me/Library/Application Support/DailyReport/logs",
                       home: String = "/Users/me", user: String = "me") throws -> [String: Any] {
        let data = ScheduleManager.plistData(hour: hour, minute: minute, runnerPath: runner,
                                             logsDir: logsDir, home: home, user: user)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    // MARK: - changeNeeded (guards the crash: skip a redundant reinstall that would
    // otherwise run launchctl inside a SwiftUI update cycle → re-entrant runloop SIGSEGV)

    func test_changeNeeded_true_when_toggling_on_or_off() {
        XCTAssertTrue(ScheduleManager.changeNeeded(requestedOn: true, currentlyOn: false,
                                                   hour: 4, minute: 5, currentHour: 4, currentMinute: 5))
        XCTAssertTrue(ScheduleManager.changeNeeded(requestedOn: false, currentlyOn: true,
                                                   hour: 4, minute: 5, currentHour: 4, currentMinute: 5))
    }

    func test_changeNeeded_false_when_both_off() {
        XCTAssertFalse(ScheduleManager.changeNeeded(requestedOn: false, currentlyOn: false,
                                                    hour: 9, minute: 0, currentHour: 4, currentMinute: 5))
    }

    func test_changeNeeded_false_when_on_and_same_time() {
        // This is the onAppear-seed case that must NOT reinstall.
        XCTAssertFalse(ScheduleManager.changeNeeded(requestedOn: true, currentlyOn: true,
                                                    hour: 4, minute: 5, currentHour: 4, currentMinute: 5))
    }

    func test_changeNeeded_true_when_on_and_time_differs() {
        XCTAssertTrue(ScheduleManager.changeNeeded(requestedOn: true, currentlyOn: true,
                                                   hour: 6, minute: 5, currentHour: 4, currentMinute: 5))
        XCTAssertTrue(ScheduleManager.changeNeeded(requestedOn: true, currentlyOn: true,
                                                   hour: 4, minute: 30, currentHour: 4, currentMinute: 5))
    }

    func test_plist_is_valid_with_schedule_and_absolute_paths() throws {
        let p = try plist(hour: 4, minute: 5)
        XCTAssertEqual(p["Label"] as? String, ScheduleManager.label)

        let interval = p["StartCalendarInterval"] as? [String: Any]
        XCTAssertEqual(interval?["Hour"] as? Int, 4)
        XCTAssertEqual(interval?["Minute"] as? Int, 5)

        let args = p["ProgramArguments"] as? [String]
        XCTAssertEqual(args?.first, "/usr/bin/caffeinate")   // absolute; no BundleProgram in a self-managed plist
        XCTAssertTrue(args?.contains("-s") ?? false)
        XCTAssertTrue(args?.contains("-i") ?? false)
        XCTAssertTrue(args?.contains("/Applications/DailyReport.app/Contents/MacOS/daily-report-runner") ?? false)
        XCTAssertEqual(args?.last, "run-day")
    }

    func test_plist_env_has_keychain_and_path_essentials() throws {
        let env = try plist(hour: 4, minute: 5)["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(env?["USER"], "me")             // login keychain is keyed on USER
        XCTAssertEqual(env?["HOME"], "/Users/me")
        XCTAssertEqual(env?["LOGNAME"], "me")
        XCTAssertTrue(env?["PATH"]?.contains("/opt/homebrew/bin") ?? false)  // find claude/codex
        XCTAssertEqual(env?["TZ"], "Asia/Seoul")
    }

    func test_plist_runAtLoad_and_bundle_attribution() throws {
        let p = try plist(hour: 4, minute: 5)
        XCTAssertEqual(p["RunAtLoad"] as? Bool, true)   // ledger-gated idempotent → safe for backfill
        XCTAssertEqual((p["AssociatedBundleIdentifiers"] as? [String])?.first, "com.mgm136044.DailyReportMac")
        XCTAssertEqual(p["StandardOutPath"] as? String,
                       "/Users/me/Library/Application Support/DailyReport/logs/stdout.log")
    }

    func test_time_is_configurable() throws {
        let interval = try plist(hour: 18, minute: 30)["StartCalendarInterval"] as? [String: Any]
        XCTAssertEqual(interval?["Hour"] as? Int, 18)
        XCTAssertEqual(interval?["Minute"] as? Int, 30)
    }

    func test_plistURL_is_in_user_launchagents() {
        let url = ScheduleManager.plistURL(home: "/Users/me")
        XCTAssertEqual(url.path, "/Users/me/Library/LaunchAgents/\(ScheduleManager.label).plist")
    }
}
