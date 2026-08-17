import XCTest
@testable import DailyReportKit

final class LedgerViewTests: XCTestCase {
    private func ledger(_ completed: [String: [String: Any]]) -> [String: Any] { ["completed": completed] }

    func test_synced_entry_renders_as_synced_not_skipped() {
        // A date reconciled from Notion (report exists elsewhere) must count as done
        // (not pending) and be flagged synced — not shown as "설치 이전 날짜".
        let state = ledger(["2026-08-12": ["synced": "notion", "at": "t"]])
        let card = LedgerView.summary(state: state, today: "2026-08-13", limit: 10).cards[0]
        XCTAssertEqual(card.kind, .done)
        XCTAssertTrue(card.synced)
        XCTAssertNil(card.skippedReason)
    }

    func test_cards_are_most_recent_first_with_parsed_fields() {
        let state = ledger([
            "2026-08-11": ["at": "t1", "projects": 2, "sessions": 5, "files": 40, "commits": 3, "report_chars": 4200],
            "2026-08-10": ["at": "t0", "skipped": "활동 없음"],
        ])
        let s = LedgerView.summary(state: state, today: "2026-08-13", limit: 10)
        XCTAssertEqual(s.cards.map(\.date), ["2026-08-11", "2026-08-10"])   // desc
        XCTAssertEqual(s.cards[0].kind, .done)
        XCTAssertEqual(s.cards[0].projects, 2)
        XCTAssertEqual(s.cards[0].reportChars, 4200)
        XCTAssertEqual(s.cards[1].kind, .skipped)
        XCTAssertEqual(s.cards[1].skippedReason, "활동 없음")
    }

    func test_health_is_healthy_when_no_pending() {
        var completed: [String: [String: Any]] = [:]
        for off in 1...14 {
            let d = LedgerViewTests.addDays("2026-08-13", -off)
            completed[d] = ["at": "t", "projects": 1]
        }
        let s = LedgerView.summary(state: ["completed": completed], today: "2026-08-13", limit: 5)
        XCTAssertEqual(s.health, .healthy)
        XCTAssertEqual(s.pendingCount, 0)
        XCTAssertEqual(s.cards.count, 5)          // limited
    }

    func test_health_needs_attention_when_pending_exists() {
        let s = LedgerView.summary(state: ["completed": [String: Any]()], today: "2026-08-13", limit: 5)
        if case .needsAttention(let pending) = s.health { XCTAssertEqual(pending, 14) }
        else { XCTFail("expected needsAttention") }
    }

    static func addDays(_ date: String, _ offset: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let d = f.date(from: date)!
        return f.string(from: d.addingTimeInterval(Double(offset) * 86_400))
    }
}
