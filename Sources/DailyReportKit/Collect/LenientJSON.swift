import Foundation

/// Parse one JSONL record the way Python's `json.loads` does.
///
/// Python accepts the bare `NaN`, `Infinity`, and `-Infinity` value tokens as a
/// non-standard extension; `JSONSerialization` rejects them and would drop the
/// whole record. Codex rollout logs contain such tokens in numeric fields the
/// report never reads, so a strict parser silently loses ~2% of real records.
///
/// The retry is recover-only: it runs solely after a strict parse fails, and
/// replaces only value-position non-finite tokens with `null`. A wrong
/// replacement just fails to re-parse and the record is skipped — the same
/// outcome as before — so it can never corrupt data.
public enum LenientJSON {
    private static let nonFinite = try! NSRegularExpression(
        pattern: #"(?<=[:\[,])(\s*)(-?Infinity|NaN)(?=\s*[,\]}])"#)

    public static func object(_ line: some StringProtocol) -> Any? {
        let s = String(line)
        guard let data = s.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) { return obj }
        let patched = nonFinite.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1null")
        guard patched != s, let patchedData = patched.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: patchedData)
    }
}
