import XCTest
@testable import DailyReportKit

/// The run pipeline emits one machine-readable progress line per stage; the app
/// parses those lines to drive the progress bar. These tests pin the wire format,
/// the parser, and the completed-work fraction the bar reads.
final class RunProgressTests: XCTestCase {

    // MARK: - Stage metadata

    func test_stages_are_the_four_pipeline_steps_in_order() {
        XCTAssertEqual(RunStage.allCases, [.collect, .sanitize, .summarize, .notion])
        XCTAssertEqual(RunStage.collect.order, 0)
        XCTAssertEqual(RunStage.summarize.order, 2)
    }

    func test_each_stage_has_a_korean_label() {
        XCTAssertEqual(RunStage.collect.label, "수집 중")
        XCTAssertEqual(RunStage.summarize.label, "요약 중")
        XCTAssertEqual(RunStage.notion.label, "노션 업로드 중")
    }

    // MARK: - Parser: what is and isn't a progress line

    func test_parser_ignores_ordinary_stdout_lines() {
        var p = RunProgressParser()
        XCTAssertNil(p.consume("밀린 날짜 2일: 2026-08-16, 2026-08-17"))
        XCTAssertNil(p.consume(""))
        XCTAssertNil(p.consume("완료 1일."))
    }

    func test_stage_line_before_a_total_is_ignored() {
        // Without a known total the denominator is unknown, so the bar can't move yet.
        var p = RunProgressParser()
        XCTAssertNil(p.consume(RunProgressWire.stage(index: 1, date: "2026-08-17", stage: .collect)))
    }

    // MARK: - Parser: the runner's own wire format round-trips

    func test_wire_stage_line_parses_back_to_its_fields() {
        var p = RunProgressParser()
        XCTAssertNil(p.consume(RunProgressWire.total(1)))   // priming line yields no update
        let update = p.consume(RunProgressWire.stage(index: 1, date: "2026-08-17", stage: .summarize))
        XCTAssertEqual(update?.stage, .summarize)
        XCTAssertEqual(update?.date, "2026-08-17")
        XCTAssertEqual(update?.dateIndex, 1)
        XCTAssertEqual(update?.totalDates, 1)
    }

    // MARK: - Fraction: reflects completed work before each stage begins

    func test_fraction_advances_stage_by_stage_within_one_day() {
        var p = RunProgressParser()
        _ = p.consume(RunProgressWire.total(1))
        XCTAssertEqual(p.consume(RunProgressWire.stage(index: 1, date: "d", stage: .collect))?.fraction, 0.0)
        XCTAssertEqual(p.consume(RunProgressWire.stage(index: 1, date: "d", stage: .sanitize))?.fraction, 0.25)
        XCTAssertEqual(p.consume(RunProgressWire.stage(index: 1, date: "d", stage: .summarize))?.fraction, 0.5)
        XCTAssertEqual(p.consume(RunProgressWire.stage(index: 1, date: "d", stage: .notion))?.fraction, 0.75)
    }

    func test_fraction_accounts_for_earlier_days_in_a_backfill() {
        // 2 days × 4 stages = 8 units; day 2's collect begins after day 1 is fully done → 4/8.
        var p = RunProgressParser()
        _ = p.consume(RunProgressWire.total(2))
        XCTAssertEqual(p.consume(RunProgressWire.stage(index: 2, date: "d2", stage: .collect))?.fraction, 0.5)
    }
}
