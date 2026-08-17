import Foundation

/// Manages a self-managed per-user LaunchAgent for the daily run.
///
/// We do NOT use SMAppService.agent: its plist must live read-only in the signed
/// bundle, so the schedule time can't be user-configured, and its status reflects
/// registration/approval — not "is my schedule active" — which made the toggle
/// reset. Instead the app writes its own plist to ~/Library/LaunchAgents and drives
/// it with domain-targeted launchctl (per Codex consult, 2026-08-14). No entitlement
/// is needed to write there under hardened runtime + notarization.
public enum ScheduleManager {
    public static let label = "com.mgm136044.DailyReportMac.schedule"
    public static let bundleID = "com.mgm136044.DailyReportMac"

    public static func plistURL(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The LaunchAgent property list. Absolute paths only (a self-managed plist can't
    /// use BundleProgram). USER/HOME are mandatory for the login keychain + `claude`/
    /// `codex`; PATH must include Homebrew so those binaries resolve. RunAtLoad is safe
    /// because run-day is ledger-gated (no pending day → immediate exit).
    public static func plistData(hour: Int, minute: Int, runnerPath: String, logsDir: String,
                                 home: String, user: String,
                                 caffeinatePath: String = "/usr/bin/caffeinate") -> Data {
        let dict: [String: Any] = [
            "Label": label,
            // caffeinate -s -i keeps the Mac awake for the duration (can't wake a
            // sleeping Mac; StartCalendarInterval catches up on the next wake).
            "ProgramArguments": [caffeinatePath, "-s", "-i", runnerPath, "run-day"],
            "EnvironmentVariables": [
                "HOME": home, "USER": user, "LOGNAME": user, "SHELL": "/bin/zsh",
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "LANG": "en_US.UTF-8", "TZ": "Asia/Seoul",
            ],
            "StartCalendarInterval": ["Hour": hour, "Minute": minute],
            "RunAtLoad": true,
            "StandardOutPath": logsDir + "/stdout.log",
            "StandardErrorPath": logsDir + "/stderr.log",
            "AssociatedBundleIdentifiers": [bundleID],   // attribute to the app in Login Items
            "ProcessType": "Background",
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    /// Whether applying (requestedOn, hour, minute) would actually change the current
    /// schedule. Callers use this to SKIP a redundant install/uninstall — critical
    /// because a needless reinstall triggered from a SwiftUI view update runs launchctl
    /// (a blocking, runloop-spinning Process) inside the layout pass and crashes.
    public static func changeNeeded(requestedOn: Bool, currentlyOn: Bool,
                                    hour: Int, minute: Int,
                                    currentHour: Int, currentMinute: Int) -> Bool {
        if requestedOn != currentlyOn { return true }   // turning on/off
        if !requestedOn { return false }                // both off → nothing to do
        return hour != currentHour || minute != currentMinute   // both on → only if time moved
    }

    // MARK: - launchctl management (side-effectful; invoked from the app)

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    private static var domainTarget: String { "gui/\(getuid())" }
    private static var serviceTarget: String { "gui/\(getuid())/\(label)" }

    /// True iff the agent is loaded — the EXIT CODE of `launchctl print` (its output
    /// format is unstable and must not be parsed).
    public static func isLoaded() -> Bool { launchctl(["print", serviceTarget]) == 0 }

    public enum ScheduleError: Error { case launchctlFailed(Int32) }

    /// Write the plist for hour:minute and (re)load it. Also the time-change path:
    /// rewrite → bootout → enable → bootstrap. Throws on file I/O OR if launchd never
    /// loads the agent (so the caller can surface it instead of the toggle flipping back).
    public static func install(hour: Int, minute: Int, runnerPath: String, logsDir: String,
                               home: String, user: String) throws {
        let url = plistURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // launchd opens StandardOut/ErrorPath at load — make the dir so the first
        // (RunAtLoad) run's log isn't dropped for a brand-new user.
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        let data = plistData(hour: hour, minute: minute, runnerPath: runnerPath,
                             logsDir: logsDir, home: home, user: user)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        launchctl(["bootout", serviceTarget])   // clear any prior instance (ok if absent)
        launchctl(["enable", serviceTarget])
        var rc = launchctl(["bootstrap", domainTarget, url.path])
        if rc != 0 {
            // bootout can return before launchd finishes teardown; settle and retry once.
            Thread.sleep(forTimeInterval: 0.3)
            launchctl(["bootout", serviceTarget])
            rc = launchctl(["bootstrap", domainTarget, url.path])
        }
        guard rc == 0 || isLoaded() else { throw ScheduleError.launchctlFailed(rc) }  // trust real state
    }

    /// Unload and remove the plist.
    public static func uninstall(home: String) {
        launchctl(["bootout", serviceTarget])
        launchctl(["disable", serviceTarget])
        try? FileManager.default.removeItem(at: plistURL(home: home))
    }
}
