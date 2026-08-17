import Foundation

public enum CollectError: Error, Equatable { case noTranscripts(String) }

/// Orchestrate the day's collectors into one refined DayDigest. Faithful port of
/// the top-level `collect()` in `collect.py`.
public struct DayCollector {
    private let config: DayConfig
    private let selfArtifactBase: String
    private let fm: FileManager

    public init(config: DayConfig, selfArtifactBase: String, fileManager: FileManager = .default) {
        self.config = config; self.selfArtifactBase = selfArtifactBase; self.fm = fileManager
    }

    public func collect(date: String) throws -> RefinedDay {
        guard let window = LogicalDate.dayWindow(date, config: config) else {
            throw CollectError.noTranscripts("bad date: \(date)")
        }
        let claudeCollector = ClaudeSessionCollector(config: config, fileManager: fm)
        let sessions = claudeCollector.collect(date: date)
        let labeled = claudeCollector.collectLabeled(date: date)
        let codex = CodexCollector(config: config, fileManager: fm).collect(date: date)
        let git = GitCollector(config: config, fileManager: fm).collectGit(date: date)

        // Bound the fs sweep to project roots the day already touched.
        let roots = ProjectRoots(config: config, fileManager: fm)
        var rootSet = Set<String>(), committed = Set<String>()
        for cwd in Array(sessions.projects.keys) + Array(codex.projects.keys) {
            if let r = roots.projectRoot(cwd) { rootSet.insert(r) }
        }
        for commit in git.commits {
            rootSet.insert(commit.repo)
            committed.formUnion(commit.paths)
        }
        // Drop roots nested inside another root (avoid double-walking / double-count).
        let ordered = rootSet.sorted()
        let topLevel = ordered.filter { r in
            !ordered.contains { other in
                let prefix = other.hasSuffix("/") ? other : other + "/"
                return r != other && r.hasPrefix(prefix)
            }
        }
        let disk = FSCollector(config: config, selfArtifactBase: selfArtifactBase, fileManager: fm)
            .collect(date: date, roots: topLevel, committed: committed)

        guard sessions.stats.transcriptsTotal > 0 else {
            throw CollectError.noTranscripts(
                (config.sources.claudeProjectsDir as NSString).expandingTildeInPath)
        }

        return Refine.refine(
            date: date,
            windowStart: LogicalDate.isoString(window.start, config: config),
            windowEnd: LogicalDate.isoString(window.end, config: config),
            claude: sessions.projects, labeled: labeled, codex: codex.projects,
            disk: disk.roots, git: git, config: config)
    }
}
