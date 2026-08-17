import Foundation

/// Collect one logical day's work signal from Claude Code session logs. A port
/// of the Python `collect.py:collect_sessions`, split into a pure record→bucket
/// absorber (testable without the filesystem) and a file walk (in this file too).
public struct ClaudeSessionCollector {
    public static let fileTools: Set<String> = ["Write", "NotebookEdit"]
    public static let editTools: Set<String> = ["Edit"]
    public static let truncationMark = " …[truncated]"

    let config: DayConfig
    let fm: FileManager
    public init(config: DayConfig, fileManager: FileManager = .default) {
        self.config = config; self.fm = fileManager
    }

    public final class Bucket {
        var sessions = Set<String>(), branches = Set<String>(), slugs = Set<String>()
        var skills = Set<String>(), writes = Set<String>(), edits = Set<String>()
        var tracked = Set<String>()
        var prompts: [String] = [], bash: [String] = [], todos: [String] = []
        var firstTS: Date?, lastTS: Date?
        public init() {}
    }

    private func cut(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + Self.truncationMark
    }

    /// record.timestamp, else record.snapshot.timestamp.
    public func recordTimestamp(_ record: [String: Any]) -> Date? {
        if let ts = LogicalDate.parseISO(record["timestamp"] as? String) { return ts }
        let snap = record["snapshot"] as? [String: Any]
        return LogicalDate.parseISO(snap?["timestamp"] as? String)
    }

    private func bucket(_ key: String, _ buckets: inout [String: Bucket]) -> Bucket {
        if let b = buckets[key] { return b }
        let b = Bucket(); buckets[key] = b; return b
    }

    /// Walk every *.jsonl transcript, keeping only records inside the logical day.
    public func collect(date: String) -> SessionCollection {
        guard let window = LogicalDate.dayWindow(date, config: config) else {
            return SessionCollection(projects: [:], stats: SessionStats())
        }
        let root = (config.sources.claudeProjectsDir as NSString).expandingTildeInPath
        var buckets: [String: Bucket] = [:]
        var total = 0, scanned = 0, inDay = 0

        let rootURL = URL(fileURLWithPath: root)
        let walker = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            total += 1
            // cheap pre-filter: a file last modified before the day started
            // cannot contain records inside it.
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mtime, mtime < window.start { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                // LenientJSON tolerates the bare NaN/Infinity tokens some records
                // carry, which JSONSerialization would reject (same gap fixed for
                // Codex in Plan 5).
                guard let record = LenientJSON.object(line) as? [String: Any] else { continue }
                guard let stamp = recordTimestamp(record),
                      stamp >= window.start, stamp < window.end else { continue }
                inDay += 1
                absorb(record, stamp: stamp, into: &buckets)
            }
        }
        return SessionCollection(
            projects: Self.finalize(buckets),
            stats: SessionStats(transcriptsTotal: total, transcriptsScanned: scanned, recordsInDay: inDay))
    }

    /// Route one in-window record. Caller has already checked the timestamp.
    public func absorb(_ record: [String: Any], stamp: Date, into buckets: inout [String: Bucket]) {
        // file-history-delta carries no cwd; its backup dir is absolute.
        if (record["type"] as? String) == "file-history-delta" {
            let backup = record["backup"] as? [String: Any] ?? [:]
            let parent = DayConfig.nfc(backup["realParentDir"] as? String ?? "")
            let name = DayConfig.nfc(((record["trackingPath"] as? String ?? "") as NSString).lastPathComponent)
            if !parent.isEmpty, !name.isEmpty, !config.isExcluded(parent) {
                bucket(parent, &buckets).tracked.insert((parent as NSString).appendingPathComponent(name))
            }
            return
        }

        let cwd = DayConfig.nfc(record["cwd"] as? String ?? "")
        if cwd.isEmpty || config.isExcluded(cwd) { return }
        let b = bucket(cwd, &buckets)

        if b.firstTS == nil || stamp < b.firstTS! { b.firstTS = stamp }
        if b.lastTS == nil || stamp > b.lastTS! { b.lastTS = stamp }
        if let s = record["sessionId"] as? String { b.sessions.insert(s) }
        if let br = record["gitBranch"] as? String { b.branches.insert(br) }
        if let sl = record["slug"] as? String { b.slugs.insert(sl) }

        guard let message = record["message"] as? [String: Any] else { return }
        let role = message["role"] as? String
        let content = message["content"]
        if role == "user", let text = content as? String {
            b.prompts.append(cut(text, config.noise.promptMaxChars)); return
        }
        guard let blocks = content as? [[String: Any]] else { return }
        for block in blocks {
            let kind = block["type"] as? String
            if kind == "text", role == "user" {
                b.prompts.append(cut(block["text"] as? String ?? "", config.noise.promptMaxChars))
            } else if kind == "tool_use" {
                absorbToolUse(b, block)
            }
        }
    }

    private func absorbToolUse(_ b: Bucket, _ block: [String: Any]) {
        let name = block["name"] as? String
        let input = block["input"] as? [String: Any] ?? [:]
        if let name, Self.fileTools.contains(name), let fp = input["file_path"] as? String {
            b.writes.insert(DayConfig.nfc(fp))
        } else if let name, Self.editTools.contains(name), let fp = input["file_path"] as? String {
            b.edits.insert(DayConfig.nfc(fp))
        } else if name == "Bash", let cmd = input["command"] as? String {
            b.bash.append(cmd)
        } else if name == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
            for item in todos { if let c = item["content"] as? String { b.todos.append(c) } }
        } else if name == "Skill", let skill = input["skill"] as? String {
            b.skills.insert(skill)
        }
    }

    /// Sessions whose cwd carries no project meaning, grouped by a fixed label
    /// (Claude local agent mode). A faithful port of `collect_labeled_sessions`.
    public func collectLabeled(date: String) -> [String: SessionProject] {
        guard let window = LogicalDate.dayWindow(date, config: config) else { return [:] }
        let promptCap = config.noise.promptMaxChars
        var buckets: [String: Bucket] = [:]

        for entry in config.sources.extraSessionGlobs where !entry.glob.isEmpty && !entry.label.isEmpty {
            let pattern = (entry.glob as NSString).expandingTildeInPath
            let b = bucket(entry.label, &buckets)
            for path in Self.globJSONL(pattern, fileManager: fm) {
                guard let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      mtime >= window.start,
                      let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let record = LenientJSON.object(line) as? [String: Any],
                          // labeled records key off record.timestamp only (no snapshot fallback)
                          let stamp = LogicalDate.parseISO(record["timestamp"] as? String),
                          stamp >= window.start, stamp < window.end else { continue }
                    if b.firstTS == nil || stamp < b.firstTS! { b.firstTS = stamp }
                    if b.lastTS == nil || stamp > b.lastTS! { b.lastTS = stamp }
                    if let sid = record["sessionId"] as? String, !sid.isEmpty { b.sessions.insert(sid) }
                    guard let message = record["message"] as? [String: Any] else { continue }
                    let role = message["role"] as? String
                    let content = message["content"]
                    if role == "user", let text = content as? String {
                        b.prompts.append(cut(text, promptCap))
                    } else if let blocks = content as? [Any] {
                        for case let block as [String: Any] in blocks {
                            if block["type"] as? String == "text", role == "user" {
                                b.prompts.append(cut(block["text"] as? String ?? "", promptCap))
                            } else if block["type"] as? String == "tool_use" {
                                absorbToolUse(b, block)
                            }
                        }
                    }
                }
            }
        }

        // keep a label only if it has real activity
        return Self.finalize(buckets).filter { _, p in
            !(p.prompts.isEmpty && p.filesWritten.isEmpty && p.filesEdited.isEmpty && p.bashCommands.isEmpty)
        }
    }

    /// Expand a `glob(3)`-style pattern (with `**` and `*`) to matching file paths.
    /// Foundation has no glob, so walk the fixed prefix and match each path against
    /// a regex compiled from the pattern.
    static func globJSONL(_ pattern: String, fileManager fm: FileManager) -> [String] {
        // base = directory prefix before the first wildcard
        let firstStar = pattern.firstIndex(of: "*") ?? pattern.endIndex
        let head = pattern[..<firstStar]
        let base = head.lastIndex(of: "/").map { String(head[..<$0]) } ?? ""
        let baseDir = base.isEmpty ? "/" : base

        var rx = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    rx += ".*"; i = pattern.index(after: next); continue
                }
                rx += "[^/]*"
            } else if "\\^$.|?+()[]{}".contains(c) {
                rx += "\\" + String(c)
            } else {
                rx += String(c)
            }
            i = pattern.index(after: i)
        }
        rx += "$"

        guard let regex = try? NSRegularExpression(pattern: rx),
              let en = fm.enumerator(atPath: baseDir) else { return [] }
        var out: [String] = []
        for case let rel as String in en {
            let full = baseDir + "/" + rel
            if regex.firstMatch(in: full, range: NSRange(full.startIndex..., in: full)) != nil {
                out.append(full)
            }
        }
        return out
    }

    public static func finalize(_ buckets: [String: Bucket]) -> [String: SessionProject] {
        var out: [String: SessionProject] = [:]
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        for (cwd, b) in buckets {
            out[cwd] = SessionProject(
                sessions: b.sessions.sorted(), branches: b.branches.sorted(),
                slugs: b.slugs.sorted(), skillsUsed: b.skills.sorted(),
                prompts: b.prompts, filesWritten: b.writes.sorted(),
                filesEdited: b.edits.sorted(), filesTracked: b.tracked.sorted(),
                bashCommands: b.bash, todos: b.todos,
                firstTS: b.firstTS.map { iso.string(from: $0) },
                lastTS: b.lastTS.map { iso.string(from: $0) })
        }
        return out
    }
}
