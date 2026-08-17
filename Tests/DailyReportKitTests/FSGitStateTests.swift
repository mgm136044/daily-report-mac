import XCTest
@testable import DailyReportKit

final class FSGitStateTests: XCTestCase {
    private var repo = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        repo = fm.temporaryDirectory.appendingPathComponent("gitstate-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        git(["init", "-q"]); git(["config", "user.email", "me@example.com"])
        git(["config", "user.name", "Me"])
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: repo) }

    private var collector: FSCollector {
        FSCollector(config: .defaultConfig, selfArtifactBase: "/opt/daily-report")
    }

    func test_tracked_clean_vs_untracked_and_modified() throws {
        write("committed.txt", "v1\n"); git(["add", "-A"]); git(["commit", "-q", "-m", "c"])
        write("untracked.txt", "new\n")             // untracked → not tracked, not dirty
        write("committed.txt", "v2\n")              // tracked but now modified → dirty

        let (tracked, dirty) = collector.gitState(repo)
        XCTAssertTrue(tracked.contains(repo + "/committed.txt"))
        XCTAssertFalse(tracked.contains(repo + "/untracked.txt"))   // ls-files omits untracked
        XCTAssertTrue(dirty.contains(repo + "/committed.txt"))      // " M"
        // `git status --porcelain` lists untracked as "?? path", so it lands in
        // dirty (verified against the Python original). Harmless: the exclusion
        // is `tracked && !dirty`, and untracked files have tracked == false, so
        // they are kept regardless of dirty membership.
        XCTAssertTrue(dirty.contains(repo + "/untracked.txt"))
    }

    func test_rename_records_both_paths_in_dirty() throws {
        write("old.txt", "content\n"); git(["add", "-A"]); git(["commit", "-q", "-m", "c"])
        git(["mv", "old.txt", "new.txt"])           // staged rename
        let (_, dirty) = collector.gitState(repo)
        XCTAssertTrue(dirty.contains(repo + "/new.txt"))
        XCTAssertTrue(dirty.contains(repo + "/old.txt"))   // the bare old path, whole
    }

    // --- helpers ---
    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", repo] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_CONFIG_GLOBAL"] = "/dev/null"; e["GIT_CONFIG_SYSTEM"] = "/dev/null"
        p.environment = e
        let sink = Pipe(); p.standardOutput = sink; p.standardError = sink
        try? p.run(); p.waitUntilExit()
    }
    private func write(_ name: String, _ body: String) {
        fm.createFile(atPath: repo + "/" + name, contents: Data(body.utf8))
    }
}
