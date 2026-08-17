import Foundation

/// Soft, client-side checks the wizard uses to enable its "다음" button and show a
/// green "형식이 맞아요" hint. These are deliberately lenient — a hard gate lives on
/// the server (the real connect attempt). The URL check REUSES the real parser so
/// validation can never be stricter than what the app itself accepts.
public enum SetupValidation {

    /// A Notion integration token: `ntn_` (2024+) or legacy `secret_`, with enough
    /// body to be a real secret rather than just the prefix.
    public static func looksLikeToken(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 20 else { return false }
        return s.hasPrefix("ntn_") || s.hasPrefix("secret_")
    }

    /// A parent page URL is valid exactly when the real parser can extract a page id
    /// from it — no separate, drift-prone regex.
    public static func looksLikeNotionURL(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        return (try? NotionClient.pageId(fromURL: s)) != nil
    }
}
