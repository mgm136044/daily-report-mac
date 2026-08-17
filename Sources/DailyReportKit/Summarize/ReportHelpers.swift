import Foundation

public enum SummarizeError: Error, Equatable {
    case notAReport(String)
    case tooShort(String)
    case runFailed(String)
    case empty(String)
    case timedOut(String)
}

public enum ReportHelpers {
    static let minReportChars = 200
    public static let summarySentences = 3

    /// Drop any chatty lead-in before the first markdown heading.
    public static func stripPreamble(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            return lines[i...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Reject anything that is not actually a report.
    public static func validate(_ report: String) throws {
        if !report.components(separatedBy: "\n").contains(where: { $0.hasPrefix("# ") }) {
            throw SummarizeError.notAReport(String(report.prefix(200)))
        }
        if report.count < minReportChars {
            throw SummarizeError.tooShort(String(report.prefix(200)))
        }
    }

    /// First few sentences of the report's opening prose block.
    public static func firstSentences(_ markdown: String, count: Int = summarySentences) -> String {
        var prose: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            let markers = ["#", "-", "*", ">", "|", "`", "1."]
            let isProse = !text.isEmpty && !markers.contains(where: { text.hasPrefix($0) })
            if isProse { prose.append(text); continue }
            if !prose.isEmpty { break }
        }
        if prose.isEmpty { return "" }
        let joined = prose.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let sentences = splitSentences(joined)
        return sentences.prefix(count).joined(separator: " ")
    }

    /// Split on sentence-final punctuation followed by whitespace (Python
    /// `re.split(r"(?<=[.!?])\s+", …)`).
    private static func splitSentences(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+"#)
        let ns = text as NSString
        var parts: [String] = [], last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        return parts.filter { !$0.isEmpty }
    }

    /// Cheap deterministic tags from what the day contained.
    public static func deriveTags(_ refined: RefinedDay) -> [String] {
        let codeExt = [".py", ".js", ".ts", ".swift", ".sh"]
        var tags = Set<String>()
        for p in refined.projects {
            if !p.commits.isEmpty { tags.insert("커밋") }
            if p.skillsUsed.contains(where: { $0.hasPrefix("insane-research") }) { tags.insert("리서치") }
            let written = p.filesWritten + p.filesEdited
            if written.contains(where: { $0.hasSuffix(".md") }) { tags.insert("문서작성") }
            if written.contains(where: { f in codeExt.contains(where: { f.hasSuffix($0) }) }) { tags.insert("코드작성") }
            if written.contains(where: { $0.hasSuffix(".html") || $0.hasSuffix(".css") }) { tags.insert("디자인") }
        }
        return tags.sorted()
    }
}
