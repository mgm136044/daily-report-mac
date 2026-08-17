import Foundation

/// The captured header of one rollout thread.
public struct CodexMeta {
    public var cwd: String
    public var branch: String?
    public var rolloutId: String?
    public var isSubagent: Bool
    public init(cwd: String, branch: String?, rolloutId: String?, isSubagent: Bool) {
        self.cwd = cwd; self.branch = branch; self.rolloutId = rolloutId; self.isSubagent = isSubagent
    }
}

/// Collect one logical day from Codex CLI rollout logs. Faithful port of
/// `collect_codex.py`.
public struct CodexCollector {
    static let outcomeMaxChars = 400
    private let config: DayConfig
    private let fm: FileManager

    public init(config: DayConfig, fileManager: FileManager = .default) {
        self.config = config; self.fm = fileManager
    }

    public func collect(date: String) -> CodexCollection {
        let root = (config.sources.codexSessionsDir as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return CodexCollection(projects: [:], stats: CodexStats(
                rolloutsTotal: 0, rolloutsScanned: 0, recordsInDay: 0, available: false))
        }
        guard let window = LogicalDate.dayWindow(date, config: config) else {
            return CodexCollection(projects: [:], stats: CodexStats(
                rolloutsTotal: 0, rolloutsScanned: 0, recordsInDay: 0, available: true))
        }
        let promptCap = config.noise.promptMaxChars

        var buckets: [String: CodexBucket] = [:]
        var filesSeen = 0, filesScanned = 0, recordsInDay = 0

        let enumerator = fm.enumerator(at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            filesSeen += 1
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let mtime, mtime < window.start { continue }
            filesScanned += 1

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var meta = CodexMeta(cwd: "", branch: nil, rolloutId: nil, isSubagent: false)
            var haveCwd = false
            var pending: [(Date, [String: Any])] = []

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let record = LenientJSON.object(line) as? [String: Any],
                      let payload = record["payload"] as? [String: Any] else { continue }

                if record["type"] as? String == "session_meta" {
                    if let source = payload["source"] as? [String: Any], source["subagent"] != nil {
                        meta.isSubagent = true
                    }
                    if haveCwd { continue }          // first meta defines the thread
                    meta.cwd = DayConfig.nfc(payload["cwd"] as? String ?? "")
                    haveCwd = true
                    meta.branch = (payload["git"] as? [String: Any])?["branch"] as? String
                    meta.rolloutId = (payload["id"] as? String) ?? (payload["session_id"] as? String)
                    continue
                }

                guard let stamp = LogicalDate.parseISO(record["timestamp"] as? String),
                      stamp >= window.start, stamp < window.end else { continue }
                recordsInDay += 1
                pending.append((stamp, payload))
            }

            if pending.isEmpty || meta.cwd.isEmpty || config.isExcluded(meta.cwd) { continue }
            let bucket = buckets[meta.cwd] ?? CodexBucket()
            buckets[meta.cwd] = bucket
            Self.absorb(bucket: bucket, meta: meta, pending: pending, promptCap: promptCap)
        }

        var projects: [String: CodexProject] = [:]
        for (cwd, bucket) in buckets { projects[cwd] = bucket.finalize(promptCap: promptCap) }
        return CodexCollection(projects: projects, stats: CodexStats(
            rolloutsTotal: filesSeen, rolloutsScanned: filesScanned,
            recordsInDay: recordsInDay, available: true))
    }

    /// Route in-window records into the bucket. Static + pure over its inputs.
    public static func absorb(bucket b: CodexBucket, meta: CodexMeta,
                              pending: [(Date, [String: Any])], promptCap: Int) {
        if let id = meta.rolloutId, !id.isEmpty { b.sessions.insert(id) }
        if let br = meta.branch, !br.isEmpty { b.branches.insert(br) }
        if meta.isSubagent { b.subagentThreads += 1 }

        for (stamp, payload) in pending {
            if b.firstTS == nil || stamp < b.firstTS! { b.firstTS = stamp }
            if b.lastTS == nil || stamp > b.lastTS! { b.lastTS = stamp }

            switch payload["type"] as? String {
            case "user_message" where !meta.isSubagent:
                let text = payload["message"] as? String ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    b.prompts.append(text.count > promptCap
                        ? String(text.prefix(promptCap)) + CodexBucket.truncationMark : text)
                }
            case "patch_apply_end":
                if payload["success"] as? Bool == false { continue }
                for (path, change) in (payload["changes"] as? [String: Any] ?? [:]) {
                    let kind = (change as? [String: Any])?["type"] as? String ?? "update"
                    switch kind {
                    case "add": b.filesAdded.insert(DayConfig.nfc(path))
                    case "delete": b.filesDeleted.insert(DayConfig.nfc(path))
                    default: b.filesUpdated.insert(DayConfig.nfc(path))
                    }
                }
            case "custom_tool_call", "function_call":
                b.plans += CodexExtract.extractPlanSteps(payload)
                b.commands += CodexExtract.extractCommands(payload)
            case "task_complete":
                let message = payload["last_agent_message"] as? String ?? ""
                if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    b.outcomes.append((LogicalDate.isoString(stamp, config: .defaultConfig),
                                       String(message.prefix(outcomeMaxChars))))
                }
            default:
                break
            }
        }
    }
}
