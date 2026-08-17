import Foundation

/// One project's Codex activity for a logical day.
public struct CodexProject: Equatable {
    public var sessions: [String]
    public var branches: [String]
    public var prompts: [String]
    public var bashCommands: [String]
    public var filesAdded: [String]
    public var filesUpdated: [String]
    public var filesDeleted: [String]
    public var plans: [String]
    public var outcomes: [String]
    public var subagentThreads: Int
    public var firstTS: String?
    public var lastTS: String?
    public init(sessions: [String], branches: [String], prompts: [String],
                bashCommands: [String], filesAdded: [String], filesUpdated: [String],
                filesDeleted: [String], plans: [String], outcomes: [String],
                subagentThreads: Int, firstTS: String?, lastTS: String?) {
        self.sessions = sessions; self.branches = branches; self.prompts = prompts
        self.bashCommands = bashCommands; self.filesAdded = filesAdded
        self.filesUpdated = filesUpdated; self.filesDeleted = filesDeleted
        self.plans = plans; self.outcomes = outcomes
        self.subagentThreads = subagentThreads; self.firstTS = firstTS; self.lastTS = lastTS
    }
}

public struct CodexStats: Equatable {
    public var rolloutsTotal: Int
    public var rolloutsScanned: Int
    public var recordsInDay: Int
    public var available: Bool
    public init(rolloutsTotal: Int, rolloutsScanned: Int, recordsInDay: Int, available: Bool) {
        self.rolloutsTotal = rolloutsTotal; self.rolloutsScanned = rolloutsScanned
        self.recordsInDay = recordsInDay; self.available = available
    }
}

public struct CodexCollection: Equatable {
    public var projects: [String: CodexProject]
    public var stats: CodexStats
    public init(projects: [String: CodexProject], stats: CodexStats) {
        self.projects = projects; self.stats = stats
    }
}

/// Mutable per-cwd accumulator. Sets dedupe; arrays preserve encounter order.
public final class CodexBucket {
    var sessions = Set<String>()
    var branches = Set<String>()
    var prompts: [String] = []
    var commands: [String] = []
    var filesAdded = Set<String>()
    var filesUpdated = Set<String>()
    var filesDeleted = Set<String>()
    var plans: [String] = []
    var outcomes: [(stamp: String, message: String)] = []
    var subagentThreads = 0
    var firstTS: Date?
    var lastTS: Date?

    static let outcomesKept = 12
    static let commandMaxChars = 300
    static let truncationMark = " …[truncated]"

    public init() {}

    /// Freeze into the immutable output shape: sets sorted, commands capped,
    /// outcomes sorted by time and last-N kept, timestamps ISO-8601.
    public func finalize(promptCap: Int) -> CodexProject {
        let cappedCommands = commands.map { c -> String in
            c.count > Self.commandMaxChars
                ? String(c.prefix(Self.commandMaxChars)) + Self.truncationMark : c
        }
        let keptOutcomes = outcomes.sorted { $0.stamp < $1.stamp }
            .suffix(Self.outcomesKept).map(\.message)
        return CodexProject(
            sessions: sessions.sorted(),
            branches: branches.filter { !$0.isEmpty }.sorted(),
            prompts: prompts,
            bashCommands: cappedCommands,
            filesAdded: filesAdded.sorted(),
            filesUpdated: filesUpdated.sorted(),
            filesDeleted: filesDeleted.sorted(),
            plans: plans,
            outcomes: keptOutcomes,
            subagentThreads: subagentThreads,
            firstTS: firstTS.map { LogicalDate.isoString($0) },
            lastTS: lastTS.map { LogicalDate.isoString($0) })
    }
}
