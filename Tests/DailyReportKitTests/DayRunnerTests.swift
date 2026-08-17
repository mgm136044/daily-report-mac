import XCTest
@testable import DailyReportKit

final class DayRunnerTests: XCTestCase {
    private var home = ""
    private let fm = FileManager.default
    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("run-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(atPath: home) }

    private func config() -> DayConfig {
        var c = DayConfig.defaultConfig
        c.day.timezoneOffsetHours = 9
        c.sources.claudeProjectsDir = home + "/claude"
        c.sources.codexSessionsDir = home + "/nocodex"
        c.projects.containers = [home + "/work"]
        c.git.authors = []
        return c
    }

    func test_runOne_produces_digest_and_calls_notion_upsert() async throws {
        // one Claude transcript for a project in window
        let projCwd = home + "/work/proj"
        try fm.createDirectory(atPath: projCwd, withIntermediateDirectories: true)
        let claudeDir = home + "/claude/-work-proj"
        try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let rec = #"{"timestamp":"2026-08-12T10:00:00.000Z","sessionId":"s1","cwd":"\#(projCwd)","message":{"role":"user","content":"do work"}}"#
        fm.createFile(atPath: claudeDir + "/t.jsonl", contents: Data((rec + "\n").utf8))

        // mock claude → a valid report; mock notion → resolve, find (none), create
        let report = "# 2026-08-12 보고서\n\n" + String(repeating: "내용 ", count: 100)
        let claude = MockClaudeRunner(.completed(ClaudeResult(status: 0, stdout: report, stderr: "")))
        let transport = MockTransport()
        transport.enqueue(status: 200, json: ["data_sources": [["id": "ds"]]])
        transport.enqueue(status: 200, json: ["results": []])
        transport.enqueue(status: 200, json: ["id": "page-1", "url": "u"])
        let notion = NotionClient(token: "t", transport: transport, schema: NotionSchema(config: config()))

        let runner = DayRunner(config: config(), selfArtifactBase: home + "/app",
            stateDir: home + "/state", workDir: home + "/work-out",
            claudeRunner: claude, notionClient: notion, databaseId: "db-1", fileManager: fm)
        let result = try await runner.runOne(date: "2026-08-12")

        XCTAssertNil(result.skipped)
        XCTAssertEqual(result.projects, 1)
        XCTAssertGreaterThan(result.reportChars, 200)
        XCTAssertFalse(transport.sentRequests.isEmpty)          // Notion was called
        // the digest was written to the work dir
        XCTAssertTrue(fm.fileExists(atPath: home + "/work-out/digest_2026-08-12.json"))
    }

    func test_runOne_reports_each_stage_once_in_pipeline_order() async throws {
        let runner = try runnerWithOneDayOfActivity()
        var stages: [RunStage] = []
        _ = try await runner.runOne(date: "2026-08-12", onStage: { stages.append($0) })
        XCTAssertEqual(stages, [.collect, .sanitize, .summarize, .notion])
    }

    /// A runner whose collectors see exactly one project's activity and whose Claude
    /// and Notion are mocked, so runOne walks the full collect→sanitize→summarize→notion
    /// pipeline (the path that emits every stage).
    private func runnerWithOneDayOfActivity() throws -> DayRunner {
        let projCwd = home + "/work/proj"
        try fm.createDirectory(atPath: projCwd, withIntermediateDirectories: true)
        let claudeDir = home + "/claude/-work-proj"
        try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let rec = #"{"timestamp":"2026-08-12T10:00:00.000Z","sessionId":"s1","cwd":"\#(projCwd)","message":{"role":"user","content":"do work"}}"#
        fm.createFile(atPath: claudeDir + "/t.jsonl", contents: Data((rec + "\n").utf8))

        let report = "# 2026-08-12 보고서\n\n" + String(repeating: "내용 ", count: 100)
        let claude = MockClaudeRunner(.completed(ClaudeResult(status: 0, stdout: report, stderr: "")))
        let transport = MockTransport()
        transport.enqueue(status: 200, json: ["data_sources": [["id": "ds"]]])
        transport.enqueue(status: 200, json: ["results": []])
        transport.enqueue(status: 200, json: ["id": "page-1", "url": "u"])
        let notion = NotionClient(token: "t", transport: transport, schema: NotionSchema(config: config()))

        return DayRunner(config: config(), selfArtifactBase: home + "/app",
            stateDir: home + "/state", workDir: home + "/work-out",
            claudeRunner: claude, notionClient: notion, databaseId: "db-1", fileManager: fm)
    }
}
