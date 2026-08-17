import Foundation

/// One cwd's worth of collected Claude session signal, finalized (sets sorted).
public struct SessionProject: Codable, Equatable {
    public var sessions: [String]
    public var branches: [String]
    public var slugs: [String]
    public var skillsUsed: [String]
    public var prompts: [String]
    public var filesWritten: [String]
    public var filesEdited: [String]
    public var filesTracked: [String]
    public var bashCommands: [String]
    public var todos: [String]
    public var firstTS: String?
    public var lastTS: String?

    public init(sessions: [String] = [], branches: [String] = [], slugs: [String] = [],
                skillsUsed: [String] = [], prompts: [String] = [], filesWritten: [String] = [],
                filesEdited: [String] = [], filesTracked: [String] = [], bashCommands: [String] = [],
                todos: [String] = [], firstTS: String? = nil, lastTS: String? = nil) {
        self.sessions = sessions; self.branches = branches; self.slugs = slugs
        self.skillsUsed = skillsUsed; self.prompts = prompts; self.filesWritten = filesWritten
        self.filesEdited = filesEdited; self.filesTracked = filesTracked
        self.bashCommands = bashCommands; self.todos = todos
        self.firstTS = firstTS; self.lastTS = lastTS
    }
}

public struct SessionStats: Codable, Equatable {
    public var transcriptsTotal: Int
    public var transcriptsScanned: Int
    public var recordsInDay: Int
    public init(transcriptsTotal: Int = 0, transcriptsScanned: Int = 0, recordsInDay: Int = 0) {
        self.transcriptsTotal = transcriptsTotal
        self.transcriptsScanned = transcriptsScanned
        self.recordsInDay = recordsInDay
    }
}

public struct SessionCollection {
    public var projects: [String: SessionProject]   // keyed by cwd
    public var stats: SessionStats
    public init(projects: [String: SessionProject], stats: SessionStats) {
        self.projects = projects; self.stats = stats
    }
}
