import Foundation

/// http(status, code, message): keep the Notion `message` too — the `code` alone
/// ("validation_error") rarely says WHAT failed; the message does.
public enum NotionError: Error, Equatable { case http(Int, String, String); case shape(String) }

public final class NotionClient {
    public static let apiBase = "https://api.notion.com"
    public static let version = "2026-03-11"
    static let transientCodes: Set<Int> = [429, 500, 502, 503, 529]
    static let backoffCapSec: UInt64 = 30

    private let token: String
    private let transport: HTTPTransport
    let schema: NotionSchema

    public init(token: String, transport: HTTPTransport, schema: NotionSchema) {
        self.token = token; self.transport = transport; self.schema = schema
    }

    /// Retries transient failures with exponential backoff. retries=1 disables
    /// retrying — page creation must use it (no idempotency key upstream).
    public func call(_ method: String, _ path: String, body: [String: Any]?,
                     retries: Int) async throws -> (status: Int, json: [String: Any]) {
        let tries = max(1, retries)
        let url = URL(string: Self.apiBase + path)!
        let headers = ["Authorization": "Bearer \(token)",
                       "Notion-Version": Self.version,
                       "Content-Type": "application/json"]
        let data = body.map { try! JSONSerialization.data(withJSONObject: $0) }
        var last: (Int, [String: Any]) = (-1, ["code": "exhausted_retries"])
        for attempt in 0..<tries {
            let resp = try await transport.send(method: method, url: url, headers: headers, body: data)
            let json = (try? JSONSerialization.jsonObject(with: resp.body)) as? [String: Any] ?? [:]
            if resp.status == 200 { return (200, json) }
            last = (resp.status, json)
            let transient = Self.transientCodes.contains(resp.status)
            if !transient || attempt == tries - 1 { return last }
            let delay = min(UInt64(1) << attempt, Self.backoffCapSec)
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
        }
        return last
    }

    public func resolveDataSource(databaseId: String) async throws -> String {
        let (status, data) = try await call("GET", "/v1/databases/\(databaseId)", body: nil, retries: 5)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
        guard let sources = data["data_sources"] as? [[String: Any]], !sources.isEmpty
        else { throw NotionError.shape("database has no data sources") }
        return str(sources[0]["id"])
    }

    public func findByDate(dataSourceId: String, date: String) async throws -> [String] {
        let body: [String: Any] = [
            "filter": ["property": schema.prop(.date), "date": ["equals": date]],
            "page_size": 5]
        let (status, data) = try await call("POST", "/v1/data_sources/\(dataSourceId)/query",
                                            body: body, retries: 5)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
        let results = data["results"] as? [[String: Any]] ?? []
        return results.map { str($0["id"]) }
    }

    /// Every logical date that already has a report row in the database — used to
    /// reconcile a fresh install's ledger with reports made before (or by another
    /// machine / the Python tool), so they aren't mislabeled "설치 이전 날짜".
    public func existingReportDates(databaseId: String) async throws -> Set<String> {
        let dataSourceId = try await resolveDataSource(databaseId: databaseId)
        let dateProp = schema.prop(.date)
        var dates: Set<String> = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let c = cursor { body["start_cursor"] = c }
            let (status, data) = try await call("POST", "/v1/data_sources/\(dataSourceId)/query",
                                                body: body, retries: 5)
            guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
            for page in (data["results"] as? [[String: Any]] ?? []) {
                let props = page["properties"] as? [String: Any] ?? [:]
                let dateVal = (props[dateProp] as? [String: Any])?["date"] as? [String: Any]
                if let start = dateVal?["start"] as? String { dates.insert(String(start.prefix(10))) }
            }
            cursor = (data["has_more"] as? Bool == true) ? (data["next_cursor"] as? String) : nil
        } while cursor != nil
        return dates
    }
}

func str(_ any: Any?) -> String { (any as? String) ?? "" }

// MARK: - Database creation (parent URL → data-source-backed database)

extension NotionClient {
    /// Extract the 32-hex page id from a Notion URL and dash-format it.
    public static func pageId(fromURL url: String) throws -> String {
        // Trim first: pasted links often carry a trailing newline/space. Doing it here
        // keeps the parser, SetupValidation, and "open page" all in agreement.
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let noQuery = trimmed.split(separator: "?").first.map(String.init) ?? trimmed
        let tail = noQuery.split(separator: "/").last.map(String.init) ?? noQuery
        let last = tail.split(separator: "-").last.map(String.init) ?? tail
        let raw = last.replacingOccurrences(of: "-", with: "")
        guard raw.count == 32 else { throw NotionError.shape("page id not found in url: \(url)") }
        let c = Array(raw)
        func slice(_ a: Int, _ b: Int) -> String { String(c[a..<b]) }
        return "\(slice(0,8))-\(slice(8,12))-\(slice(12,16))-\(slice(16,20))-\(slice(20,32))"
    }

    public func findExistingDatabase(parentId: String) async throws -> String? {
        var cursor: String?
        repeat {
            let page = cursor.map { "&start_cursor=\($0)" } ?? ""
            let (status, data) = try await call(
                "GET", "/v1/blocks/\(parentId)/children?page_size=100\(page)", body: nil, retries: 5)
            // A non-200 means we genuinely don't know — surface it instead of falling
            // through to createDatabase and silently making a duplicate.
            guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
            let results = data["results"] as? [[String: Any]] ?? []
            for block in results where (block["type"] as? String) == "child_database" {
                let blockId = str(block["id"])
                let child = block["child_database"] as? [String: Any] ?? [:]
                var title = str(child["title"])
                // Data-source-backed DBs can report an EMPTY title in the block listing;
                // fetch the database itself to read its real title.
                if title.isEmpty { title = (try? await databaseTitle(blockId)) ?? "" }
                if title == schema.dbTitle { return blockId }
            }
            cursor = (data["has_more"] as? Bool == true) ? (data["next_cursor"] as? String) : nil
        } while cursor != nil
        return nil
    }

    /// The plain-text title of a database (for when the child_database block omits it).
    func databaseTitle(_ databaseId: String) async throws -> String {
        let (status, data) = try await call("GET", "/v1/databases/\(databaseId)", body: nil, retries: 5)
        guard status == 200 else { return "" }
        let rich = data["title"] as? [[String: Any]] ?? []
        return rich.compactMap {
            ($0["plain_text"] as? String) ?? (($0["text"] as? [String: Any])?["content"] as? String)
        }.joined()
    }

    public func createDatabase(parentId: String) async throws -> String {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": parentId],
            "title": [["type": "text", "text": ["content": schema.dbTitle]]],
            "initial_data_source": ["properties": schema.propertiesDefinition()]]
        let (status, data) = try await call("POST", "/v1/databases", body: body, retries: 5)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
        return str(data["id"])
    }

    /// Find the schema-titled child database under the parent page, or create it.
    public func ensureDatabase(parentURL: String) async throws -> String {
        let parentId = try Self.pageId(fromURL: parentURL)
        if let existing = try await findExistingDatabase(parentId: parentId) { return existing }
        return try await createDatabase(parentId: parentId)
    }
}

// MARK: - Upsert (query → create-or-update, keyed by the date property)

extension NotionClient {
    /// Notion accepts at most 100 children per request.
    public func appendBlocks(pageId: String, blocks: [[String: Any]]) async throws {
        var start = 0
        while start < blocks.count {
            let slice = Array(blocks[start..<min(start + 100, blocks.count)])
            let (status, data) = try await call(
                "PATCH", "/v1/blocks/\(pageId)/children", body: ["children": slice], retries: 5)
            guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
            start += 100
        }
    }

    /// Create with a one-shot markdown body. NOT retried (no idempotency key). If
    /// the markdown path is rejected, write the body as blocks so the day is
    /// never lost to a page with no body.
    public func createRow(dataSourceId: String, props: [String: Any],
                          markdown: String) async throws -> (usedMarkdown: Bool, pageId: String, url: String) {
        var body: [String: Any] = [
            "parent": ["type": "data_source_id", "data_source_id": dataSourceId],
            "properties": props, "markdown": markdown]
        var (status, data) = try await call("POST", "/v1/pages", body: body, retries: 1)
        if status == 200 { return (true, str(data["id"]), str(data["url"])) }

        body.removeValue(forKey: "markdown")
        (status, data) = try await call("POST", "/v1/pages", body: body, retries: 1)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
        let pageId = str(data["id"])
        try await appendBlocks(pageId: pageId, blocks: NotionPayloads.markdownToBlocks(markdown))
        return (false, pageId, str(data["url"]))
    }

    public func updateRow(pageId: String, props: [String: Any], markdown: String) async throws -> Bool {
        var (status, data) = try await call("PATCH", "/v1/pages/\(pageId)",
                                            body: ["properties": props], retries: 5)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }

        (status, data) = try await call("PATCH", "/v1/pages/\(pageId)/markdown", body: [
            "type": "replace_content",
            "replace_content": ["new_str": markdown, "allow_deleting_content": true]], retries: 5)
        if status == 200 { return true }

        // Erase first, else the fallback appends a second copy under the old text.
        (status, data) = try await call("PATCH", "/v1/pages/\(pageId)",
                                        body: ["erase_content": true], retries: 5)
        guard status == 200 else { throw NotionError.http(status, str(data["code"]), str(data["message"])) }
        try await appendBlocks(pageId: pageId, blocks: NotionPayloads.markdownToBlocks(markdown))
        return false
    }

    /// Query-then-create-or-update, keyed by the date property.
    @discardableResult
    public func upsert(databaseId: String, digest: DayDigest,
                       config: DayConfig, now: Date) async throws -> String {
        let dataSourceId = try await resolveDataSource(databaseId: databaseId)
        let hits = try await findByDate(dataSourceId: dataSourceId, date: digest.date)
        let props = NotionPayloads.buildProperties(digest, schema: schema, config: config, now: now)

        if hits.count > 1 {
            throw NotionError.shape("\(digest.date) 행이 \(hits.count)개입니다. 중복을 먼저 정리하세요: \(hits)")
        }
        if let existing = hits.first {
            _ = try await updateRow(pageId: existing, props: props, markdown: digest.markdown)
            return existing
        }
        do {
            let created = try await createRow(dataSourceId: dataSourceId, props: props,
                                              markdown: digest.markdown)
            return created.pageId
        } catch {
            // The create is not retried, so a failure may still have landed
            // server-side. Look before trying again, or the next run makes a
            // second row and this date becomes unwritable forever.
            let recheck = try await findByDate(dataSourceId: dataSourceId, date: digest.date)
            if let found = recheck.first {
                _ = try await updateRow(pageId: found, props: props, markdown: digest.markdown)
                return found
            }
            throw error
        }
    }
}
