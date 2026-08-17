import Foundation

public enum DayStatus: String, Codable, Equatable, CaseIterable {
    case done, draft, failed
}

/// The data a finished day carries into the Notion sink. Producers (collection,
/// refinement, summarization — later plans) build this; NotionClient consumes it.
public struct DayDigest: Codable, Equatable {
    public var date: String        // "YYYY-MM-DD"
    public var markdown: String    // page body
    public var summary: String     // short prose for the Summary property
    public var projects: [String]
    public var tags: [String]
    public var sessions: Int
    public var commits: Int
    public var files: Int
    public var status: DayStatus
    public var source: String

    public init(date: String, markdown: String, summary: String,
                projects: [String], tags: [String], sessions: Int,
                commits: Int, files: Int, status: DayStatus, source: String) {
        self.date = date; self.markdown = markdown; self.summary = summary
        self.projects = projects; self.tags = tags; self.sessions = sessions
        self.commits = commits; self.files = files; self.status = status
        self.source = source
    }
}
