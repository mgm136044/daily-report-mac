import Foundation

/// The completed-days ledger. Kept as a plain JSON object (entries are
/// heterogeneous) and written atomically so a crash cannot corrupt it. A
/// corrupt read returns empty — the caller regenerates rather than trusting junk.
public enum Ledger {
    public static func url(stateDir: String) -> String { stateDir + "/lastrun.json" }

    public static func read(_ url: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ["completed": [String: Any]()] }
        if obj["completed"] is [String: Any] { return obj }
        var fixed = obj; fixed["completed"] = [String: Any](); return fixed
    }

    public static func completedDates(_ state: [String: Any]) -> Set<String> {
        guard let completed = state["completed"] as? [String: Any] else { return [] }
        return Set(completed.keys)
    }

    public static func record(_ state: [String: Any], date: String,
                              entry: [String: Any]) -> [String: Any] {
        var state = state
        var completed = state["completed"] as? [String: Any] ?? [:]
        completed[date] = entry
        state["completed"] = completed
        return state
    }

    /// Write via temp + fsync + rename so a crash mid-write cannot corrupt it.
    public static func write(_ state: [String: Any], to url: String) throws {
        let data = try JSONSerialization.data(withJSONObject: state,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let temp = url + ".tmp"
        let fm = FileManager.default
        fm.createFile(atPath: temp, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: temp))
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        // POSIX rename atomically replaces the destination (matches os.replace),
        // so a crash never leaves a half-written ledger.
        guard rename(temp, url) == 0 else {
            try? fm.removeItem(atPath: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url)
    }
}
