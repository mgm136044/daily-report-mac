import XCTest
@testable import DailyReportKit

final class NotionSchemaTests: XCTestCase {
    private func config(schema: String?, report: String) -> DayConfig {
        var c = DayConfig.defaultConfig
        c.notion.schemaLanguage = schema
        c.report.language = report
        return c
    }

    func test_korean_property_names_never_change() {
        let s = NotionSchema(config: config(schema: "ko", report: "ko"))
        XCTAssertEqual(s.dbTitle, "하루 마감 보고서")
        XCTAssertEqual(s.prop(.date), "날짜")
        XCTAssertEqual(s.prop(.summary), "요약")
        XCTAssertEqual(s.statusLabel(.done), "완료")
        XCTAssertEqual(s.weekday(0), "월")
    }

    func test_english_schema() {
        let s = NotionSchema(config: config(schema: "en", report: "en"))
        XCTAssertEqual(s.dbTitle, "Daily report")
        XCTAssertEqual(s.prop(.date), "Date")
    }

    func test_schema_language_is_pinned_separately_from_report_language() {
        // report switches to en but the schema stays ko because it is pinned.
        let s = NotionSchema(config: config(schema: "ko", report: "en"))
        XCTAssertEqual(s.language, "ko")
        XCTAssertEqual(s.prop(.date), "날짜")
    }

    func test_unpinned_schema_follows_report_then_defaults_korean() {
        XCTAssertEqual(NotionSchema(config: config(schema: nil, report: "en")).language, "en")
        XCTAssertEqual(NotionSchema(config: config(schema: nil, report: "zz")).language, "ko")
    }

    func test_properties_definition_has_all_eleven() {
        let s = NotionSchema(config: config(schema: "ko", report: "ko"))
        let def = s.propertiesDefinition()
        XCTAssertEqual(def.count, 11)
        XCTAssertNotNil(def["날짜"])
    }
}
