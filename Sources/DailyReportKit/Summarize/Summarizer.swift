import Foundation

/// Turn a RefinedDay into a markdown report via headless `claude -p`, and
/// assemble the DayDigest the Notion sink consumes. Port of `summarize.py`.
public struct Summarizer {
    private let config: DayConfig
    private let runner: ClaudeRunner

    public init(config: DayConfig, runner: ClaudeRunner) {
        self.config = config; self.runner = runner
    }

    public func summarize(_ refined: RefinedDay) throws -> String {
        try summarize(digest: DigestJSON.object(refined), date: refined.date)
    }

    /// Summarize a pre-built (and pre-sanitized, by the caller) digest object.
    public func summarize(digest: [String: Any], date: String) throws -> String {
        let prompt = buildPrompt(digest: digest, date: date)
        switch runner.run(prompt: prompt, maxTurns: config.summary.maxTurns,
                          timeoutSec: config.summary.modelTimeoutSec) {
        case .launchFailed(let name):
            throw SummarizeError.runFailed("claude 실행 실패: \(name)")
        case .timedOut:
            throw SummarizeError.timedOut("요약이 \(config.summary.modelTimeoutSec)초 안에 끝나지 않았습니다")
        case .completed(let r):
            let combined = r.stdout + r.stderr
            if r.status != 0 {
                throw SummarizeError.runFailed(
                    "claude -p exit \(r.status): "
                    + String(combined.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
            }
            let text = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                throw SummarizeError.empty(
                    "요약이 비어 있습니다: "
                    + String(combined.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
            }
            let report = ReportHelpers.stripPreamble(text)
            try ReportHelpers.validate(report)
            return report
        }
    }

    func buildPrompt(digest: [String: Any], date: String) -> String {
        let language = config.report.language
        let names = Prompts.weekdayNames[language] ?? Prompts.weekdayNames["en"]!
        let weekday = names[mondayZeroWeekday(date)]
        let data = (try? JSONSerialization.data(withJSONObject: digest,
            options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        let digestJSON = String(data: data, encoding: .utf8) ?? "{}"
        return Prompts.build(digestJSON: digestJSON, date: date, weekday: weekday,
                             targetChars: config.report.targetChars, language: language)
    }

    /// Weekday index with Monday = 0 (Python datetime.weekday()).
    private func mondayZeroWeekday(_ date: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = LogicalDate.timeZone(config)
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return 0 }
        let weekday = cal.component(.weekday, from: d)   // Sunday = 1 … Saturday = 7
        return (weekday + 5) % 7                          // Monday = 0 … Sunday = 6
    }

    /// Confirm the CLI is reachable and authenticated before spending a run.
    public func preflight() -> (ok: Bool, message: String) {
        switch runner.run(prompt: "reply with exactly: OK", maxTurns: 1, timeoutSec: 120) {
        case .launchFailed(let name): return (false, "claude 를 찾을 수 없습니다 (\(name))")
        case .timedOut: return (false, "인증 확인이 120초 안에 끝나지 않았습니다")
        case .completed(let r):
            let combined = r.stdout + r.stderr
            if combined.contains("Not logged in") {
                return (false, "로그인되어 있지 않습니다 (USER 환경변수 누락 가능성)")
            }
            if r.status != 0 {
                return (false, "exit \(r.status): "
                    + String(combined.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))
            }
            return (true, "ok")
        }
    }

    /// Assemble the Notion-bound DayDigest from the refined day + its report.
    public func buildDayDigest(refined: RefinedDay, report: String, source: String) -> DayDigest {
        DayDigest(
            date: refined.date, markdown: report,
            summary: ReportHelpers.firstSentences(report),
            projects: refined.projects.map(\.label),
            tags: ReportHelpers.deriveTags(refined),
            sessions: refined.stats.sessions, commits: refined.stats.commits,
            files: refined.stats.files, status: .done, source: source)
    }
}
