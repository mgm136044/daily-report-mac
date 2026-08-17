import XCTest
@testable import DailyReportKit

final class FSRepoRootTests: XCTestCase {
    private var root = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("reporoot-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private var collector: FSCollector {
        FSCollector(config: .defaultConfig, selfArtifactBase: "/opt/daily-report")
    }

    func test_finds_repo_with_git_dir() throws {
        try fm.createDirectory(atPath: root + "/proj/.git", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/proj/src", withIntermediateDirectories: true)
        XCTAssertEqual(collector.repoRoot(root + "/proj/src/a.txt"), root + "/proj")
    }

    func test_finds_repo_with_git_file() throws {   // submodule / worktree
        try fm.createDirectory(atPath: root + "/wt", withIntermediateDirectories: true)
        fm.createFile(atPath: root + "/wt/.git", contents: Data("gitdir: ...".utf8))
        XCTAssertEqual(collector.repoRoot(root + "/wt/file.txt"), root + "/wt")
    }

    func test_returns_nil_outside_any_repo() throws {
        try fm.createDirectory(atPath: root + "/plain", withIntermediateDirectories: true)
        XCTAssertNil(collector.repoRoot(root + "/plain/a.txt"))
    }
}
