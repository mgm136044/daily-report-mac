import Foundation

/// Roll a working directory up to the project it belongs to. The session log
/// records `cwd` per record, often a deep subdirectory; naming a day's work
/// after that leaf is meaningless, so each cwd walks up to the nearest
/// project-root marker. A faithful port of the Python `project_roots.py`.
public struct ProjectRoots {
    public static let rootMarkers = [
        ".git", "pyproject.toml", "package.json", "Cargo.toml", "go.mod",
        "CONTEXT.md", "CLAUDE.md", ".venv",
    ]

    private let config: DayConfig
    private let fm: FileManager

    public init(config: DayConfig, fileManager: FileManager = .default) {
        self.config = config; self.fm = fileManager
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
    private func normalize(_ path: String) -> String {
        // Collapse ".."/"." and trailing slashes, matching os.path.normpath closely.
        (expand(path) as NSString).standardizingPath
    }
    private func dirs(_ values: [String]) -> Set<String> {
        Set(values.map { normalize($0) })
    }
    private var containers: Set<String> { dirs(config.projects.containers) }
    private var never: Set<String> {
        dirs(config.projects.never).union([normalize("~"), "/"])
    }

    private var home: String { DayConfig.nfc(normalize("~")) }

    /// Return the project root for cwd, or nil if it should be dropped.
    public func projectRoot(_ cwd: String) -> String? {
        guard !cwd.isEmpty, cwd.hasPrefix("/"), !config.isExcluded(cwd) else { return nil }
        let containers = self.containers, never = self.never
        let home = self.home
        var current = DayConfig.nfc(normalize(cwd))
        while !current.isEmpty && current != "/" {
            // The home dir is a valid FALLBACK root (labeled "홈"), not a hard drop —
            // the Claude desktop app runs Claude Code from home by default, and those
            // sessions would otherwise vanish from the report. A real marker found on
            // the way up still wins (checked each level below); home only catches the
            // markerless remainder. Note home is also in `never`, so this must come first.
            if current == home { return home }
            if never.contains(current) { return nil }
            let hasMarker = Self.rootMarkers.contains {
                fm.fileExists(atPath: (current as NSString).appendingPathComponent($0))
            }
            if hasMarker { return current }
            // A container is never itself the answer — checked before the parent
            // rule, else ~/Downloads returns itself because its parent (~) is a
            // container.
            if containers.contains(current) { return nil }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            // a direct child of a container is a project even without a marker
            if containers.contains(parent) { return current }
            current = parent
        }
        return nil
    }

    /// Human-facing project name for a cwd, or nil to drop it.
    public func projectLabel(_ cwd: String) -> String? {
        guard let root = projectRoot(cwd) else { return nil }
        if root == home { return "홈" }               // app default cwd → a real, labeled bucket
        guard !never.contains(root) else { return nil }
        let base = DayConfig.nfc((root as NSString).lastPathComponent)
        return config.displayLabel(base)
    }
}
