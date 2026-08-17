import Foundation

/// Discover git repositories and collect the day's commits by the configured
/// authors. A faithful port of the git functions in the Python `collect.py`.
public struct GitCollector {
    static let gitTimeoutSec = 20

    private let config: DayConfig
    private let fm: FileManager

    public init(config: DayConfig, fileManager: FileManager = .default) {
        self.config = config; self.fm = fileManager
    }

    /// Parse the `git log` stream.
    ///
    /// `at` is the committer date because that is what `--since/--until` filter
    /// on; the author date would put a rebased or amended commit on a day the
    /// window never selected.
    public static func parseGitLog(_ output: String, repo: String) -> [GitCommit] {
        let project = (repo as NSString).lastPathComponent
        var commits: [GitCommit] = []
        var current: GitCommit?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.contains("\u{1F}") {
                if let c = current { commits.append(c) }
                let parts = line.split(separator: "\u{1F}", maxSplits: 4,
                                       omittingEmptySubsequences: false).map(String.init)
                func field(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
                current = GitCommit(
                    repo: repo, project: project,
                    sha: String(field(0).prefix(8)),
                    at: field(1), authoredAt: field(2),
                    author: field(3), subject: field(4),
                    files: 0, insertions: 0, deletions: 0, paths: [])
                continue
            }
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard current != nil, !stripped.isEmpty else { continue }

            if stripped.contains("changed")
                && (stripped.contains("insertion") || stripped.contains("deletion")
                    || stripped.contains("file")) {
                for (marker, key) in [(" file", 0), ("insertion", 1), ("deletion", 2)] {
                    for part in stripped.split(separator: ",", omittingEmptySubsequences: false) {
                        guard part.contains(marker) else { continue }
                        let digits = part.filter { $0.isASCII && $0.isNumber }
                        guard let n = Int(digits) else { continue }
                        switch key {
                        case 0: current!.files = n
                        case 1: current!.insertions = n
                        default: current!.deletions = n
                        }
                    }
                }
            } else {
                current!.paths.append(DayConfig.nfc(repo + "/" + stripped))
            }
        }
        if let c = current { commits.append(c) }
        return commits
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
    private func normalize(_ path: String) -> String {
        (expand(path) as NSString).standardizingPath
    }
    private func isSymlink(_ path: String) -> Bool {
        (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Every git repository under `gitSearchRoot`, plus the explicitly named
    /// `extraRepoRoots`. `os.walk`-faithful: top-down, prunable, error-tolerant,
    /// symlinks are not descended, depth is the separator count below the root.
    public func findRepos() -> [String] {
        let root = expand(config.sources.gitSearchRoot)
        let maxDepth = config.sources.gitMaxDepth
        var repos: [String] = []

        var stack: [(dir: String, depth: Int)] = [(root, 0)]
        while let (dir, depth) = stack.popLast() {
            if config.isWalkExcluded(dir) { continue }
            if depth >= maxDepth { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }

            var hasGit = false
            var children: [String] = []
            for name in names {
                let full = dir + "/" + name
                guard isDirectory(full) else { continue }   // follows symlinks, like scandir
                if name == ".git" { hasGit = true; continue }
                if isSymlink(full) { continue }             // followlinks=False
                children.append(full)
            }
            if hasGit { repos.append(DayConfig.nfc(dir)) }
            for child in children { stack.append((child, depth + 1)) }
        }

        // Repositories inside a skipped tree have to be named explicitly. The
        // Python original compares the raw (non-NFC) path against the list, then
        // stores the NFC form — replicated here for byte-fidelity.
        for extra in config.sources.extraRepoRoots where !extra.isEmpty {
            let path = normalize(extra)
            // Named roots bypass walkExclude and may be foreign/protected paths that
            // block on a TCC prompt — guard the first access with a deadline.
            guard RootAccess.reachable(path) else {
                FileHandle.standardError.write(Data("추가 저장소 건너뜀(접근 불가/권한 대기): \(path)\n".utf8)); continue
            }
            if isDirectory(path + "/.git") && !repos.contains(path) {
                repos.append(DayConfig.nfc(path))
            }
        }
        return repos
    }

    private func isoWithZone(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = LogicalDate.timeZone(config)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private enum GitRun {
        case launchFailed(String)
        case timedOut
        case completed(status: Int32, stdout: String, stderr: String)
    }

    /// Run `git <args>` inside `repo` with a wall-clock timeout, draining stdout
    /// and stderr concurrently so a full pipe buffer cannot deadlock the wait.
    private func runGit(_ args: [String], repo: String) -> GitRun {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git", "-C", repo] + args
        proc.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe

        do { try proc.run() } catch { return .launchFailed("\(type(of: error))") }

        var outData = Data(), errData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave()
        }
        drain.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave()
        }

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { proc.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + .seconds(Self.gitTimeoutSec)) == .timedOut {
            proc.terminate()
            _ = drain.wait(timeout: .now() + .seconds(2))
            return .timedOut
        }
        drain.wait()
        return .completed(status: proc.terminationStatus,
                          stdout: String(data: outData, encoding: .utf8) ?? "",
                          stderr: String(data: errData, encoding: .utf8) ?? "")
    }

    /// Commits authored by the configured identities inside the logical day.
    ///
    /// Author filtering is mandatory: an empty list means "none", not "everyone".
    /// Without `--author` flags git returns every commit in the tree, so a fresh
    /// install would pull hundreds of upstream commits out of vendored forks.
    public func collectGit(date: String) -> GitCollection {
        let authors = config.git.authors.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !authors.isEmpty else {
            return GitCollection(commits: [], reposScanned: 0, failures: [],
                skipped: "git.authors 가 비어 있어 커밋을 수집하지 않았습니다")
        }
        guard let window = LogicalDate.dayWindow(date, config: config) else {
            return GitCollection(commits: [], reposScanned: 0, failures: [], skipped: nil)
        }

        var logArgs = ["log", "--all",
                       "--since=\(isoWithZone(window.start))",
                       "--until=\(isoWithZone(window.end))"]
        for author in authors { logArgs += ["--author", author] }
        // NOTE: git treats diff-format flags as "last one wins", so the trailing
        // --name-only overrides --shortstat and git emits no "N files changed"
        // summary — files/insertions/deletions therefore stay 0. Kept verbatim to
        // match the Python original (its _parse_git_log yields the same 0/0/0 on
        // real output); the parser still handles a summary line if one ever appears.
        logArgs += ["--pretty=format:%H\u{1F}%cI\u{1F}%aI\u{1F}%ae\u{1F}%s",
                    "--shortstat", "--name-only"]

        let repos = findRepos()
        var commits: [GitCommit] = []
        var failures: [GitFailure] = []
        for repo in repos {
            switch runGit(logArgs, repo: repo) {
            case .launchFailed(let name):
                failures.append(GitFailure(repo: repo, reason: name))
            case .timedOut:
                failures.append(GitFailure(repo: repo, reason: "TimeoutExpired"))
            case .completed(let status, let stdout, let stderr):
                // A non-zero exit is indistinguishable from "no commits" if only
                // stdout is read — dubious ownership, a stale index.lock, or a
                // denied path all look like a quiet day otherwise.
                if status != 0 {
                    let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason = trimmed.isEmpty ? "exit \(status)" : String(trimmed.prefix(120))
                    failures.append(GitFailure(repo: repo, reason: reason))
                } else {
                    commits += Self.parseGitLog(stdout, repo: repo)
                }
            }
        }
        return GitCollection(commits: commits, reposScanned: repos.count,
                             failures: failures, skipped: nil)
    }
}
