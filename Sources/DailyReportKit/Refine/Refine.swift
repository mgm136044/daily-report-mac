import Foundation

/// Turn the collectors' typed outputs into a summarizer-ready `RefinedDay`.
/// A faithful port of `refine.py`.
public enum Refine {
    static let truncationMark = " …[truncated]"

    /// `^\s*(?:prefix|…)(?:\s|$)`, prefixes escaped and longest-first so a longer
    /// prefix wins over a shorter one it contains.
    private static func noiseMatcher(_ config: DayConfig) -> NSRegularExpression {
        let prefixes = config.noise.bashCommandPrefixes.sorted { $0.count > $1.count }
        let escaped = prefixes.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "^\\s*(?:\(escaped))(?:\\s|$)")
    }

    /// Remove navigation noise and near-duplicates. Returns (kept, dropped_count).
    public static func filterCommands(_ commands: [String], config: DayConfig) -> (kept: [String], dropped: Int) {
        let noise = noiseMatcher(config)
        let prefixLen = config.noise.dedupePrefixChars
        let cap = config.noise.commandMaxChars
        var kept: [String] = [], seen = Set<String>(), dropped = 0
        for command in commands {
            let collapsed = command.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if collapsed.isEmpty
                || noise.firstMatch(in: collapsed, range: NSRange(collapsed.startIndex..., in: collapsed)) != nil {
                dropped += 1; continue
            }
            let key = String(collapsed.prefix(prefixLen))
            if seen.contains(key) { dropped += 1; continue }
            seen.insert(key)
            kept.append(collapsed.count > cap ? String(collapsed.prefix(cap)) + truncationMark : collapsed)
        }
        return (kept, dropped)
    }

    /// Drop repeats, preserving order (Codex re-sends whole plans each turn).
    public static func dedupe(_ items: [String]) -> (kept: [String], dropped: Int) {
        var seen = Set<String>(), out: [String] = []
        for item in items {
            let key = String(item.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(120))
            if seen.contains(key) { continue }
            seen.insert(key); out.append(item)
        }
        return (out, items.count - out.count)
    }

    /// Render a UTC log timestamp in the reporting zone as "yyyy-MM-dd HH:mm".
    public static func localTime(_ iso: String?, config: DayConfig) -> String? {
        guard let date = LogicalDate.parseISO(iso) else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = LogicalDate.timeZone(config)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// min for first_ts, max for last_ts, over ISO strings.
    static func mergeTime(_ current: String?, _ value: String?, isFirst: Bool) -> String? {
        guard let value, !value.isEmpty else { return current }
        guard let current else { return value }
        return (isFirst ? value < current : value > current) ? value : current
    }

    private final class Bucket {
        var cwds = Set<String>(), sessions = Set<String>(), branches = Set<String>()
        var slugs = Set<String>(), skillsUsed = Set<String>(), tools = Set<String>()
        var codexSessions = Set<String>()
        var filesWritten = Set<String>(), filesEdited = Set<String>(), filesTracked = Set<String>()
        var filesOnDisk = Set<String>()
        var prompts: [String] = [], bashCommands: [String] = [], todos: [String] = []
        var plans: [String] = [], outcomes: [String] = [], commits: [GitCommit] = []
        var firstTS: String?, lastTS: String?
        func mergeTimes(_ first: String?, _ last: String?) {
            firstTS = Refine.mergeTime(firstTS, first, isFirst: true)
            lastTS = Refine.mergeTime(lastTS, last, isFirst: false)
        }
    }

    public static func refine(date: String, windowStart: String, windowEnd: String,
                              claude: [String: SessionProject], labeled: [String: SessionProject],
                              codex: [String: CodexProject], disk: [String: [String]],
                              git: GitCollection, config: DayConfig) -> RefinedDay {
        let roots = ProjectRoots(config: config)
        var merged: [String: Bucket] = [:]
        var order: [String] = []                     // first-seen label order for determinism
        var droppedCwds: [String] = []
        func bucket(_ label: String) -> Bucket {
            if let b = merged[label] { return b }
            let b = Bucket(); merged[label] = b; order.append(label); return b
        }

        for (cwd, d) in claude.sorted(by: { $0.key < $1.key }) {
            guard let label = roots.projectLabel(cwd) else { droppedCwds.append(cwd); continue }
            let b = bucket(label)
            b.cwds.insert(cwd); b.sessions.formUnion(d.sessions); b.branches.formUnion(d.branches)
            b.slugs.formUnion(d.slugs); b.skillsUsed.formUnion(d.skillsUsed); b.prompts += d.prompts
            b.filesWritten.formUnion(d.filesWritten); b.filesEdited.formUnion(d.filesEdited)
            b.filesTracked.formUnion(d.filesTracked); b.todos += d.todos; b.bashCommands += d.bashCommands
            b.tools.insert("Claude Code"); b.mergeTimes(d.firstTS, d.lastTS)
        }
        for (label, d) in labeled.sorted(by: { $0.key < $1.key }) {
            let b = bucket(label)
            b.sessions.formUnion(d.sessions); b.skillsUsed.formUnion(d.skillsUsed); b.prompts += d.prompts
            b.filesWritten.formUnion(d.filesWritten); b.filesEdited.formUnion(d.filesEdited)
            b.filesTracked.formUnion(d.filesTracked); b.bashCommands += d.bashCommands; b.todos += d.todos
            b.tools.insert("Claude Code"); b.mergeTimes(d.firstTS, d.lastTS)
        }
        for (cwd, d) in codex.sorted(by: { $0.key < $1.key }) {
            guard let label = roots.projectLabel(cwd) else { droppedCwds.append(cwd); continue }
            let b = bucket(label)
            b.cwds.insert(cwd); b.codexSessions.formUnion(d.sessions); b.branches.formUnion(d.branches)
            b.prompts += d.prompts; b.filesWritten.formUnion(d.filesAdded)
            b.filesEdited.formUnion(d.filesUpdated); b.filesTracked.formUnion(d.filesDeleted)
            b.bashCommands += d.bashCommands; b.plans += d.plans; b.outcomes += d.outcomes
            b.tools.insert("Codex"); b.mergeTimes(d.firstTS, d.lastTS)
        }
        for (root, paths) in disk.sorted(by: { $0.key < $1.key }) {
            guard let label = roots.projectLabel(root) else { continue }   // not a dropped cwd
            let b = bucket(label); b.cwds.insert(root); b.filesOnDisk.formUnion(paths)
        }
        for commit in git.commits {
            let label = roots.projectLabel(commit.repo) ?? commit.project
            bucket(label).commits.append(commit)
        }

        // Disk observations lose to tool records for the same file, day-wide.
        var toolRecorded = Set<String>()
        for b in merged.values {
            toolRecorded.formUnion(b.filesWritten)
            toolRecorded.formUnion(b.filesEdited)
            toolRecorded.formUnion(b.filesTracked)
        }

        var projects: [RefinedProject] = []
        var noiseDropped = 0
        for label in order {
            let b = merged[label]!
            let (commands, dropped) = filterCommands(b.bashCommands, config: config)
            noiseDropped += dropped
            let (plans, _) = dedupe(b.plans)
            projects.append(RefinedProject(
                label: label,
                root: b.cwds.isEmpty ? nil : roots.projectRoot(b.cwds.sorted()[0]),
                tools: b.tools.sorted(),
                sessionCount: b.sessions.count + b.codexSessions.count,
                branches: b.branches.sorted(), titles: b.slugs.sorted(), skillsUsed: b.skillsUsed.sorted(),
                prompts: b.prompts,
                filesWritten: b.filesWritten.sorted(), filesEdited: b.filesEdited.sorted(),
                filesTracked: b.filesTracked.sorted(),
                filesOnDisk: b.filesOnDisk.subtracting(toolRecorded).sorted(),
                bashCommands: commands, todos: b.todos, plans: plans, outcomes: b.outcomes,
                commits: b.commits,
                activeFrom: localTime(b.firstTS, config: config),
                activeTo: localTime(b.lastTS, config: config)))
        }

        // busiest first; ties keep first-seen order (Swift sort is stable)
        projects.sort { a, b in
            let ka = (a.prompts.count, a.filesWritten.count + a.filesEdited.count)
            let kb = (b.prompts.count, b.filesWritten.count + b.filesEdited.count)
            return ka.0 != kb.0 ? ka.0 > kb.0 : ka.1 > kb.1
        }

        var uniqueFiles = Set<String>()
        for p in projects {
            uniqueFiles.formUnion(p.filesWritten); uniqueFiles.formUnion(p.filesEdited)
            uniqueFiles.formUnion(p.filesTracked); uniqueFiles.formUnion(p.filesOnDisk)
        }
        return RefinedDay(date: date, windowStart: windowStart, windowEnd: windowEnd,
            projects: projects,
            stats: RefinedStats(
                projects: projects.count,
                sessions: projects.reduce(0) { $0 + $1.sessionCount },
                files: uniqueFiles.count,
                commits: projects.reduce(0) { $0 + $1.commits.count },
                noiseCommandsDropped: noiseDropped, cwdsDropped: droppedCwds.count),
            droppedCwds: droppedCwds)
    }
}
