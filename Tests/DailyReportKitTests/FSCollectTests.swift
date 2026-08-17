import XCTest
@testable import DailyReportKit

final class FSCollectTests: XCTestCase {
    private var root = ""
    private let fm = FileManager.default
    // 2026-08-12 window with +09 boundary 4 → [08-12 04:00+09, 08-13 04:00+09)
    private let inWindow = ISO8601DateFormatter().date(from: "2026-08-12T10:00:00+09:00")!
    private let before = ISO8601DateFormatter().date(from: "2026-08-11T10:00:00+09:00")!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("fscol-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private func write(_ rel: String, at date: Date, body: String = "x") throws {
        let full = root + "/" + rel
        try fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        fm.createFile(atPath: full, contents: Data(body.utf8))
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: full)
    }
    private func config() -> DayConfig {
        var c = DayConfig.defaultConfig; c.day.timezoneOffsetHours = 9; return c
    }
    private var collector: FSCollector {
        FSCollector(config: config(), selfArtifactBase: "/opt/daily-report")
    }

    func test_keeps_in_window_drops_out_of_window_and_noise() throws {
        try write("src/kept.txt", at: inWindow)
        try write("src/old.txt", at: before)                 // out of window
        try write("src/skip.pyc", at: inWindow)              // noise suffix
        try write("node_modules/x.js", at: inWindow)         // noise dir
        let out = collector.collect(date: "2026-08-12", roots: [root], committed: [])
        XCTAssertEqual(out.roots[root], [root + "/src/kept.txt"])
        XCTAssertEqual(out.stats.files, 1)
        XCTAssertEqual(out.stats.rootsScanned, 1)
    }

    func test_tracked_clean_file_excluded_unless_committed_today() throws {
        // real repo: a tracked+clean file with an in-window mtime is git-moved,
        // so excluded — unless it is in the committed set.
        gitInit()
        try write("tracked.txt", at: inWindow, body: "v1\n")
        git(["add", "-A"]); git(["commit", "-q", "-m", "c"])
        try fm.setAttributes([.modificationDate: inWindow], ofItemAtPath: root + "/tracked.txt")

        let excluded = collector.collect(date: "2026-08-12", roots: [root], committed: [])
        XCTAssertFalse(excluded.roots[root]?.contains(root + "/tracked.txt") ?? false)

        let kept = collector.collect(date: "2026-08-12", roots: [root],
                                     committed: [root + "/tracked.txt"])
        XCTAssertTrue(kept.roots[root]?.contains(root + "/tracked.txt") ?? false)
    }

    func test_untracked_file_in_repo_is_kept() throws {
        gitInit()
        try write("committed.txt", at: before, body: "v1\n")
        git(["add", "-A"]); git(["commit", "-q", "-m", "c"])
        try write("scratch.txt", at: inWindow)               // untracked, in window
        let out = collector.collect(date: "2026-08-12", roots: [root], committed: [])
        XCTAssertTrue(out.roots[root]?.contains(root + "/scratch.txt") ?? false)
    }

    func test_caps_at_80_keeping_most_recent() throws {
        let base = ISO8601DateFormatter().date(from: "2026-08-12T05:00:00+09:00")!
        for i in 0..<85 {
            // later index → later mtime, so indices 5..84 are the newest 80
            try write("bulk/f\(String(format: "%03d", i)).txt",
                      at: base.addingTimeInterval(Double(i) * 60))
        }
        let out = collector.collect(date: "2026-08-12", roots: [root], committed: [])
        XCTAssertEqual(out.roots[root]?.count, 80)
        XCTAssertEqual(out.stats.filesDroppedOverCap, 5)
        XCTAssertFalse(out.roots[root]?.contains(root + "/bulk/f000.txt") ?? true)  // oldest dropped
        XCTAssertTrue(out.roots[root]?.contains(root + "/bulk/f084.txt") ?? false)  // newest kept
    }

    // --- helpers ---
    private func gitInit() {
        git(["init", "-q"]); git(["config", "user.email", "me@example.com"]); git(["config", "user.name", "Me"])
    }
    private func git(_ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", root] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_CONFIG_GLOBAL"] = "/dev/null"; e["GIT_CONFIG_SYSTEM"] = "/dev/null"; p.environment = e
        let sink = Pipe(); p.standardOutput = sink; p.standardError = sink
        try? p.run(); p.waitUntilExit()
    }
}
