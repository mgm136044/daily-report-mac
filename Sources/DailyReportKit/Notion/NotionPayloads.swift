import Foundation

public enum NotionPayloads {
    public static let summaryMaxChars = 2000
    public static let optionMaxChars = 100
    public static let multiSelectMax = 100

    /// Notion rejects commas and caps option names at 100 chars. An empty name
    /// is a 400, so callers must drop whatever comes back empty.
    public static func cleanOption(_ value: String) -> String {
        let collapsed = value.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
        return String(collapsed.prefix(optionMaxChars))
    }

    public static func options(_ values: [String]) -> [[String: Any]] {
        var seen = Set<String>(); var out: [[String: Any]] = []
        for value in values {
            let name = cleanOption(value)
            if name.isEmpty || seen.contains(name) { continue }
            seen.insert(name); out.append(["name": name])
            if out.count >= multiSelectMax { break }
        }
        return out
    }

    private static func richText(_ content: String) -> [[String: Any]] {
        [["type": "text", "text": ["content": content]]]
    }

    public static func buildProperties(_ digest: DayDigest, schema: NotionSchema,
                                       config: DayConfig, now: Date) -> [String: Any] {
        let weekdayIndex = mondayZeroWeekday(digest.date, config: config)
        let iso = ISO8601DateFormatter()
        iso.timeZone = LogicalDate.timeZone(config)
        iso.formatOptions = [.withInternetDateTime]
        return [
            schema.prop(.title): ["title": richText(
                "\(digest.date) (\(schema.weekday(weekdayIndex)))")],
            schema.prop(.date): ["date": ["start": digest.date]],
            schema.prop(.summary): ["rich_text": richText(
                String(digest.summary.prefix(summaryMaxChars)))],
            schema.prop(.projects): ["multi_select": options(digest.projects)],
            schema.prop(.tags): ["multi_select": options(digest.tags)],
            schema.prop(.sessions): ["number": digest.sessions],
            schema.prop(.commits): ["number": digest.commits],
            schema.prop(.files): ["number": digest.files],
            schema.prop(.status): ["select": ["name": schema.statusLabel(digest.status)]],
            schema.prop(.createdAt): ["date": ["start": iso.string(from: now)]],
            schema.prop(.source): ["rich_text": richText(digest.source)],
        ]
    }

    /// Monday=0 … Sunday=6, matching the Korean weekday table.
    static func mondayZeroWeekday(_ dateStr: String, config: DayConfig) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = LogicalDate.timeZone(config)
        let f = DateFormatter()
        f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        let date = f.date(from: dateStr) ?? Date()
        // Calendar weekday: Sunday=1 … Saturday=7. Convert to Monday=0.
        return (cal.component(.weekday, from: date) + 5) % 7
    }

    public static func markdownToBlocks(_ markdown: String) -> [[String: Any]] {
        func rich(_ text: String) -> [[String: Any]] {
            let chunks = stride(from: 0, to: max(text.count, 1), by: 2000).map { start -> String in
                let s = text.index(text.startIndex, offsetBy: start)
                let e = text.index(s, offsetBy: 2000, limitedBy: text.endIndex) ?? text.endIndex
                return String(text[s..<e])
            }
            return chunks.map { ["type": "text", "text": ["content": $0]] }
        }
        var blocks: [[String: Any]] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            let kind: String, content: String
            if text.hasPrefix("### ") { kind = "heading_3"; content = String(text.dropFirst(4)) }
            else if text.hasPrefix("## ") { kind = "heading_2"; content = String(text.dropFirst(3)) }
            else if text.hasPrefix("# ") { kind = "heading_1"; content = String(text.dropFirst(2)) }
            else if text.hasPrefix("- ") || text.hasPrefix("* ") {
                kind = "bulleted_list_item"; content = String(text.dropFirst(2)) }
            else { kind = "paragraph"; content = text }
            blocks.append(["object": "block", "type": kind, kind: ["rich_text": rich(content)]])
        }
        return blocks
    }
}
