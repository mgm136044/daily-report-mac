import XCTest
@testable import DailyReportKit

final class RunLockTests: XCTestCase {
    private var dir = ""
    private let fm = FileManager.default
    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: dir) }

    func test_second_acquire_fails_until_released() {
        let path = dir + "/run.lock"
        let first = RunLock.acquire(path: path)
        XCTAssertNotNil(first)
        XCTAssertNil(RunLock.acquire(path: path))    // second instance is refused
        first?.release()
        let third = RunLock.acquire(path: path)
        XCTAssertNotNil(third)                        // available again after release
        third?.release()
    }

    func test_ensureDirs_creates_owner_only() throws {
        let sub = dir + "/state"
        RunSupport.ensureDirs([sub])
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: sub, isDirectory: &isDir) && isDir.boolValue)
        let perms = (try fm.attributesOfItem(atPath: sub)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o700)
    }
}
