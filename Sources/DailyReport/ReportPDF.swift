import WebKit
import PDFKit
import Foundation

/// Renders assembled report HTML to PDF Data via an offscreen WKWebView (render path A:
/// design-system.css is the renderer). App-side because WKWebView needs a GUI context.
enum ReportPDF {
    @MainActor
    static func makePDF(html: String, title: String, version: String) async throws -> Data {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123))
        let loader = LoadDelegate()
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        try await loader.wait()                                  // navigation finished
        try await Task.sleep(nanoseconds: 150_000_000)           // let layout/webfonts settle

        let raw: Data = try await withCheckedThrowingContinuation { cont in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                cont.resume(with: result)
            }
        }
        return Self.withMetadata(raw, title: title, version: version)
    }

    /// Set safe document attributes; never embed paths, tokens, or email.
    private static func withMetadata(_ data: Data, title: String, version: String) -> Data {
        guard let doc = PDFDocument(data: data) else { return data }
        doc.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: title,
            PDFDocumentAttribute.creatorAttribute: "DailyReport v\(version)",
            PDFDocumentAttribute.subjectAttribute: "daily-report 자동 생성 보고서",
        ]
        return doc.dataRepresentation() ?? data
    }
}

/// Bridges WKWebView's delegate callback to async/await.
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    private var cont: CheckedContinuation<Void, Error>?
    func wait() async throws { try await withCheckedThrowingContinuation { cont = $0 } }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { cont?.resume(); cont = nil }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { cont?.resume(throwing: e); cont = nil }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { cont?.resume(throwing: e); cont = nil }
}
