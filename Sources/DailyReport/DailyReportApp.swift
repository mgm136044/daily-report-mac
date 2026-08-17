import SwiftUI
import AppKit
import Combine
import DailyReportKit

struct DailyReportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Only a Settings scene; the menu bar item + popover are owned by the
        // AppDelegate (a custom NSStatusItem, so right-click can show a menu —
        // which MenuBarExtra cannot).
        Settings { SettingsView().environmentObject(delegate.state) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var healthObserver: AnyCancellable?
    private var onboardingWindow: NSWindow?
    private var onboardingDone = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only; NOT LSUIElement

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusView().environmentObject(state))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon(state.summary.health)
        // health → icon (quiet when healthy, tinted when attention)
        healthObserver = state.$summary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in self?.updateIcon(summary.health) }

        // First launch: a menu-bar-only app is unfriendly to set up (you have to find
        // the menu bar item), so pop a real window that guides through onboarding, then
        // fall back to menu-bar-only. Marked once so it never re-appears.
        let ud = UserDefaults.standard
        if FirstRunGate.shouldShowOnboarding(hasLaunchedBefore: ud.bool(forKey: FirstRunGate.hasLaunchedKey),
                                             isConnected: state.isConnected) {
            ud.set(true, forKey: FirstRunGate.hasLaunchedKey)
            showOnboarding()
        }
    }

    // MARK: - First-run onboarding window

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)   // real window + dock icon + focus during onboarding
        let wizard = SetupWizardView(onFinish: { [weak self] in self?.onboardingWindow?.close() })
            .environmentObject(state)
        let window = NSWindow(contentViewController: NSHostingController(rootView: wizard))
        window.title = "DailyReport 시작하기"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self                // catch the red close button too
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Fires whether onboarding ends via 완료/X (SetupWizardView) or the window's red
    /// button. Return to menu-bar-only and point the user at the status item.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboardingWindow, !onboardingDone else { return }
        onboardingDone = true
        onboardingWindow = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "설정 완료 🎉"
            alert.informativeText = "이제부터 메뉴 막대 오른쪽 위의 달력 아이콘을 눌러 사용하세요."
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }

    private func updateIcon(_ health: AppHealth) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let tint: NSColor?
        switch health {
        case .healthy: symbol = "calendar"; tint = nil
        case .needsAttention: symbol = "calendar.badge.exclamationmark"; tint = .systemOrange
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DailyReport")
        image?.isTemplate = (tint == nil)   // template = adapts to menu bar light/dark
        button.image = image
        button.contentTintColor = tint
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        if event.type == .rightMouseUp {
            showMenu(from: button)
        } else {
            togglePopover(from: button)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            state.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        addItem(to: menu, "지금 실행", #selector(menuRunNow))
        addItem(to: menu, "설정", #selector(menuOpenSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, "종료", #selector(menuQuit), key: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuRunNow() { state.runNow() }
    @objc private func menuOpenSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func menuQuit() { NSApplication.shared.terminate(nil) }
}

/// A downloaded-or-pending app update, surfaced as a banner in the popover.
enum UpdateStatus: Equatable {
    case none
    case checking                   // a manual check is in flight
    case upToDate                   // manual check found nothing newer (transient)
    case failed                     // manual check couldn't reach/parse the release (transient)
    case downloading(String)        // version
    case downloaded(URL, String)    // local dmg path, version
}

/// The result of a connect attempt, structured so the wizard can route a failure
/// back to the exact step that fixes it (via `SetupHint`). `.other` covers non-Notion
/// failures (empty token, keychain write) that no single wizard step maps to.
enum SetupOutcome {
    case success(String)        // human-facing done message
    case notion(NotionError)    // structured Notion failure → SetupHint.remedy
    case other(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var summary = LedgerSummary(cards: [], pendingCount: 0, health: .healthy)
    @Published var lastError: String?
    @Published var notice: String?          // informational, non-error (e.g. "이미 생성 중")
    @Published private(set) var running = false
    @Published private(set) var progress: RunProgress?   // live pipeline progress; nil = idle
    @Published private(set) var update: UpdateStatus = .none
    /// Set by the not-connected popover CTA to ask Settings to (re-)present the wizard.
    /// A deterministic signal so the CTA works every time, not just on first launch.
    @Published var pendingWizard = false
    /// Cached launchd schedule state. STORED (not recomputed via launchctl on every
    /// access) so SwiftUI reads during rendering never shell out — running launchctl
    /// inside a view-update cycle spins a nested runloop and crashes (EXC_BAD_ACCESS).
    @Published private(set) var isScheduled = false
    /// Whether a Notion token is saved. Tracked as a NON-secret persisted flag — never
    /// by reading the Keychain — so rendering the UI (e.g. moving the schedule time,
    /// which re-renders Settings) never triggers a Keychain access prompt. The Keychain
    /// is touched only when the token is actually USED (connect / scheduled run).
    @Published private(set) var hasToken = false
    static let hasTokenKey = "hasNotionToken"

    private(set) var config: DayConfig
    let base: String
    private var reloadTimer: Timer?
    private var updateTimer: Timer?

    // Public repo holding both source and release binaries; the app reads releases/latest unauthenticated.
    private let releasesOwner = "mgm136044"
    private let releasesRepo = "daily-report-mac"

    init() {
        let (loaded, _) = ConfigStore.load(from: ConfigStore.url())
        config = loaded
        base = ConfigStore.url().deletingLastPathComponent().path
        // Token existence is a non-secret flag (never a Keychain read on render). Migrate
        // existing users: if already connected, a token must be saved.
        let ud = UserDefaults.standard
        if !ud.bool(forKey: Self.hasTokenKey), !(loaded.notion.databaseId ?? "").isEmpty {
            ud.set(true, forKey: Self.hasTokenKey)
        }
        hasToken = ud.bool(forKey: Self.hasTokenKey)
        reload()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        checkForUpdate()   // on launch, then every 6h
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdate() }
        }
        refreshScheduleState()   // read real launchd state once, off-main
    }

    /// Re-read the ledger from disk and recompute the summary.
    func reload() {
        let state = Ledger.read(Ledger.url(stateDir: base + "/state"))
        let today = LogicalDate.logicalDate(Date(), config: config)
        summary = LedgerView.summary(state: state, today: today, limit: 14)
    }

    /// Path to the runner binary (same dir as this app's executable, or PATH).
    var runnerPath: String {
        (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent
            .appending("/daily-report-runner") ?? "daily-report-runner"
    }

    // MARK: - Report runs

    func runNow() { runDates([]) }                                                    // backfill missed days
    func runToday() { runDates([LogicalDate.logicalDate(Date(), config: config)]) }   // 퇴근: today, now
    func runDate(_ ymd: String) { runDates([ymd]) }                                   // any past date

    /// Spawn the runner for the given logical dates (empty = auto-backfill). The runner
    /// reads the Keychain token itself, so the first manual run surfaces the one-time
    /// "allow access" prompt that later unattended runs depend on.
    private func runDates(_ dates: [String]) {
        guard !running else { return }
        running = true
        lastError = nil
        notice = nil
        progress = nil
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [runnerPath, "run-day"] + dates

        // Capture the runner's stdout and parse its "@P" progress lines to drive the bar.
        // Reading via AsyncBytes.lines keeps the parser a plain local inside one Task — no
        // mutable state shared across threads. The runner flushes each line, so updates
        // arrive as the run progresses rather than all at the end.
        let pipe = Pipe()
        p.standardOutput = pipe
        let outHandle = pipe.fileHandleForReading
        Task { [weak self] in
            var parser = RunProgressParser()
            do {
                for try await line in outHandle.bytes.lines {
                    guard let update = parser.consume(line) else { continue }
                    await MainActor.run { self?.progress = update }
                }
            } catch { /* pipe closed when the runner exits */ }
        }

        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in
                self?.running = false
                self?.progress = nil
                self?.reload()
                // A held lock (another run already in progress) is not a failure —
                // show a neutral notice, not a red error. Real failures still surface.
                switch RunExit.outcome(for: code) {
                case .ok:            self?.lastError = nil; self?.notice = nil
                case .busy(let m):   self?.lastError = nil; self?.notice = m
                case .failed(let m): self?.notice = nil; self?.lastError = m
                }
            }
        }
        do { try p.run() } catch { lastError = "실행 실패: \(error)"; running = false }
    }

    // MARK: - Schedule (self-managed user LaunchAgent)

    var scheduleHour: Int { config.run.scheduleHour ?? 4 }
    var scheduleMinute: Int { config.run.scheduleMinute ?? 5 }

    /// Read the real launchd state once, OFF the main thread, and cache it into the
    /// published `isScheduled`. Never call launchctl synchronously from a view update.
    func refreshScheduleState() {
        Task.detached { [weak self] in
            let loaded = ScheduleManager.isLoaded()
            await MainActor.run { [weak self] in self?.isScheduled = loaded }
        }
    }

    /// Persist the chosen time and install/remove the LaunchAgent. Two safety rails that
    /// together fix the "open Settings → crash" bug:
    ///  1) no-op when nothing actually changes (so the onAppear toggle-seed can't trigger
    ///     a reinstall), and
    ///  2) run the launchctl work OFF the main thread — never inside SwiftUI's layout/
    ///     update cycle, where its nested runloop re-enters SwiftUI and segfaults.
    func setSchedule(on: Bool, hour: Int, minute: Int) async {
        guard ScheduleManager.changeNeeded(requestedOn: on, currentlyOn: isScheduled,
                                           hour: hour, minute: minute,
                                           currentHour: scheduleHour, currentMinute: scheduleMinute)
        else { return }
        config.run.scheduleHour = hour
        config.run.scheduleMinute = minute
        try? ConfigStore.save(config, to: ConfigStore.url())
        let home = NSHomeDirectory(), user = NSUserName()
        let runner = runnerPath, logs = base + "/logs"
        // launchctl runs on a background executor (off the main thread — never inside a
        // SwiftUI update) and is AWAITED, so the caller can reconcile the toggle to the
        // real launchd state afterward. Awaiting from a debounced, cancel-on-change task
        // keeps mutations serialized so the last request wins.
        let failure = await Task.detached { () -> String? in
            do {
                if on {
                    try ScheduleManager.install(hour: hour, minute: minute, runnerPath: runner,
                                                logsDir: logs, home: home, user: user)
                } else {
                    ScheduleManager.uninstall(home: home)
                }
                return nil
            } catch { return "스케줄 변경 실패: \(error)" }
        }.value
        let loaded = await Task.detached { ScheduleManager.isLoaded() }.value
        isScheduled = loaded
        if let failure { lastError = failure }
    }

    // MARK: - Summary engine

    var engine: String { config.summary.engine ?? "claude" }
    func setEngine(_ e: String) {
        config.summary.engine = e
        try? ConfigStore.save(config, to: ConfigStore.url())
    }

    // MARK: - Update check (public releases repo → auto-download dmg)

    /// `manual == true` gives the user feedback: a spinner while checking and an
    /// "up to date" note when nothing is newer. The automatic (launch/timer) check stays
    /// silent so it never nags.
    func checkForUpdate(manual: Bool = false) {
        Task { @MainActor in
            if manual {
                // A manual re-check must not clobber a check/download already running,
                // nor wipe an install banner that's already up (which could then be
                // mislabeled "up to date" on a transient failure).
                switch update {
                case .checking, .downloading, .downloaded: return
                default: break
                }
                update = .checking
            }
            let result = await UpdateChecker(transport: URLSessionTransport())
                .check(current: AppVersion.current, owner: releasesOwner, repo: releasesRepo)
            switch result {
            case .failed:
                if manual { update = .failed; clearTransientSoon() }   // auto stays silent
            case .upToDate:
                if manual { update = .upToDate; clearTransientSoon() }
            case .newer(let info):
                if case .downloaded(_, let v) = update, v == info.version { return }
                if case .downloading(let v) = update, v == info.version { return }
                // Persist across launches: if this version's dmg is already on disk, just
                // surface it — don't re-download on every login.
                let dest = downloadDest(for: info.version)
                if FileManager.default.fileExists(atPath: dest.path) {
                    update = .downloaded(dest, info.version)
                    return
                }
                update = .downloading(info.version)
                if let local = await downloadDMG(info, to: dest) {
                    update = .downloaded(local, info.version)
                } else {
                    update = manual ? .failed : .none
                    if manual { clearTransientSoon() }
                }
            }
        }
    }

    /// Clear a transient note (.upToDate / .failed) after a few seconds — but never
    /// step on a real update that arrived in the meantime.
    private func clearTransientSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.update == .upToDate || self?.update == .failed { self?.update = .none }
        }
    }

    /// Safe semi-automatic install: open (mount) the downloaded dmg so Finder shows the
    /// drag-to-Applications window, then quit so the running app can be replaced. The
    /// disk image mounts in a separate process, so quitting doesn't interrupt it — but
    /// only quit once the open actually succeeds (the dmg may have been deleted).
    func installUpdate() {
        guard case .downloaded(let url, _) = update else { return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error == nil else {
                DispatchQueue.main.async { self.update = .failed; self.clearTransientSoon() }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Download destination. The version comes from a remote tag, so keep only digits
    /// and dots in the filename — defense against a crafted tag steering the path
    /// (belt-and-braces; the releases repo is ours).
    private func downloadDest(for version: String) -> URL {
        let safe = version.filter { $0.isNumber || $0 == "." }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        return downloads.appendingPathComponent("DailyReport-\(safe).dmg")
    }

    private func downloadDMG(_ info: ReleaseInfo, to dest: URL) async -> URL? {
        guard let url = URL(string: info.dmgURL) else { return nil }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            // URLSession.download does NOT throw on 4xx/5xx — a 404/HTML body would
            // otherwise be saved and revealed as a "dmg". Verify success first.
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch { return nil }
    }

    // MARK: - First-run setup

    /// Store the token in the Keychain (never logged), save the parent URL, resolve the
    /// database (reusing a still-valid one so reconnect never makes a duplicate), and
    /// reconcile the ledger with reports already in Notion.
    /// Closure-based entry used by SettingsView. Wraps `performSetup` and flattens the
    /// structured outcome into a single status string (Notion failures become the
    /// human remedy from `SetupHint`, so Settings no longer shows raw error dumps).
    func saveSetup(token rawToken: String, parentURL: String, done: @escaping (String) -> Void) {
        Task { @MainActor in
            switch await performSetup(token: rawToken, parentURL: parentURL) {
            case .success(let m): done(m)
            case .notion(let e):  done(SetupHint.remedy(for: e).message)
            case .other(let m):   done(m)
            }
        }
    }

    /// The actual connect: resolve/create the DB, reconcile existing reports, and
    /// return a STRUCTURED outcome. The wizard awaits this directly so it can map a
    /// `.notion` failure to the step that fixes it.
    func performSetup(token rawTokenIn: String, parentURL parentURLIn: String) async -> SetupOutcome {
        // Normalize first: pasted tokens/links often carry a trailing newline/space, which
        // would otherwise be stored in the Keychain and sent in the Bearer header (→ 401).
        let rawToken = rawTokenIn.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentURL = parentURLIn.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty field + a saved token → reuse it (so reconnect needn't re-type the token).
        let store = KeychainTokenStore()
        let token = rawToken.isEmpty ? (((try? store.read(TokenAccount.notion)) ?? nil) ?? "") : rawToken
        guard !token.isEmpty else { return .other("토큰을 입력하세요") }
        if !rawToken.isEmpty {
            do { try store.write(rawToken, account: TokenAccount.notion) }
            catch { return .other("토큰 저장 실패: \(error)") }
            UserDefaults.standard.set(true, forKey: Self.hasTokenKey)
            hasToken = true
        }
        config.notion.parentPageURL = parentURL
        try? ConfigStore.save(config, to: ConfigStore.url())
        do {
            let client = NotionClient(token: token, transport: URLSessionTransport(),
                                      schema: NotionSchema(config: config))
            // Reuse a still-valid databaseId — avoids re-scanning and, crucially, avoids
            // creating a DUPLICATE DB on every reconnect. Only find/create if it's gone.
            let dbId: String
            if let existing = config.notion.databaseId, !existing.isEmpty,
               (try? await client.resolveDataSource(databaseId: existing)) != nil {
                dbId = existing
            } else {
                dbId = try await client.ensureDatabase(parentURL: parentURL)
            }
            config.notion.databaseId = dbId
            try? ConfigStore.save(config, to: ConfigStore.url())
            let synced = await reconcileLedger(client: client, databaseId: dbId)
            // Publish an update so observers (SettingsView badge/button, popover) re-read
            // isConnected — reconcileLedger only reloads when it changed rows, which misses
            // the common "connect to a brand-new empty page" (synced == 0) case.
            reload()
            return .success("연결 완료 (DB \(dbId.prefix(8))…)"
                + (synced > 0 ? " · 기존 보고서 \(synced)일 동기화" : ""))
        } catch let e as NotionError {
            return .notion(e)
        } catch {
            return .other("연결 실패: \(error)")
        }
    }

    var isConnected: Bool { !(config.notion.databaseId ?? "").isEmpty }

    /// Seed the ledger with dates that already have a Notion report so a fresh install
    /// (or one pointed at a DB the Python tool filled) doesn't relabel them
    /// "설치 이전 날짜". Overwrites pre-install skips and blanks, but keeps this machine's
    /// own richer "done" records. Returns how many dates were (re)marked.
    private func reconcileLedger(client: NotionClient, databaseId: String) async -> Int {
        guard let dates = try? await client.existingReportDates(databaseId: databaseId), !dates.isEmpty
        else { return 0 }
        let ledgerURL = Ledger.url(stateDir: base + "/state")
        var state = Ledger.read(ledgerURL)
        let completed = state["completed"] as? [String: Any] ?? [:]
        var added = 0
        for date in dates {
            if let e = completed[date] as? [String: Any], e["skipped"] == nil { continue }  // real report / already synced
            state = Ledger.record(state, date: date, entry: ["synced": "notion"])
            added += 1
        }
        if added > 0 { try? Ledger.write(state, to: ledgerURL); reload() }
        return added
    }
}
