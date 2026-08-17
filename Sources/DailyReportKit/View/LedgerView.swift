import Foundation

public enum DayKind: String, Equatable { case done, skipped }

public struct DayCard: Equatable {
    public var date: String
    public var kind: DayKind
    public var projects: Int
    public var sessions: Int
    public var files: Int
    public var commits: Int
    public var reportChars: Int
    public var skippedReason: String?
    public var at: String?
    public var synced: Bool   // reconciled from Notion (report exists but wasn't run here)
    public init(date: String, kind: DayKind, projects: Int, sessions: Int, files: Int,
                commits: Int, reportChars: Int, skippedReason: String?, at: String?,
                synced: Bool = false) {
        self.date = date; self.kind = kind; self.projects = projects; self.sessions = sessions
        self.files = files; self.commits = commits; self.reportChars = reportChars
        self.skippedReason = skippedReason; self.at = at; self.synced = synced
    }
}

public enum AppHealth: Equatable {
    case healthy
    case needsAttention(pending: Int)
}

public struct LedgerSummary: Equatable {
    public var cards: [DayCard]
    public var pendingCount: Int
    public var health: AppHealth
    public init(cards: [DayCard], pendingCount: Int, health: AppHealth) {
        self.cards = cards; self.pendingCount = pendingCount; self.health = health
    }
}

/// Turn the raw ledger into what the menu bar app shows. Pure over its inputs.
public enum LedgerView {
    public static func summary(state: [String: Any], today: String, limit: Int) -> LedgerSummary {
        let completed = state["completed"] as? [String: Any] ?? [:]
        let cards: [DayCard] = completed.compactMap { date, value in
            guard let e = value as? [String: Any] else { return nil }
            if e["synced"] != nil {   // reconciled from an existing Notion report
                return DayCard(date: date, kind: .done, projects: 0, sessions: 0, files: 0,
                    commits: 0, reportChars: 0, skippedReason: nil, at: e["at"] as? String, synced: true)
            }
            if let reason = e["skipped"] as? String {
                return DayCard(date: date, kind: .skipped, projects: 0, sessions: 0, files: 0,
                    commits: 0, reportChars: 0, skippedReason: reason, at: e["at"] as? String)
            }
            func int(_ k: String) -> Int { e[k] as? Int ?? 0 }
            return DayCard(date: date, kind: .done, projects: int("projects"), sessions: int("sessions"),
                files: int("files"), commits: int("commits"), reportChars: int("report_chars"),
                skippedReason: nil, at: e["at"] as? String)
        }
        .sorted { $0.date > $1.date }

        let pending = Backfill.pendingDays(state: state, today: today).count
        return LedgerSummary(
            cards: Array(cards.prefix(limit)),
            pendingCount: pending,
            health: pending == 0 ? .healthy : .needsAttention(pending: pending))
    }
}
