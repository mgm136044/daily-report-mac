import Foundation

/// Converts a daily-report Markdown body into HTML carrying the design system's
/// classes (see docs/design/pdf-report-design-system.md §8). Deliberately small:
/// it handles only the element set the reports use, not arbitrary Markdown. Pure.
public enum MarkdownToHTML {
    public static func convert(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" { out.append("<hr>"); i += 1; continue }
            if let (level, text) = Self.heading(trimmed) {
                out.append(Self.headingHTML(level: level, text: text)); i += 1; continue
            }
            if trimmed.isEmpty { i += 1; continue }

            // paragraph: gather consecutive non-blank, non-block lines
            var para: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l == "---" || Self.heading(l) != nil { break }
                para.append(l); i += 1
            }
            out.append(#"<p class="body">"# + Self.inline(para.joined(separator: " ")) + "</p>")
        }
        return out.joined(separator: "\n")
    }

    /// (level, text) for an ATX heading line, else nil.
    static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 { level += 1; idx = line.index(after: idx) }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        return (level, String(line[line.index(after: idx)...]))
    }

    static func headingHTML(level: Int, text: String) -> String {
        let html = Self.inline(text)
        switch level {
        case 1, 2: return #"<h2 class="sec">"# + html + "</h2>"   // H1 demoted to h2.sec
        case 3:    return #"<h3 class="proj">"# + html + "</h3>"
        default:   return "<h4>" + html + "</h4>"
        }
    }
}

extension MarkdownToHTML {
    /// Escape HTML, then apply inline Markdown (bold, code, link). Order matters:
    /// escape first so raw '<'/'&' can't inject markup; code spans are extracted
    /// before bold so `**` inside code stays literal.
    static func inline(_ text: String) -> String {
        var s = escape(text)
        // inline code: `...`  (before bold, so ** inside code is literal)
        s = replace(s, pattern: "`([^`]+)`") { "<code>\($0)</code>" }
        // bold: **...**
        s = replace(s, pattern: #"\*\*([^*]+)\*\*"#) { "<b>\($0)</b>" }
        // link: [text](url)  — url already escaped; & became &amp;
        s = replace(s, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, groups: 2) { m in
            #"<a href=""# + m[1] + #"">"# + m[0] + "</a>"
        }
        return s
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Single-capture regex replace.
    static func replace(_ s: String, pattern: String, _ body: (String) -> String) -> String {
        replace(s, pattern: pattern, groups: 1) { body($0[0]) }
    }

    /// Multi-capture regex replace: `body` receives capture groups [1...n] as [0...n-1].
    static func replace(_ s: String, pattern: String, groups: Int, _ body: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var caps: [String] = []
            for g in 1...groups { caps.append(ns.substring(with: m.range(at: g))) }
            result += body(caps)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
