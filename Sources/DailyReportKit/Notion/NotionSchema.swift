import Foundation

public struct NotionSchema {
    public enum PropKey: CaseIterable {
        case title, date, summary, projects, tags, sessions, commits, files
        case status, createdAt, source
    }

    public let language: String
    private let table: LangTable

    private static let supported = ["ko", "en"]
    public static let statusColors: [DayStatus: String] =
        [.done: "green", .draft: "yellow", .failed: "red"]

    public init(config: DayConfig) {
        if let pinned = config.notion.schemaLanguage, Self.supported.contains(pinned) {
            language = pinned
        } else if Self.supported.contains(config.report.language) {
            language = config.report.language
        } else {
            language = "ko"
        }
        table = language == "en" ? .english : .korean
    }

    public var dbTitle: String { table.dbTitle }
    public func weekday(_ index: Int) -> String { table.weekdays[index] }
    public func prop(_ key: PropKey) -> String { table.props[key]! }
    public func statusLabel(_ status: DayStatus) -> String { table.status[status]! }

    /// The `properties` payload for creating the database. Empty JSON objects and
    /// arrays are given explicit element types so the literals type-check in an
    /// `Any` context.
    public func propertiesDefinition() -> [String: Any] {
        let emptyObject: [String: String] = [:]
        let emptyOptions: [String: [Any]] = ["options": []]
        let statusOptions: [[String: String]] = DayStatus.allCases.map { s in
            ["name": statusLabel(s), "color": Self.statusColors[s]!]
        }
        return [
            prop(.title): ["title": emptyObject],
            prop(.date): ["date": emptyObject],
            prop(.summary): ["rich_text": emptyObject],
            prop(.projects): ["multi_select": emptyOptions],
            prop(.tags): ["multi_select": emptyOptions],
            prop(.sessions): ["number": ["format": "number"]],
            prop(.commits): ["number": ["format": "number"]],
            prop(.files): ["number": ["format": "number"]],
            prop(.status): ["select": ["options": statusOptions]],
            prop(.createdAt): ["date": emptyObject],
            prop(.source): ["rich_text": emptyObject],
        ]
    }
}

private struct LangTable {
    let dbTitle: String
    let weekdays: [String]
    let props: [NotionSchema.PropKey: String]
    let status: [DayStatus: String]

    static let korean = LangTable(
        dbTitle: "하루 마감 보고서",
        weekdays: ["월", "화", "수", "목", "금", "토", "일"],
        props: [.title: "이름", .date: "날짜", .summary: "요약", .projects: "프로젝트",
                .tags: "태그", .sessions: "세션 수", .commits: "커밋 수",
                .files: "생성 파일 수", .status: "상태", .createdAt: "생성 시각",
                .source: "원본"],
        status: [.done: "완료", .draft: "초안", .failed: "실패"])

    static let english = LangTable(
        dbTitle: "Daily report",
        weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        props: [.title: "Name", .date: "Date", .summary: "Summary", .projects: "Projects",
                .tags: "Tags", .sessions: "Sessions", .commits: "Commits",
                .files: "Files", .status: "Status", .createdAt: "Created",
                .source: "Source"],
        status: [.done: "Done", .draft: "Draft", .failed: "Failed"])
}
