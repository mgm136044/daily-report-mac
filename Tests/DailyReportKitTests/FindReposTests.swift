import XCTest
@testable import DailyReportKit

final class FindReposTests: XCTestCase {
    private var root: String = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("findrepos-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private func mkdir(_ rel: String) throws {
        try fm.createDirectory(atPath: root + "/" + rel, withIntermediateDirectories: true)
    }
    private func touch(_ rel: String) throws {
        fm.createFile(atPath: root + "/" + rel, contents: Data())
    }
    private func config(maxDepth: Int = 6, walkExclude: [String] = [],
                        extra: [String] = []) -> DayConfig {
        var c = DayConfig.defaultConfig
        c.sources.gitSearchRoot = root
        c.sources.gitMaxDepth = maxDepth
        c.sources.walkExclude = walkExclude
        c.sources.extraRepoRoots = extra
        return c
    }

    func test_finds_a_git_repo() throws {
        try mkdir("proj/.git")
        try touch("proj/file.txt")
        let repos = GitCollector(config: config()).findRepos()
        XCTAssertTrue(repos.contains(DayConfig.nfc(root + "/proj")))
    }

    func test_depth_cap_prunes_deep_repos() throws {
        try mkdir("a/b/.git")     // repo dir "a/b" is at depth 2
        let shallow = GitCollector(config: config(maxDepth: 3)).findRepos()
        XCTAssertTrue(shallow.contains(DayConfig.nfc(root + "/a/b")))
        let capped = GitCollector(config: config(maxDepth: 2)).findRepos()
        XCTAssertFalse(capped.contains(DayConfig.nfc(root + "/a/b")))
    }

    func test_walk_exclude_prunes_subtree() throws {
        try mkdir("skip/proj/.git")
        let repos = GitCollector(config: config(walkExclude: ["/skip/"])).findRepos()
        XCTAssertFalse(repos.contains(DayConfig.nfc(root + "/skip/proj")))
    }

    func test_extra_repo_roots_recover_a_skipped_repo() throws {
        try mkdir("skip/proj/.git")
        let extra = [root + "/skip/proj"]
        let repos = GitCollector(config: config(walkExclude: ["/skip/"], extra: extra)).findRepos()
        XCTAssertTrue(repos.contains(DayConfig.nfc(root + "/skip/proj")))
    }

    func test_symlinked_directory_is_not_descended() throws {
        try mkdir("real/proj/.git")
        try fm.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")
        let repos = GitCollector(config: config()).findRepos()
        XCTAssertTrue(repos.contains(DayConfig.nfc(root + "/real/proj")))
        XCTAssertFalse(repos.contains(DayConfig.nfc(root + "/link/proj")))
    }

    func test_dot_git_file_is_not_a_repo() throws {
        try mkdir("notrepo")
        try touch("notrepo/.git")     // a gitfile, not a directory
        let repos = GitCollector(config: config()).findRepos()
        XCTAssertFalse(repos.contains(DayConfig.nfc(root + "/notrepo")))
    }
}
