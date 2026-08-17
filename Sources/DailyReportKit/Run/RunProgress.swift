import Foundation

/// One step of the per-day run pipeline, in execution order. The progress bar
/// advances one notch per stage.
public enum RunStage: String, CaseIterable, Sendable {
    case collect, sanitize, summarize, notion

    /// 0-based position within a single day's pipeline.
    public var order: Int { Self.allCases.firstIndex(of: self)! }

    /// Korean label shown next to the bar.
    public var label: String {
        switch self {
        case .collect:   return "수집 중"
        case .sanitize:  return "살균 중"
        case .summarize: return "요약 중"
        case .notion:    return "노션 업로드 중"
        }
    }
}

/// A progress update the app renders: which date of how many, which stage, and
/// how much of the whole run is complete BEFORE this stage begins (0...1).
public struct RunProgress: Equatable, Sendable {
    public var totalDates: Int
    public var dateIndex: Int   // 1-based
    public var date: String
    public var stage: RunStage
    public var fraction: Double

    public init(totalDates: Int, dateIndex: Int, date: String, stage: RunStage, fraction: Double) {
        self.totalDates = totalDates; self.dateIndex = dateIndex
        self.date = date; self.stage = stage; self.fraction = fraction
    }
}

/// The wire format the runner prints and the parser reads — one source of truth so
/// the two can never drift. Progress lines carry a prefix so ordinary human-facing
/// stdout ("완료 1일." etc.) is passed through untouched.
public enum RunProgressWire {
    public static let prefix = "@P"

    /// Announce how many days this run will process (the bar's denominator).
    public static func total(_ n: Int) -> String { "\(prefix) total=\(n)" }

    /// Announce that `stage` of day `index` (1-based) is starting.
    public static func stage(index: Int, date: String, stage: RunStage) -> String {
        "\(prefix) index=\(index) date=\(date) stage=\(stage.rawValue)"
    }
}

/// Stateful line parser. It remembers the total announced by a `total=` line, then
/// turns each following `stage=` line into a `RunProgress`. A stage line seen before
/// any total, or any non-progress line, yields nil.
public struct RunProgressParser {
    private var total = 0
    public init() {}

    public mutating func consume(_ line: String) -> RunProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(RunProgressWire.prefix + " ") else { return nil }
        let fields = Self.fields(trimmed)

        if let totalStr = fields["total"], let n = Int(totalStr) {
            total = n
            return nil
        }
        guard total > 0,
              let indexStr = fields["index"], let index = Int(indexStr),
              let date = fields["date"],
              let stageStr = fields["stage"], let stage = RunStage(rawValue: stageStr)
        else { return nil }

        let perDay = RunStage.allCases.count
        let completed = (index - 1) * perDay + stage.order
        let fraction = Double(completed) / Double(total * perDay)
        return RunProgress(totalDates: total, dateIndex: index, date: date,
                           stage: stage, fraction: fraction)
    }

    /// Parse the `key=value` pairs that follow the `@P` prefix token.
    private static func fields(_ line: String) -> [String: String] {
        var out: [String: String] = [:]
        for token in line.split(separator: " ").dropFirst() {   // drop the "@P" prefix token
            let kv = token.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }
}
