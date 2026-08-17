import Foundation

/// Pure extraction of shell commands and plan steps from Codex's JS tool
/// wrapper. A faithful port of the scanning functions in `collect_codex.py`.
public enum CodexExtract {
    static let maxLiteralChars = 4000
    static let toolNameKeys: Set<String> = ["exec", "exec_command", "shell"]

    /// Read a quote-delimited literal, honoring backslash escapes. `rest` starts
    /// at the opening quote. Bounded so an unterminated quote cannot swallow a
    /// whole 30 KB block. Returns the content between the quotes, or nil.
    public static func scanQuoted(_ rest: Substring, quote: Character) -> String? {
        let chars = Array(rest)
        var end = 1
        while end < chars.count && end <= maxLiteralChars {
            if chars[end] == "\\" { end += 2; continue }
            if chars[end] == quote { return String(chars[1..<end]) }
            end += 1
        }
        return nil
    }

    /// Decode the string literal starting at `index`, if there is one. Handles
    /// backtick, single-, and double-quoted forms; double quotes are JSON-
    /// unescaped, falling back to a raw scan for escapes JSON rejects (e.g. \').
    public static func decodeStringAt(_ text: String, from index: String.Index) -> String? {
        let rest = text[index...].drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let first = rest.first else { return nil }
        if first == "`" { return scanQuoted(rest, quote: "`") }
        if first == "'" { return scanQuoted(rest, quote: "'") }
        if first == "\"" {
            if let decoded = jsonUnescapePrefix(rest) { return decoded }
            return scanQuoted(rest, quote: "\"")
        }
        return nil
    }

    /// Mirror `json.JSONDecoder().raw_decode` for a leading double-quoted string:
    /// find the literal's end with the same escape rules but NO length cap —
    /// unlike `scanQuoted`, which the backtick/single-quote paths use and which
    /// Python bounds at MAX_LITERAL_CHARS. Python's `"` path is `raw_decode`,
    /// which has no cap, so a >4000-char double-quoted command must still decode.
    /// nil if the content is not a valid JSON string; the caller then falls back
    /// to the bounded `scanQuoted`, matching Python's except-branch.
    private static func jsonUnescapePrefix(_ rest: Substring) -> String? {
        let chars = Array(rest)
        guard chars.first == "\"" else { return nil }
        var end = 1
        while end < chars.count {
            if chars[end] == "\\" { end += 2; continue }
            if chars[end] == "\"" {
                let wrapped = String(chars[0...end])     // the full "…" literal
                guard let data = wrapped.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                      let s = obj as? String else { return nil }
                return s
            }
            end += 1
        }
        return nil
    }

    private static let cmdKey = try! NSRegularExpression(pattern: #"["']?cmd["']?\s*:\s*"#)
    private static let planKey = try! NSRegularExpression(pattern: #"tools\.update_plan\s*\("#)
    private static let stepKey = try! NSRegularExpression(pattern: #"["']?step["']?\s*:\s*"#)

    /// The index just past each match of `re` in `text` (like Python `match.end()`).
    private static func matchEnds(_ re: NSRegularExpression, in text: String) -> [String.Index] {
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Range($0.range, in: text)?.upperBound
        }
    }

    /// `payload["input"] or payload["arguments"] or ""` with Python truthiness:
    /// falsy (nil / empty string / empty collection / zero) falls through.
    private static func rawInput(_ payload: [String: Any]) -> Any? {
        for key in ["input", "arguments"] {
            if let v = payload[key], truthy(v) { return v }
        }
        return nil
    }
    private static func truthy(_ v: Any) -> Bool {
        if v is NSNull { return false }
        if let s = v as? String { return !s.isEmpty }
        if let a = v as? [Any] { return !a.isEmpty }
        if let d = v as? [String: Any] { return !d.isEmpty }
        if let n = v as? NSNumber { return n != 0 }
        return true
    }
    private static func jsonEncode(_ v: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Pull the real shell commands out of Codex's JS tool wrapper.
    public static func extractCommands(_ payload: [String: Any]) -> [String] {
        guard let name = payload["name"] as? String, toolNameKeys.contains(name) else { return [] }
        let raw: String
        if let v = rawInput(payload) { raw = (v as? String) ?? jsonEncode(v) } else { raw = "" }
        var commands: [String] = []
        for end in matchEnds(cmdKey, in: raw) {
            if let value = decodeStringAt(raw, from: end) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { commands.append(trimmed) }
            }
        }
        return commands
    }

    /// Plan steps arrive two ways: a standalone `update_plan` function_call with
    /// JSON arguments, or an inline `tools.update_plan({plan:[{step:…}]})`.
    public static func extractPlanSteps(_ payload: [String: Any]) -> [String] {
        guard let rawAny = rawInput(payload), let raw = rawAny as? String else { return [] }
        if payload["name"] as? String == "update_plan",
           let data = raw.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data,
                       options: [.fragmentsAllowed])) as? [String: Any] {
            let plan = dict["plan"] as? [Any] ?? []
            return plan.compactMap { item in
                guard let d = item as? [String: Any],
                      let step = d["step"], !(step is NSNull) else { return nil }
                let s = String(describing: step).trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
        }
        let ns = raw as NSString
        guard planKey.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) != nil
        else { return [] }
        var steps: [String] = []
        for end in matchEnds(stepKey, in: raw) {
            if let value = decodeStringAt(raw, from: end) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { steps.append(trimmed) }
            }
        }
        return steps
    }
}
