import Foundation

extension DayConfig {
    /// Substring match against the configured exclude fragments. A trailing
    /// slash is added first so a fragment like "/secret/" also matches a path
    /// whose last component is "secret".
    public func isExcluded(_ path: String) -> Bool {
        let probe = path.hasSuffix("/") ? path : path + "/"
        return exclude.paths.contains { probe.contains($0) }
    }

    /// Extra exclusions that apply only to filesystem traversal. Under launchd a
    /// background process cannot answer a TCC prompt, so opening a protected or
    /// cloud-backed directory can block forever instead of failing.
    ///
    /// Exception: a path inside a user-named `extraRepoRoots` entry is a deliberate
    /// whitelist — it (and its subtree) stays scannable even under an excluded folder
    /// like ~/Downloads. Hard excludes (node_modules, .git, .build) still win.
    public func isWalkExcluded(_ path: String) -> Bool {
        if isExcluded(path) { return true }
        if isUnderExtraRepoRoot(path) { return false }
        let probe = path.hasSuffix("/") ? path : path + "/"
        return sources.walkExclude.contains { probe.contains($0) }
    }

    /// True if `path` equals or is nested under any configured `extraRepoRoots` entry.
    private func isUnderExtraRepoRoot(_ path: String) -> Bool {
        let p = DayConfig.nfc((path as NSString).standardizingPath)
        for entry in sources.extraRepoRoots where !entry.isEmpty {
            let root = DayConfig.nfc(((entry as NSString).expandingTildeInPath as NSString).standardizingPath)
            if p == root || p.hasPrefix(root + "/") { return true }
        }
        return false
    }

    /// Human-facing name for a project folder; unrenamed folders pass through.
    public func displayLabel(_ name: String) -> String {
        labels.rename[name] ?? name
    }

    /// macOS returns Korean path components decomposed (NFD) from the
    /// filesystem, while session records carry them composed (NFC). Normalize so
    /// the same folder does not split into two projects that never merge.
    public static func nfc(_ path: String) -> String {
        path.isEmpty ? path : path.precomposedStringWithCanonicalMapping
    }
}
