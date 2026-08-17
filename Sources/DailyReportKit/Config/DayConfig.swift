import Foundation

public struct DaySettings: Codable, Equatable {
    public var boundaryHour: Int
    public var timezoneOffsetHours: Int?
}
public struct GitSettings: Codable, Equatable { public var authors: [String] }
public struct ExcludeSettings: Codable, Equatable { public var paths: [String] }
public struct SessionGlob: Codable, Equatable {
    public var glob: String
    public var label: String
    public init(glob: String, label: String) { self.glob = glob; self.label = label }
}
public struct SourceSettings: Codable, Equatable {
    public var walkExclude: [String]
    public var claudeProjectsDir: String
    public var codexSessionsDir: String
    public var gitSearchRoot: String
    public var gitMaxDepth: Int
    public var extraRepoRoots: [String]
    public var extraSessionGlobs: [SessionGlob]
}
public struct ProjectSettings: Codable, Equatable {
    public var containers: [String]
    public var never: [String]
}
public struct LabelSettings: Codable, Equatable { public var rename: [String: String] }
public struct ReportSettings: Codable, Equatable {
    public var language: String
    public var targetChars: Int
}
public struct NotionSettings: Codable, Equatable {
    public var schemaLanguage: String?
    public var databaseId: String?
    public var parentPageURL: String?
}
public struct NoiseSettings: Codable, Equatable {
    public var promptMaxChars: Int
    public var bashCommandPrefixes: [String]
    public var dedupePrefixChars: Int
    public var commandMaxChars: Int
}
public struct SummarySettings: Codable, Equatable {
    public var modelTimeoutSec: Int
    public var maxTurns: Int
    /// "claude" (default) or "codex". Optional so pre-existing config.json (which
    /// lacks the key) still decodes — otherwise the whole config falls back to
    /// defaults, silently discarding the user's saved token/DB settings. nil = claude.
    public var engine: String?
    public init(modelTimeoutSec: Int, maxTurns: Int, engine: String? = "claude") {
        self.modelTimeoutSec = modelTimeoutSec; self.maxTurns = maxTurns; self.engine = engine
    }
}
public struct RunSettings: Codable, Equatable {
    public var watchdogSec: Int
    /// Chosen daily-run clock time. Optional for backward compatibility with
    /// config.json written before the schedule was user-configurable; nil → 04:05.
    public var scheduleHour: Int?
    public var scheduleMinute: Int?
    public init(watchdogSec: Int, scheduleHour: Int? = 4, scheduleMinute: Int? = 5) {
        self.watchdogSec = watchdogSec
        self.scheduleHour = scheduleHour; self.scheduleMinute = scheduleMinute
    }
}

public struct DayConfig: Codable, Equatable {
    public var day: DaySettings
    public var git: GitSettings
    public var exclude: ExcludeSettings
    public var sources: SourceSettings
    public var projects: ProjectSettings
    public var labels: LabelSettings
    public var report: ReportSettings
    public var notion: NotionSettings
    public var noise: NoiseSettings
    public var summary: SummarySettings
    public var run: RunSettings

    public static let defaultConfig = DayConfig(
        day: DaySettings(boundaryHour: 4, timezoneOffsetHours: nil),
        git: GitSettings(authors: []),
        exclude: ExcludeSettings(paths: ["/node_modules/", "/.git/", "/.build/"]),
        sources: SourceSettings(
            walkExclude: [
                "/Library/Mobile Documents/", "/Documents/", "/Desktop/",
                "/Downloads/", "/Pictures/", "/Movies/", "/Music/",
                "/Applications/", "/.Trash/",
            ],
            claudeProjectsDir: "~/.claude/projects",
            codexSessionsDir: "~/.codex/sessions",
            gitSearchRoot: "~",
            gitMaxDepth: 6,
            extraRepoRoots: [],
            extraSessionGlobs: []),
        projects: ProjectSettings(containers: ["~/Downloads", "~/Desktop"], never: []),
        labels: LabelSettings(rename: [:]),
        report: ReportSettings(language: "ko", targetChars: 5000),
        notion: NotionSettings(schemaLanguage: nil, databaseId: nil, parentPageURL: nil),
        noise: NoiseSettings(
            promptMaxChars: 1400,
            bashCommandPrefixes: [
                "ls", "ll", "cd", "pwd", "cat", "head", "tail", "echo", "which", "wc",
                "find", "grep", "rg", "du", "df", "open", "file", "stat", "date",
                "tree", "source", "export", "sed -n", "printf", "basename", "dirname",
            ],
            dedupePrefixChars: 60, commandMaxChars: 400),
        summary: SummarySettings(modelTimeoutSec: 900, maxTurns: 1),
        run: RunSettings(watchdogSec: 2400))
}

public enum ConfigStore {
    public static func url(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DailyReport", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func load(from url: URL) -> (config: DayConfig, usingDefaults: Bool) {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(DayConfig.self, from: data) else {
            return (.defaultConfig, true)
        }
        return (config, false)
    }

    public static func save(_ config: DayConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
