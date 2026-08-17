import XCTest
@testable import DailyReportKit

final class CollectGitTests: XCTestCase {
    private var root: String = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("collectgit-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    // Empty authors must NOT shell out — it returns the skip marker directly.
    func test_empty_authors_skips_without_scanning() {
        var c = DayConfig.defaultConfig
        c.git.authors = []
        let result = GitCollector(config: c).collectGit(date: "2026-08-12")
        XCTAssertEqual(result.skipped, "git.authors 가 비어 있어 커밋을 수집하지 않았습니다")
        XCTAssertTrue(result.commits.isEmpty)
        XCTAssertEqual(result.reposScanned, 0)
    }

    // Integration: a real repo with commits inside/outside the window and by
    // another author. Requires the `git` binary (present on macOS dev machines).
    func test_collects_windowed_commits_by_configured_author() throws {
        let repo = root + "/proj"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        git(["init", "-q"], repo)
        git(["config", "user.email", "me@example.com"], repo)
        git(["config", "user.name", "Me"], repo)

        // Create commits in CHRONOLOGICAL order (monotonic committer dates), as a
        // real branch always is. `git log --since` stops walking a line of history
        // once it hits a commit older than the cutoff, assuming ancestors are older
        // still — so a too-early commit placed BETWEEN two in-window commits would
        // hide the older one. Keep these in time order or the in-window commit
        // vanishes (a git traversal quirk, not a collector bug — the Python original
        // behaves identically).
        commit(repo, file: "b.txt", body: "two\nthree\n", subject: "too early",
               date: "2026-08-11T10:00:00+09:00")                      // before window
        commit(repo, file: "a.txt", body: "one\n", subject: "inside window",
               date: "2026-08-12T10:00:00+09:00")                      // in window, mine
        commit(repo, file: "c.txt", body: "four\n", subject: "not mine",
               date: "2026-08-12T12:00:00+09:00", author: "Other <other@example.com>")

        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9              // deterministic regardless of CI zone
        c.git.authors = ["me@example.com"]
        c.sources.gitSearchRoot = root
        c.sources.gitMaxDepth = 6

        let result = GitCollector(config: c).collectGit(date: "2026-08-12")

        XCTAssertNil(result.skipped)
        XCTAssertGreaterThanOrEqual(result.reposScanned, 1)
        let subjects = result.commits.map(\.subject)
        XCTAssertEqual(subjects, ["inside window"])            // only in-window, mine
        let mine = result.commits[0]
        XCTAssertEqual(mine.sha.count, 8)
        XCTAssertEqual(mine.author, "me@example.com")
        XCTAssertEqual(mine.project, "proj")
        XCTAssertFalse(mine.at.isEmpty)
        // The reliable per-commit signal is the touched paths.
        XCTAssertEqual(mine.paths, [repo + "/a.txt"])
        // git's later --name-only overrides the earlier --shortstat, so git emits
        // no "N files changed" summary and the counts stay 0. This is faithful to
        // the Python original (verified: its _parse_git_log yields 0/0/0 on the
        // same real git output). The parser's shortstat branch is still exercised
        // by GitParseTests, and would fire if git ever emitted the summary.
        XCTAssertEqual(mine.files, 0)
        XCTAssertEqual(mine.insertions, 0)
        XCTAssertEqual(mine.deletions, 0)
    }

    // --- helpers -----------------------------------------------------------
    private func git(_ args: [String], _ cwd: String, env: [String: String] = [:]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", cwd] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_CONFIG_GLOBAL"] = "/dev/null"; e["GIT_CONFIG_SYSTEM"] = "/dev/null"
        for (k, v) in env { e[k] = v }
        p.environment = e
        let sink = Pipe(); p.standardOutput = sink; p.standardError = sink
        try? p.run(); p.waitUntilExit()
    }
    private func commit(_ repo: String, file: String, body: String, subject: String,
                        date: String, author: String? = nil) {
        fm.createFile(atPath: repo + "/" + file, contents: Data(body.utf8))
        git(["add", "-A"], repo)
        var args = ["commit", "-q", "-m", subject]
        if let author { args += ["--author", author] }
        git(args, repo, env: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date])
    }
}
