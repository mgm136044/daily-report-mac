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

            // fenced code block
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }  // consume closing fence
                out.append("<pre><code>" + Self.escape(code.joined(separator: "\n")) + "</code></pre>")
                continue
            }
            // blockquote
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    quote.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                out.append("<blockquote>" + Self.inline(quote.joined(separator: " ")) + "</blockquote>")
                continue
            }
            // list (indent-based nesting)
            if Self.listMarker(trimmed) != nil {
                let (listHTML, next) = Self.parseList(lines, from: i, minIndent: Self.indent(line))
                out.append(listHTML); i = next; continue
            }

            // paragraph: gather consecutive non-blank, non-block lines
            var para: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l == "---" || Self.heading(l) != nil
                    || Self.listMarker(l) != nil || l.hasPrefix(">") || l.hasPrefix("```") { break }
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
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    /// Returns "ul"/"ol" if the trimmed line starts a list item, else nil.
    static func listMarker(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("- ") { return "ul" }
        if let dot = trimmed.firstIndex(of: "."),
           trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
           trimmed.index(after: dot) < trimmed.endIndex, trimmed[trimmed.index(after: dot)] == " " {
            return "ol"
        }
        return nil
    }

    static func itemText(_ trimmed: String) -> String {
        if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        let dot = trimmed.firstIndex(of: ".")!
        return String(trimmed[trimmed.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Parse a list starting at `from`, consuming items at >= minIndent. Deeper-indented
    /// items recurse into a nested list appended inside the current <li>.
    static func parseList(_ lines: [String], from: Int, minIndent: Int) -> (String, Int) {
        let tag = listMarker(lines[from].trimmingCharacters(in: .whitespaces))!
        var items: [String] = []
        var i = from
        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard listMarker(trimmed) != nil, indent(raw) >= minIndent else { break }
            var li = inline(itemText(trimmed))
            i += 1
            // nested list: following lines indented deeper
            if i < lines.count, listMarker(lines[i].trimmingCharacters(in: .whitespaces)) != nil,
               indent(lines[i]) > indent(raw) {
                let (nested, next) = parseList(lines, from: i, minIndent: indent(lines[i]))
                li += nested; i = next
            }
            items.append("<li>" + li + "</li>")
        }
        return (#"<"# + tag + #" class="body">"# + items.joined() + "</" + tag + ">", i)
    }
}
