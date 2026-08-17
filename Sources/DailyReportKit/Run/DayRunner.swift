import Foundation

public struct RunResult {
    public var date: String
    public var skipped: String?
    public var projects: Int
    public var sessions: Int
    public var files: Int
    public var commits: Int
    public var reportChars: Int
    public var digestFindings: [String: Int]
    public var reportFindings: [String: Int]
}

/// One day, end to end: collect → sanitize digest → summarize → sanitize report
/// → DayDigest → Notion upsert. A faithful port of `run_one`.
public struct DayRunner {
    private let config: DayConfig
    private let base: String
    private let stateDir: String
    private let workDir: String
    private let claudeRunner: ClaudeRunner
    private let notionClient: NotionClient
    private let databaseId: String
    private let fm: FileManager

    public init(config: DayConfig, selfArtifactBase: String, stateDir: String, workDir: String,
                claudeRunner: ClaudeRunner, notionClient: NotionClient, databaseId: String,
                fileManager: FileManager = .default) {
        self.config = config; self.base = selfArtifactBase; self.stateDir = stateDir
        self.workDir = workDir; self.claudeRunner = claudeRunner; self.notionClient = notionClient
        self.databaseId = databaseId; self.fm = fileManager
    }

    public func runOne(date: String) async throws -> RunResult {
        RunSupport.ensureDirs([stateDir, workDir])
        let refined = try DayCollector(config: config, selfArtifactBase: base, fileManager: fm)
            .collect(date: date)

        // sanitize BEFORE the model sees it
        let (cleanDigestAny, digestFindings) = Sanitizer.redactStructure(DigestJSON.object(refined))
        let cleanDigest = cleanDigestAny as? [String: Any] ?? [:]
        let digestPath = workDir + "/digest_\(date).json"
        if let data = try? JSONSerialization.data(withJSONObject: cleanDigest,
            options: [.prettyPrinted, .withoutEscapingSlashes]) {
            fm.createFile(atPath: digestPath, contents: data,
                          attributes: [.posixPermissions: 0o600])
        }

        if refined.projects.isEmpty {
            return RunResult(date: date, skipped: "활동 없음", projects: 0, sessions: 0,
                files: 0, commits: 0, reportChars: 0,
                digestFindings: digestFindings, reportFindings: [:])
        }

        let summarizer = Summarizer(config: config, runner: claudeRunner)
        let rawReport = try summarizer.summarize(digest: cleanDigest, date: date)
        // sanitize AFTER, in case the model echoed something
        let (report, reportFindings) = Sanitizer.redact(rawReport)
        fm.createFile(atPath: workDir + "/report_\(date).md", contents: Data((report + "\n").utf8),
                      attributes: [.posixPermissions: 0o600])

        let source = (digestPath as NSString).abbreviatingWithTildeInPath
        let digest = summarizer.buildDayDigest(refined: refined, report: report, source: source)
        _ = try await notionClient.upsert(databaseId: databaseId, digest: digest,
                                          config: config, now: Date())

        let s = refined.stats
        return RunResult(date: date, skipped: nil, projects: s.projects, sessions: s.sessions,
            files: s.files, commits: s.commits, reportChars: report.count,
            digestFindings: digestFindings, reportFindings: reportFindings)
    }
}
