import Foundation

/// One project's rolled-up day, ready for the summarizer.
public struct RefinedProject: Equatable {
    public var label: String
    public var root: String?
    public var tools: [String]
    public var sessionCount: Int
    public var branches: [String]
    public var titles: [String]
    public var skillsUsed: [String]
    public var prompts: [String]
    public var filesWritten: [String]
    public var filesEdited: [String]
    public var filesTracked: [String]
    public var filesOnDisk: [String]
    public var bashCommands: [String]
    public var todos: [String]
    public var plans: [String]
    public var outcomes: [String]
    public var commits: [GitCommit]
    public var activeFrom: String?
    public var activeTo: String?
}

public struct RefinedStats: Equatable {
    public var projects: Int
    public var sessions: Int
    public var files: Int
    public var commits: Int
    public var noiseCommandsDropped: Int
    public var cwdsDropped: Int
}

public struct RefinedDay: Equatable {
    public var date: String
    public var windowStart: String
    public var windowEnd: String
    public var projects: [RefinedProject]   // ordered busiest-first
    public var stats: RefinedStats
    public var droppedCwds: [String]
}
