import XCTest
@testable import DailyReportKit

final class UpdateCheckerTests: XCTestCase {
    /// A GitHub `releases/latest` payload: a .dmg asset (optional) plus a decoy zip.
    private func latestJSON(tag: String,
                            dmg: String? = "https://example.com/DailyReport-1.1.0.dmg",
                            body: String = "릴리스 노트") -> [String: Any] {
        var assets: [[String: Any]] = []
        if let dmg { assets.append(["name": "DailyReport-1.1.0.dmg", "browser_download_url": dmg]) }
        assets.append(["name": "Source.zip", "browser_download_url": "https://example.com/Source.zip"])
        return ["tag_name": tag, "body": body, "assets": assets]
    }

    // MARK: - SemVer

    func test_semver_isNewer_basic() {
        XCTAssertTrue(SemVer.isNewer("1.1.0", than: "1.0.0"))
        XCTAssertFalse(SemVer.isNewer("1.0.0", than: "1.0.0"))   // equal is not newer
        XCTAssertFalse(SemVer.isNewer("1.0.0", than: "1.1.0"))
    }

    func test_semver_double_digits_and_v_prefix() {
        XCTAssertTrue(SemVer.isNewer("v1.10.0", than: "v1.9.0"))  // 10 > 9 numerically, not lexically
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.99.99"))
        XCTAssertFalse(SemVer.isNewer("v1.0", than: "1.0.0"))     // 1.0 == 1.0.0
        XCTAssertTrue(SemVer.isNewer("1.0.1", than: "1.0"))       // 1.0.1 > 1.0(.0)
    }

    // MARK: - UpdateChecker

    func test_returns_release_when_remote_newer() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v1.1.0"))
        let info = await UpdateChecker(transport: mock)
            .latestIfNewer(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertEqual(info?.version, "1.1.0")
        XCTAssertEqual(info?.dmgURL, "https://example.com/DailyReport-1.1.0.dmg")
        XCTAssertEqual(info?.notes, "릴리스 노트")
        XCTAssertEqual(mock.sentRequests.first?.url.absoluteString,
                       "https://api.github.com/repos/o/r/releases/latest")
    }

    func test_nil_when_same_version() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v1.0.0"))
        let info = await UpdateChecker(transport: mock).latestIfNewer(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertNil(info)
    }

    func test_nil_when_remote_older() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v0.9.0"))
        let info = await UpdateChecker(transport: mock).latestIfNewer(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertNil(info)
    }

    func test_nil_when_newer_but_no_dmg_asset() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v1.1.0", dmg: nil))
        let info = await UpdateChecker(transport: mock).latestIfNewer(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertNil(info)   // newer, but nothing installable
    }

    func test_nil_on_http_error() async {
        let mock = MockTransport()
        mock.enqueue(status: 404, json: ["message": "Not Found"])
        let info = await UpdateChecker(transport: mock).latestIfNewer(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertNil(info)
    }

    // MARK: - check() 3-way (manual "check now" needs to tell "up to date" from "failed")

    func test_check_returns_newer_when_remote_newer() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v1.1.0"))
        let r = await UpdateChecker(transport: mock).check(current: "1.0.0", owner: "o", repo: "r")
        guard case .newer(let info) = r else { return XCTFail("expected .newer, got \(r)") }
        XCTAssertEqual(info.version, "1.1.0")
    }

    func test_check_upToDate_when_same_or_older() async {
        for tag in ["v1.0.0", "v0.9.0"] {
            let mock = MockTransport()
            mock.enqueue(status: 200, json: latestJSON(tag: tag))
            let r = await UpdateChecker(transport: mock).check(current: "1.0.0", owner: "o", repo: "r")
            XCTAssertEqual(r, .upToDate, tag)
        }
    }

    func test_check_upToDate_when_newer_but_no_dmg() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: latestJSON(tag: "v1.1.0", dmg: nil))
        let r = await UpdateChecker(transport: mock).check(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertEqual(r, .upToDate)   // nothing installable → treat as up to date, not a failure
    }

    func test_check_failed_on_http_error() async {
        let mock = MockTransport()
        mock.enqueue(status: 404, json: ["message": "Not Found"])
        let r = await UpdateChecker(transport: mock).check(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertEqual(r, .failed)     // a failed check must NOT masquerade as "up to date"
    }

    func test_check_failed_on_transport_error() async {
        let mock = MockTransport()   // empty queue → 599 (non-200)
        let r = await UpdateChecker(transport: mock).check(current: "1.0.0", owner: "o", repo: "r")
        XCTAssertEqual(r, .failed)
    }
}
