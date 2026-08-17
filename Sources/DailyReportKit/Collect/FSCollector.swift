import Foundation

/// Find files that changed on disk within the day window but left no trace in
/// either tool's log. Faithful port of `collect_fs.py`.
public struct FSCollector {
    static let gitTimeoutSec = 15
    static let maxFilesPerProject = 80

    static let noiseNames: Set<String> = [
        ".DS_Store", "package-lock.json", "uv.lock", "poetry.lock",
        "Thumbs.db", ".localized",
        ".env", ".envrc", ".netrc", ".npmrc", "credentials", "id_rsa", "id_ed25519",
    ]
    static let noiseSuffixes = [
        ".pyc", ".pyo", ".log", ".lock", ".tmp", ".swp", ".swo",
        ".pack", ".idx", ".part", ".crdownload",
    ]
    static let noiseDirParts = [
        "/.git/", "/node_modules/", "/__pycache__/", "/.venv/",
        "/.pytest_cache/", "/.ruff_cache/", "/.obsidian/",
        "/dist/", "/build/", "/.next/", "/.cache/",
        "/.claude/", "/.codex/", "/.agents/",
    ]

    private let config: DayConfig
    private let fm: FileManager
    let selfArtifactDirs: [String]

    /// `selfArtifactBase` is the app's data dir; work/state/logs under it are the
    /// tool's own output and must never be reported.
    public init(config: DayConfig, selfArtifactBase: String, fileManager: FileManager = .default) {
        self.config = config; self.fm = fileManager
        self.selfArtifactDirs = ["work", "state", "logs"].map { selfArtifactBase + "/" + $0 + "/" }
    }

    public func isNoise(_ path: String) -> Bool {
        if selfArtifactDirs.contains(where: { path.hasPrefix($0) }) { return true }
        // os.path.basename("/a/b/") == "" — a trailing slash means "no filename".
        let name = path.hasSuffix("/") ? "" : (path as NSString).lastPathComponent
        if Self.noiseNames.contains(name) { return true }
        if Self.noiseSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
        if name.hasPrefix(".env.") { return true }
        let probe = path.hasSuffix("/") ? path : path + "/"
        return Self.noiseDirParts.contains(where: { probe.contains($0) })
    }

    /// The nearest ancestor directory containing a `.git` entry (file or dir),
    /// or nil. `.git` as a file counts — submodules and worktrees use one.
    public func repoRoot(_ path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty && current != "/" {
            if fm.fileExists(atPath: current + "/.git") { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }

    /// stdout of `git <args>` in `repo` on exit 0, else nil (matching the Python
    /// `run` helper). Drains concurrently with a 15 s wall-clock timeout.
    private func runGit(_ args: [String], repo: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git", "-C", repo] + args
        proc.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe
        do { try proc.run() } catch { return nil }

        var outData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }
        drain.enter()
        DispatchQueue.global().async { _ = errPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { proc.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + .seconds(Self.gitTimeoutSec)) == .timedOut {
            proc.terminate(); _ = drain.wait(timeout: .now() + .seconds(2)); return nil
        }
        drain.wait()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: outData, encoding: .utf8)
    }

    /// (tracked, dirty) absolute paths. Only a tracked-and-clean file can be
    /// assumed git-moved; untracked/ignored files keep their mtime meaning, so
    /// tracked comes from `ls-files` (which `status --porcelain` alone omits).
    public func gitState(_ repo: String) -> (tracked: Set<String>, dirty: Set<String>) {
        var tracked = Set<String>()
        if let listing = runGit(["ls-files", "-z"], repo: repo) {
            for e in listing.split(separator: "\0", omittingEmptySubsequences: true) {
                tracked.insert(DayConfig.nfc(repo + "/" + e))
            }
        }
        var dirty = Set<String>()
        if let status = runGit(["status", "--porcelain", "-z"], repo: repo) {
            // -z emits "XY path\0"; a rename adds a bare "oldpath\0" right after.
            let fields = status.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
            var index = 0
            while index < fields.count {
                let entry = fields[index]
                if entry.count > 3 {
                    dirty.insert(DayConfig.nfc(repo + "/" + String(entry.dropFirst(3))))
                    if let first = entry.first, first == "R" || first == "C", index + 1 < fields.count {
                        dirty.insert(DayConfig.nfc(repo + "/" + fields[index + 1]))
                        index += 1
                    }
                }
                index += 1
            }
        }
        return (tracked, dirty)
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
    private func mtime(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Files changed inside the day window under each given project root.
    public func collect(date: String, roots: [String], committed: Set<String>) -> FSCollection {
        guard let window = LogicalDate.dayWindow(date, config: config) else {
            return FSCollection(roots: [:], stats: FSStats(rootsScanned: 0, files: 0, filesDroppedOverCap: 0))
        }
        var found: [String: [String]] = [:]
        var gitCache: [String: (tracked: Set<String>, dirty: Set<String>)] = [:]
        var scannedRoots = 0

        for root in roots {
            guard !root.isEmpty, !config.isWalkExcluded(root) else { continue }
            // First touch of a root is deadline-guarded: a folder blocked on a TCC
            // prompt is skipped instead of hanging the whole run (see RootAccess).
            guard RootAccess.reachable(root) else {
                FileHandle.standardError.write(Data("루트 건너뜀(접근 불가/권한 대기): \(root)\n".utf8)); continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            scannedRoots += 1

            var stack = [root]
            while let dir = stack.popLast() {
                if config.isWalkExcluded(dir) || isNoise(dir + "/") { continue }
                guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for name in names {
                    let full = dir + "/" + name
                    var entryIsDir: ObjCBool = false
                    guard fm.fileExists(atPath: full, isDirectory: &entryIsDir) else { continue }
                    if entryIsDir.boolValue {
                        if !isSymlink(full) { stack.append(full) }   // followlinks=False
                        continue
                    }
                    let path = DayConfig.nfc(full)
                    if isNoise(path) { continue }
                    guard let m = mtime(full), m >= window.start, m < window.end else { continue }
                    if let repo = repoRoot(path) {
                        if gitCache[repo] == nil { gitCache[repo] = gitState(repo) }
                        let (tracked, dirty) = gitCache[repo]!
                        let trackedAndClean = tracked.contains(path) && !dirty.contains(path)
                        if trackedAndClean && !committed.contains(path) { continue }
                    }
                    found[root, default: []].append(path)
                }
            }
        }

        var trimmed: [String: [String]] = [:]
        var dropped = 0
        for (root, paths) in found {
            var paths = paths
            if paths.count > Self.maxFilesPerProject {
                paths.sort { (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast) }  // newest first
                dropped += paths.count - Self.maxFilesPerProject
                paths = Array(paths.prefix(Self.maxFilesPerProject))
            }
            trimmed[root] = paths.sorted()
        }
        return FSCollection(roots: trimmed, stats: FSStats(
            rootsScanned: scannedRoots,
            files: trimmed.values.reduce(0) { $0 + $1.count },
            filesDroppedOverCap: dropped))
    }
}
