import Foundation

/// Redact credentials before anything leaves this machine. A faithful port of
/// the Python `sanitize.py` — patterns, order, and masking must not drift.
/// Scanning 30 days of prompts once turned up three live Notion tokens in plain
/// text, so a missed pattern is a leak.
public enum Sanitizer {
    // Ordered most-specific first so a token matches its own rule, not a generic
    // one. `key_assignment` deliberately allows a prefix before the keyword —
    // an earlier `\b` anchor let OPENAI_API_KEY= and DB_PASSWORD= through.
    private static let rawPatterns: [(String, String)] = [
        ("anthropic_key", #"sk-ant-[A-Za-z0-9_\-]{10,}"#),
        ("notion_token", #"\b(?:ntn_[A-Za-z0-9]{20,}|secret_[A-Za-z0-9]{30,})"#),
        ("github_token", #"\bgh[pousr]_[A-Za-z0-9]{20,}"#),
        ("gitlab_token", #"\bglpat-[A-Za-z0-9_\-]{15,}"#),
        ("slack_token", #"\bxox[baprs]-[A-Za-z0-9\-]{10,}"#),
        ("google_api_key", #"\bAIza[0-9A-Za-z_\-]{35}"#),
        ("aws_access_key", #"\b(?:AKIA|ASIA)[0-9A-Z]{16}"#),
        ("stripe_key", #"\bsk_(?:live|test)_[A-Za-z0-9]{16,}"#),
        ("huggingface_token", #"\bhf_[A-Za-z0-9]{20,}"#),
        ("openai_project_key", #"\bsk-proj-[A-Za-z0-9_\-]{20,}"#),
        ("openai_key", #"\bsk-[A-Za-z0-9]{32,}"#),
        ("jwt", #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#),
        ("private_key_block", #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"#),
        ("ssh_key_body", #"\bb3BlbnNzaC1rZXktdjEA[A-Za-z0-9+/=]{20,}"#),
        ("connection_string",
         #"\b(?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis|amqp|ftp|ssh)://[^\s:/@]+:[^\s@/]+@"#),
        ("bearer_token", #"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}"#),
        ("krn_rrn", #"\b\d{6}-[1-4]\d{6}\b"#),
        ("krn_phone", #"\b01[016789]-\d{3,4}-\d{4}\b"#),
        ("key_assignment",
         #"(?i)(?:^|[^A-Za-z0-9_])([A-Za-z0-9_]*(?:API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?TOKEN|SECRET[_-]?KEY|CLIENT[_-]?SECRET|PRIVATE[_-]?KEY|PASSWORD|PASSWD|SECRET|TOKEN)[A-Za-z0-9_]*)\s*[=:]\s*["']?([^\s"'&;,)]{8,})"#),
        ("korean_secret",
         #"(?:비밀번호|패스워드|비번|암호)\s*(?:는|은|가|이|:|=)?\s*["']?((?=[^\s"']*[0-9!@#$%^&*])[^\s"']{6,})"#),
    ]

    public static let patterns: [(kind: String, regex: NSRegularExpression)] =
        rawPatterns.map { (kind, source) in
            // No global options: inline (?i) applies case-insensitivity exactly
            // where the Python pattern asks for it.
            (kind, try! NSRegularExpression(pattern: source))
        }

    /// Keep enough to recognise what was removed, not enough to use it. The
    /// separator is whichever of `=` or `:` comes first — preferring `=` leaked
    /// the head when the separator was `:` and the value contained an `=`.
    public static func mask(_ kind: String, _ matched: String) -> String {
        if kind == "key_assignment" || kind == "korean_secret" {
            let positions = [matched.firstIndex(of: "="), matched.firstIndex(of: ":")]
                .compactMap { $0 }
                .map { matched.distance(from: matched.startIndex, to: $0) }
            let name: String
            if let cut = positions.min() {
                name = String(matched.prefix(cut))
            } else {
                name = matched.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? matched
            }
            return "\(name.trimmingCharacters(in: .whitespaces))=<REDACTED>"
        }
        let head = String(matched.prefix(6))
        return "<REDACTED:\(kind):\(head)…len\(matched.count)>"
    }

    /// Apply every pattern in order over the whole text, replacing each match
    /// with its mask and counting findings by kind.
    public static func redact(_ text: String) -> (clean: String, findings: [String: Int]) {
        var findings: [String: Int] = [:]
        if text.isEmpty { return (text, findings) }
        var result = text
        for (kind, regex) in patterns {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }
            var rebuilt = ""
            var last = 0
            for m in matches {
                let r = m.range
                rebuilt += ns.substring(with: NSRange(location: last, length: r.location - last))
                rebuilt += mask(kind, ns.substring(with: r))
                findings[kind, default: 0] += 1
                last = r.location + r.length
            }
            rebuilt += ns.substring(from: last)
            result = rebuilt
        }
        return (result, findings)
    }
}

extension Sanitizer {
    static func merge(_ a: inout [String: Int], _ b: [String: Int]) {
        for (k, v) in b { a[k, default: 0] += v }
    }

    /// Walk a JSON-like structure, redacting every string in it — keys included.
    /// Project names are dict keys and become Notion properties, so a key left
    /// unredacted bypasses sanitizing entirely.
    public static func redactStructure(_ value: Any) -> (clean: Any, findings: [String: Int]) {
        if let s = value as? String {
            let (clean, found) = redact(s)
            return (clean, found)
        }
        if let array = value as? [Any] {
            var findings: [String: Int] = [:]
            var out: [Any] = []
            for item in array {
                let (clean, found) = redactStructure(item)
                out.append(clean); merge(&findings, found)
            }
            return (out, findings)
        }
        if let dict = value as? [String: Any] {
            var findings: [String: Int] = [:]
            var out: [String: Any] = [:]
            for (key, item) in dict {
                let (cleanKey, keyFound) = redact(key)
                let (clean, found) = redactStructure(item)
                out[cleanKey] = clean
                merge(&findings, keyFound); merge(&findings, found)
            }
            return (out, findings)
        }
        return (value, [:])
    }

    /// Human summary, counts descending. Ties broken by kind name for stability.
    public static func describe(_ findings: [String: Int]) -> String {
        if findings.isEmpty { return "탐지 0건" }
        let ordered = findings.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return ordered.map { "\($0.key) \($0.value)건" }.joined(separator: ", ")
    }
}
