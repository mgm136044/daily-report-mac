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
            out.append(#"<p class="body">"# + para.joined(separator: " ") + "</p>")
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
        switch level {
        case 1, 2: return #"<h2 class="sec">"# + text + "</h2>"   // H1 demoted to h2.sec
        case 3:    return #"<h3 class="proj">"# + text + "</h3>"
        default:   return "<h4>" + text + "</h4>"
        }
    }
}
