import Foundation

/// Dotted numeric version compare, tolerant of a leading "v" and differing lengths.
/// Compares component-wise as integers so "1.10.0" > "1.9.0" (not lexical).
public enum SemVer {
    static func parts(_ s: String) -> [Int] {
        let body = (s.hasPrefix("v") || s.hasPrefix("V")) ? String(s.dropFirst()) : s
        return body.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// True iff `a` is strictly newer than `b` (shorter side zero-padded).
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// A newer release worth downloading.
public struct ReleaseInfo: Equatable {
    public let version: String   // normalized, no leading "v"
    public let dmgURL: String
    public let notes: String
    public init(version: String, dmgURL: String, notes: String) {
        self.version = version; self.dmgURL = dmgURL; self.notes = notes
    }
}

/// Outcome of an update check. A manual "check now" button must distinguish
/// "you're current" from "the check failed" — collapsing both to nil would tell a
/// user with no network that they're up to date.
public enum UpdateCheckResult: Equatable {
    case newer(ReleaseInfo)
    case upToDate           // reachable + parsed, but nothing newer to install
    case failed             // network / non-200 / parse error
}

/// Checks a public GitHub releases repo's `releases/latest` for a newer version.
/// Injected transport → testable. `check` never throws (so an update check can't
/// break the app); it reports failure explicitly instead.
public struct UpdateChecker {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    public func check(current: String, owner: String, repo: String) async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
        else { return .failed }
        let headers = ["Accept": "application/vnd.github+json", "User-Agent": "DailyReport"]
        // A network error, non-200, or unparseable body is a FAILED check, not "up to date".
        guard let resp = try? await transport.send(method: "GET", url: url, headers: headers, body: nil),
              resp.status == 200,
              let obj = try? JSONSerialization.jsonObject(with: resp.body) as? [String: Any],
              let tag = obj["tag_name"] as? String
        else { return .failed }

        guard SemVer.isNewer(tag, than: current) else { return .upToDate }

        let assets = obj["assets"] as? [[String: Any]] ?? []
        guard let dmg = assets.compactMap({ $0["browser_download_url"] as? String })
            .first(where: { $0.hasSuffix(".dmg") })
        else { return .upToDate }   // newer tag, but nothing installable → nothing to offer

        let version = (tag.hasPrefix("v") || tag.hasPrefix("V")) ? String(tag.dropFirst()) : tag
        return .newer(ReleaseInfo(version: version, dmgURL: dmg, notes: obj["body"] as? String ?? ""))
    }

    /// Convenience for the silent auto-check, which only cares about a newer release.
    public func latestIfNewer(current: String, owner: String, repo: String) async -> ReleaseInfo? {
        if case .newer(let info) = await check(current: current, owner: owner, repo: repo) { return info }
        return nil
    }
}
