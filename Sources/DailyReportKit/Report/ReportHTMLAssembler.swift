import Foundation

/// Data the app supplies for the report's chrome (everything not in the summary md).
public struct ReportChrome {
    public var date: String        // "2026-08-17"
    public var weekday: String     // "일"
    public var projects, sessions, commits, files: Int
    public var generatedAt: String // "2026-08-18 04:05"
    public var appVersion: String  // "1.4.0"
    public init(date: String, weekday: String, projects: Int, sessions: Int,
                commits: Int, files: Int, generatedAt: String, appVersion: String) {
        self.date = date; self.weekday = weekday; self.projects = projects
        self.sessions = sessions; self.commits = commits; self.files = files
        self.generatedAt = generatedAt; self.appVersion = appVersion
    }
}

/// Assembles the complete report HTML: app-generated chrome (header, totals, footer)
/// wrapping the Markdown-converted body, with design-system.css embedded verbatim.
public enum ReportHTMLAssembler {
    public static func assemble(chrome c: ReportChrome, markdownBody: String, css: String) -> String {
        func stat(_ n: Int, _ label: String) -> String {
            #"<div class="stat"><div class="n">\#(n)</div><div class="l">\#(label)</div></div>"#
        }
        let body = MarkdownToHTML.convert(markdownBody)
        return """
        <!DOCTYPE html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <style>
        \(css)
        </style>
        <style>
        /* PDF render: WKWebView.createPDF uses screen media, so @media print never fires.
           Re-apply the print look unconditionally → clean white output, not the grey preview backdrop.
           Kept as a SEPARATE block so the verbatim design-system.css embed above is byte-for-byte (B3). */
        html, body { background: #fff; padding: 0; }
        .page { box-shadow: none; }
        </style>
        </head>
        <body>
          <main class="page">
            <header class="head">
              <div class="title">하루 마감 보고서</div>
              <div class="date">\(c.date) (\(c.weekday))</div>
            </header>
            <section class="stats">
              \(stat(c.projects, "프로젝트"))\(stat(c.sessions, "세션"))\(stat(c.commits, "커밋"))\(stat(c.files, "파일"))
            </section>
            \(body)
            <footer class="foot">
              <span>\(c.generatedAt) 생성</span>
              <span>DailyReport v\(c.appVersion)</span>
              <span class="pageno">- 1 / 1 -</span>
            </footer>
          </main>
        </body>
        </html>
        """
    }
}
