import XCTest
@testable import DailyReportKit

final class DayCollectorTests: XCTestCase {
    private var home = ""
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("day-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: home) }

    func test_throws_when_no_transcripts_exist() {
        var c = DayConfig.defaultConfig
        c.sources.claudeProjectsDir = home + "/empty-claude"   // does not exist → 0 transcripts
        c.sources.codexSessionsDir = home + "/empty-codex"
        let collector = DayCollector(config: c, selfArtifactBase: home + "/app")
        XCTAssertThrowsError(try collector.collect(date: "2026-08-12"))
    }

    func test_end_to_end_rolls_a_session_into_a_project() throws {
        // one Claude transcript for a project under a container, in window
        let container = home + "/work"
        let projCwd = container + "/proj"
        try fm.createDirectory(atPath: projCwd, withIntermediateDirectories: true)
        let claudeDir = home + "/claude/-work-proj"
        try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let rec = #"{"timestamp":"2026-08-12T10:00:00.000Z","sessionId":"s1","cwd":"\#(projCwd)","message":{"role":"user","content":"do the work"}}"#
        fm.createFile(atPath: claudeDir + "/t.jsonl", contents: Data((rec + "\n").utf8))

        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.claudeProjectsDir = home + "/claude"
        c.sources.codexSessionsDir = home + "/nocodex"
        c.projects.containers = [container]
        c.git.authors = []                                    // no git scan

        let out = try DayCollector(config: c, selfArtifactBase: home + "/app").collect(date: "2026-08-12")
        XCTAssertEqual(out.projects.map(\.label), ["proj"])
        XCTAssertEqual(out.projects[0].prompts, ["do the work"])
    }
}
