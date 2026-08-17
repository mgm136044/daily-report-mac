import Foundation

public struct HTTPResponse { public let status: Int; public let body: Data }

public protocol HTTPTransport {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPResponse
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPResponse {
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResponse(status: status, body: data)
    }
}

/// A scripted transport for tests: responses are dequeued in enqueue order and
/// every request is recorded so tests can assert on retry counts and methods.
public final class MockTransport: HTTPTransport {
    public struct Recorded { public let method: String; public let url: URL; public let body: Data? }
    private struct Canned { let status: Int; let data: Data }
    private var queue: [Canned] = []
    public private(set) var sentRequests: [Recorded] = []
    public init() {}

    public func enqueue(status: Int, json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        queue.append(Canned(status: status, data: data))
    }

    public func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPResponse {
        sentRequests.append(Recorded(method: method, url: url, body: body))
        guard !queue.isEmpty else { return HTTPResponse(status: 599, body: Data()) }
        let next = queue.removeFirst()
        return HTTPResponse(status: next.status, body: next.data)
    }
}
