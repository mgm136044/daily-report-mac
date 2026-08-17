import Foundation

/// Which closed logical days still need a report, and how a fresh install seeds
/// its ledger. A faithful port of `pending_days` / `seed_first_run`.
public enum Backfill {
    static let maxBackfillDays = 14
    static let firstRunDays = 1

    private static func addDays(_ date: String, _ offset: Int) -> String? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return nil }
        return f.string(from: d.addingTimeInterval(Double(offset) * 86_400))
    }

    /// Closed logical days (offset 1…14 back from today) not already in the ledger.
    public static func pendingDays(state: [String: Any], today: String) -> [String] {
        let done = Ledger.completedDates(state)
        var days: [String] = []
        for offset in 1...maxBackfillDays {
            if let day = addDays(today, -offset), !done.contains(day) { days.append(day) }
        }
        return days.sorted()
    }

    /// On a brand-new install (no ledger file), seed the fortnight before install:
    /// dates already reported in Notion (`syncedDates`) as "synced" so they aren't
    /// mislabeled, the rest as "설치 이전 날짜". Only the most recent closed day is left
    /// to run. Making this Notion-aware keeps the runner's seed in agreement with the
    /// app's reconcile, so a race between them can't reintroduce false pre-install skips.
    public static func seedFirstRun(state: [String: Any], ledgerExists: Bool,
                                    today: String, syncedDates: Set<String> = []) -> [String: Any] {
        if ledgerExists || !Ledger.completedDates(state).isEmpty { return state }
        var state = state
        for offset in (firstRunDays + 1)...maxBackfillDays {
            guard let day = addDays(today, -offset) else { continue }
            let entry: [String: Any] = syncedDates.contains(day)
                ? ["synced": "notion"] : ["skipped": "설치 이전 날짜"]
            state = Ledger.record(state, date: day, entry: entry)
        }
        return state
    }
}
