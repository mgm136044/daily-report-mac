import XCTest
@testable import DailyReportKit

final class RefineTests: XCTestCase {
    private var cfg: DayConfig {
        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        // make the cwds below resolve to a project label without touching disk:
        c.projects.containers = ["/work"]      // /work/proj is a project (child of a container)
        return c
    }

    private func session(prompts: [String] = [], written: [String] = [],
                         sessions: [String] = ["s1"]) -> SessionProject {
        SessionProject(sessions: sessions, branches: ["main"], slugs: ["t"], skillsUsed: [],
                       prompts: prompts, filesWritten: written, filesEdited: [], filesTracked: [],
                       bashCommands: [], todos: [], firstTS: nil, lastTS: nil)
    }
    private func emptyGit() -> GitCollection {
        GitCollection(commits: [], reposScanned: 0, failures: [], skipped: nil)
    }

    func test_claude_and_codex_roll_into_one_label() {
        let claude = ["/work/proj": session(prompts: ["a"], written: ["/work/proj/x.swift"])]
        let codex = ["/work/proj": CodexProject(
            sessions: ["c1"], branches: [], prompts: ["b"], bashCommands: ["git status"],
            filesAdded: ["/work/proj/y.swift"], filesUpdated: [], filesDeleted: [],
            plans: ["plan"], outcomes: ["done"], subagentThreads: 0, firstTS: nil, lastTS: nil)]
        let out = Refine.refine(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            claude: claude, labeled: [:], codex: codex, disk: [:], git: emptyGit(), config: cfg)

        XCTAssertEqual(out.projects.count, 1)
        let p = out.projects[0]
        XCTAssertEqual(p.label, "proj")
        XCTAssertEqual(Set(p.tools), ["Claude Code", "Codex"])
        XCTAssertEqual(p.sessionCount, 2)                       // s1 + c1
        XCTAssertEqual(p.filesWritten, ["/work/proj/x.swift", "/work/proj/y.swift"])
        XCTAssertEqual(p.prompts.count, 2)
    }

    func test_disk_files_minus_tool_recorded() {
        // x.swift is tool-recorded (written); it must not reappear under files_on_disk.
        let claude = ["/work/proj": session(written: ["/work/proj/x.swift"])]
        let disk = ["/work/proj": ["/work/proj/x.swift", "/work/proj/gen.csv"]]
        let out = Refine.refine(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            claude: claude, labeled: [:], codex: [:], disk: disk, git: emptyGit(), config: cfg)
        XCTAssertEqual(out.projects[0].filesOnDisk, ["/work/proj/gen.csv"])
    }

    func test_git_commit_attaches_to_project() {
        let commit = GitCommit(repo: "/work/proj", project: "proj", sha: "abc12345",
            at: "2026-08-12T10:00:00+09:00", authoredAt: "x", author: "me", subject: "fix",
            files: 0, insertions: 0, deletions: 0, paths: [])
        let claude = ["/work/proj": session(prompts: ["a"])]
        let out = Refine.refine(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            claude: claude, labeled: [:], codex: [:], disk: [:],
            git: GitCollection(commits: [commit], reposScanned: 1, failures: [], skipped: nil), config: cfg)
        XCTAssertEqual(out.projects[0].commits.map(\.sha), ["abc12345"])
        XCTAssertEqual(out.stats.commits, 1)
    }

    func test_unlabelable_cwd_is_dropped() {
        let claude = ["/": session(prompts: ["a"])]     // "/" resolves to no label
        let out = Refine.refine(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            claude: claude, labeled: [:], codex: [:], disk: [:], git: emptyGit(), config: cfg)
        XCTAssertTrue(out.projects.isEmpty)
        XCTAssertEqual(out.stats.cwdsDropped, 1)
        XCTAssertEqual(out.droppedCwds, ["/"])
    }

    func test_orders_busiest_first() {
        let claude = [
            "/work/quiet": session(prompts: ["one"], sessions: ["q"]),
            "/work/busy": session(prompts: ["a", "b", "c"], sessions: ["b"]),
        ]
        let out = Refine.refine(date: "2026-08-12", windowStart: "s", windowEnd: "e",
            claude: claude, labeled: [:], codex: [:], disk: [:], git: emptyGit(), config: cfg)
        XCTAssertEqual(out.projects.map(\.label), ["busy", "quiet"])
    }
}
