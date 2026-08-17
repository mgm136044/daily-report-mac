import XCTest
@testable import DailyReportKit

final class NotionClientTests: XCTestCase {
    private func client(_ mock: MockTransport) -> NotionClient {
        NotionClient(token: "t", transport: mock,
                     schema: NotionSchema(config: .defaultConfig))
    }

    func test_http_error_carries_code_and_message() async {
        // The 400 reason (message) must survive to the UI/logs, not just the code —
        // that string is what disambiguates a Notion validation failure.
        let mock = MockTransport()
        mock.enqueue(status: 400, json: ["code": "validation_error",
                                         "message": "body failed validation: parent not found"])
        do {
            _ = try await client(mock).resolveDataSource(databaseId: "db-1")
            XCTFail("expected a throw")
        } catch let NotionError.http(status, code, message) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(code, "validation_error")
            XCTAssertEqual(message, "body failed validation: parent not found")
        } catch { XCTFail("wrong error: \(error)") }
    }

    // MARK: - findExistingDatabase (reuse an existing DB instead of duplicating it)

    func test_find_matches_child_database_by_title() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": [
            ["type": "child_database", "id": "db-1", "child_database": ["title": "하루 마감 보고서"]],
        ], "has_more": false])
        let id = try await client(mock).findExistingDatabase(parentId: "p")
        XCTAssertEqual(id, "db-1")
    }

    func test_find_follows_pagination() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": [
            ["type": "child_database", "id": "other", "child_database": ["title": "다른 DB"]],
        ], "has_more": true, "next_cursor": "c2"])
        mock.enqueue(status: 200, json: ["results": [
            ["type": "child_database", "id": "db-2", "child_database": ["title": "하루 마감 보고서"]],
        ], "has_more": false])
        let id = try await client(mock).findExistingDatabase(parentId: "p")
        XCTAssertEqual(id, "db-2")
        XCTAssertEqual(mock.sentRequests.count, 2)   // followed next_cursor
    }

    func test_find_fetches_title_when_block_title_empty() async throws {
        // A data-source-backed DB can report an EMPTY child_database.title here — the
        // root cause of the duplicate-DB bug. Fall back to GET /v1/databases/{id}.
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": [
            ["type": "child_database", "id": "db-3", "child_database": ["title": ""]],
        ], "has_more": false])
        mock.enqueue(status: 200, json: ["title": [["plain_text": "하루 마감 보고서"]]])
        let id = try await client(mock).findExistingDatabase(parentId: "p")
        XCTAssertEqual(id, "db-3")
    }

    func test_find_throws_on_non_200_instead_of_creating_a_duplicate() async {
        let mock = MockTransport()
        mock.enqueue(status: 403, json: ["code": "restricted_resource", "message": "no access"])
        do {
            _ = try await client(mock).findExistingDatabase(parentId: "p")
            XCTFail("expected a throw, not a silent nil (which would create a duplicate)")
        } catch let NotionError.http(status, _, _) {
            XCTAssertEqual(status, 403)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test_find_returns_nil_when_genuinely_absent() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": [], "has_more": false])
        let id = try await client(mock).findExistingDatabase(parentId: "p")
        XCTAssertNil(id)
    }

    // MARK: - existingReportDates (reconcile the ledger with what's already in Notion)

    private func datePage(_ date: String) -> [String: Any] {
        ["properties": ["날짜": ["date": ["start": date]]]]   // schema.prop(.date) == "날짜"
    }

    func test_existingReportDates_collects_dates_paginated() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": [["id": "ds-1"]]])   // resolveDataSource
        mock.enqueue(status: 200, json: ["results": [datePage("2026-08-11"), datePage("2026-08-12")],
                                         "has_more": true, "next_cursor": "c2"])
        mock.enqueue(status: 200, json: ["results": [datePage("2026-08-13T00:00:00.000+09:00")],
                                         "has_more": false])
        let dates = try await client(mock).existingReportDates(databaseId: "db-1")
        XCTAssertEqual(dates, ["2026-08-11", "2026-08-12", "2026-08-13"])   // time suffix trimmed to yyyy-MM-dd
    }

    func test_call_retries_transient_then_succeeds() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 502, json: ["code": "bad_gateway"])
        mock.enqueue(status: 200, json: ["ok": true])
        let (status, json) = try await client(mock).call("GET", "/v1/x", body: nil, retries: 5)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(mock.sentRequests.count, 2)   // retried once
    }

    func test_call_with_retries_one_does_not_retry() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 502, json: ["code": "bad_gateway"])
        let (status, _) = try await client(mock).call("POST", "/v1/pages", body: [:], retries: 1)
        XCTAssertEqual(status, 502)
        XCTAssertEqual(mock.sentRequests.count, 1)   // NOT retried
    }

    func test_resolve_data_source_picks_the_first() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": [["id": "ds-1"], ["id": "ds-2"]]])
        let id = try await client(mock).resolveDataSource(databaseId: "db")
        XCTAssertEqual(id, "ds-1")
    }

    func test_resolve_data_source_errors_when_none() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": []])
        await XCTAssertThrowsErrorAsync(try await self.client(mock).resolveDataSource(databaseId: "db"))
    }

    func test_find_by_date_returns_ids() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": [["id": "p1"], ["id": "p2"]]])
        let ids = try await client(mock).findByDate(dataSourceId: "ds", date: "2026-08-10")
        XCTAssertEqual(ids, ["p1", "p2"])
    }

    // MARK: DB creation (Task 9)

    func test_page_id_from_url_extracts_and_dashes() throws {
        let id = try NotionClient.pageId(
            fromURL: "https://www.notion.so/My-Page-0123456789abcdef0123456789abcdef?pvs=4")
        XCTAssertEqual(id, "01234567-89ab-cdef-0123-456789abcdef")
    }

    func test_page_id_from_url_rejects_garbage() {
        XCTAssertThrowsError(try NotionClient.pageId(fromURL: "https://notion.so/short"))
    }

    func test_ensure_database_reuses_existing() async throws {
        let mock = MockTransport()
        // children lookup returns a child_database titled like the schema
        mock.enqueue(status: 200, json: ["results": [[
            "id": "db-existing", "type": "child_database",
            "child_database": ["title": "하루 마감 보고서"]]]])
        let id = try await client(mock).ensureDatabase(
            parentURL: "https://notion.so/p-0123456789abcdef0123456789abcdef")
        XCTAssertEqual(id, "db-existing")
        XCTAssertEqual(mock.sentRequests.count, 1)   // no create call
    }

    func test_ensure_database_creates_when_absent() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["results": []])          // no existing child db
        mock.enqueue(status: 200, json: ["id": "db-new"])         // create response
        let id = try await client(mock).ensureDatabase(
            parentURL: "https://notion.so/p-0123456789abcdef0123456789abcdef")
        XCTAssertEqual(id, "db-new")
        XCTAssertEqual(mock.sentRequests.count, 2)
        XCTAssertEqual(mock.sentRequests[1].method, "POST")
    }

    // MARK: upsert (Task 11)

    private func digest() -> DayDigest {
        DayDigest(date: "2026-08-10", markdown: "# hi\n- a", summary: "s",
                  projects: ["app"], tags: [], sessions: 1, commits: 2, files: 3,
                  status: .done, source: "runner")
    }

    func test_upsert_creates_when_no_hits() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": [["id": "ds"]]])   // resolve
        mock.enqueue(status: 200, json: ["results": []])                    // find (none)
        mock.enqueue(status: 200, json: ["id": "new-page", "url": "u"])     // create (markdown)
        let id = try await client(mock).upsert(databaseId: "db", digest: digest(),
                                               config: .defaultConfig, now: Date())
        XCTAssertEqual(id, "new-page")
    }

    func test_upsert_updates_when_one_hit() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": [["id": "ds"]]])   // resolve
        mock.enqueue(status: 200, json: ["results": [["id": "old-page"]]])  // find (one)
        mock.enqueue(status: 200, json: [:])                               // update props
        mock.enqueue(status: 200, json: [:])                               // markdown replace
        let id = try await client(mock).upsert(databaseId: "db", digest: digest(),
                                               config: .defaultConfig, now: Date())
        XCTAssertEqual(id, "old-page")
    }

    func test_upsert_refuses_on_duplicate_rows() async {
        let mock = MockTransport()
        mock.enqueue(status: 200, json: ["data_sources": [["id": "ds"]]])
        mock.enqueue(status: 200, json: ["results": [["id": "a"], ["id": "b"]]])
        await XCTAssertThrowsErrorAsync(
            try await self.client(mock).upsert(databaseId: "db", digest: self.digest(),
                                               config: .defaultConfig, now: Date()))
    }

    func test_create_row_falls_back_to_blocks_when_markdown_rejected() async throws {
        let mock = MockTransport()
        mock.enqueue(status: 400, json: ["code": "validation_error"])   // markdown create fails
        mock.enqueue(status: 200, json: ["id": "p", "url": "u"])        // create w/o markdown
        mock.enqueue(status: 200, json: [:])                           // append blocks
        let (usedMarkdown, id, _) = try await client(mock).createRow(
            dataSourceId: "ds",
            props: NotionPayloads.buildProperties(digest(), schema: NotionSchema(config: .defaultConfig),
                                                  config: .defaultConfig, now: Date()),
            markdown: "# hi\n- a")
        XCTAssertFalse(usedMarkdown)
        XCTAssertEqual(id, "p")
    }
}

// Small async throwing assertion helper (XCTest lacks a built-in async variant).
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("expected error", file: file, line: line) }
    catch {}
}
