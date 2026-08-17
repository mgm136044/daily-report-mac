import Foundation

/// One commit authored by a configured identity inside the logical day.
/// `at` is the committer date because that is what `--since/--until` filter on.
public struct GitCommit: Equatable {
    public var repo: String
    public var project: String
    public var sha: String          // first 8 chars
    public var at: String           // committer date, ISO 8601
    public var authoredAt: String   // author date, ISO 8601
    public var author: String       // author email (%ae)
    public var subject: String
    public var files: Int
    public var insertions: Int
    public var deletions: Int
    public var paths: [String]

    public init(repo: String, project: String, sha: String, at: String,
                authoredAt: String, author: String, subject: String,
                files: Int, insertions: Int, deletions: Int, paths: [String]) {
        self.repo = repo; self.project = project; self.sha = sha; self.at = at
        self.authoredAt = authoredAt; self.author = author; self.subject = subject
        self.files = files; self.insertions = insertions; self.deletions = deletions
        self.paths = paths
    }
}

/// A repo whose `git log` could not be read (launch failure, timeout, non-zero exit).
public struct GitFailure: Equatable {
    public var repo: String
    public var reason: String
    public init(repo: String, reason: String) { self.repo = repo; self.reason = reason }
}

/// The result of a day's git sweep. `skipped` is set only when `git.authors`
/// is empty — that is a deliberate "collected nothing", not an error.
public struct GitCollection: Equatable {
    public var commits: [GitCommit]
    public var reposScanned: Int
    public var failures: [GitFailure]
    public var skipped: String?
    public init(commits: [GitCommit], reposScanned: Int,
                failures: [GitFailure], skipped: String?) {
        self.commits = commits; self.reposScanned = reposScanned
        self.failures = failures; self.skipped = skipped
    }
}
