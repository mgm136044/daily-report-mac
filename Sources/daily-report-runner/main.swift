import DailyReportKit
import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: daily-report-runner "
        + "<run-day|notion-smoke|sanitize|collect|summarize|collect-sessions|collect-git|collect-codex|collect-fs>")
    exit(2)
}

switch args[1] {
case "notion-smoke":
    // Token: env override for first-time setup, else Keychain.
    let store = KeychainTokenStore()
    let token = ProcessInfo.processInfo.environment["DAILY_REPORT_NOTION_TOKEN"]
        ?? ((try? store.read(TokenAccount.notion)) ?? nil)
    guard let token, !token.isEmpty else {
        die("토큰이 없습니다. DAILY_REPORT_NOTION_TOKEN 로 넘기거나 Keychain에 저장하세요")
    }

    let (config, _) = ConfigStore.load(from: ConfigStore.url())
    let parentURL = ProcessInfo.processInfo.environment["DAILY_REPORT_PARENT_PAGE_URL"]
        ?? config.notion.parentPageURL
    guard let parentURL, !parentURL.isEmpty else {
        die("부모 페이지 URL이 없습니다 (테스트 페이지를 쓰세요)")
    }

    print("토큰 확인: \(token.prefix(8))… (len \(token.count))")   // never print the whole token
    let schema = NotionSchema(config: config)
    let client = NotionClient(token: token, transport: URLSessionTransport(), schema: schema)

    let digest = DayDigest(
        date: LogicalDate.logicalDate(Date(), config: config),
        markdown: "# 스모크 테스트\n- daily-report-mac Plan 1\n- Notion 싱크 검증",
        summary: "Plan 1 Notion 싱크 라이브 검증", projects: ["daily-report-mac"],
        tags: ["swift", "smoke"], sessions: 0, commits: 0, files: 0,
        status: .draft, source: "notion-smoke")

    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let dbId = try await client.ensureDatabase(parentURL: parentURL)
            print("DB 보장 완료: \(dbId)")
            let pageId = try await client.upsert(databaseId: dbId, digest: digest,
                                                 config: config, now: Date())
            print("✅ upsert 완료 — page \(pageId)")
        } catch { die("실패: \(error)") }
        semaphore.signal()
    }
    semaphore.wait()

case "sanitize":
    guard args.count >= 3 else { die("usage: daily-report-runner sanitize <file.json|file.txt>") }
    let path = args[2]
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
        die("파일을 읽을 수 없습니다: \(path)")
    }
    let output: String
    let findings: [String: Int]
    if path.hasSuffix(".json"),
       let data = raw.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) {
        let (clean, found) = Sanitizer.redactStructure(parsed)
        let pretty = try! JSONSerialization.data(withJSONObject: clean,
            options: [.prettyPrinted, .withoutEscapingSlashes])
        output = String(data: pretty, encoding: .utf8) ?? ""
        findings = found
    } else {
        let (clean, found) = Sanitizer.redact(raw)
        output = clean; findings = found
    }
    print(output)   // sanitized content → stdout (redirectable)
    FileHandle.standardError.write(Data(("살균: \(Sanitizer.describe(findings))\n").utf8))

case "collect-sessions":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args.count >= 3 ? args[2] : LogicalDate.logicalDate(Date(), config: cfg)
    let collection = ClaudeSessionCollector(config: cfg).collect(date: date)
    let (cleanProjects, findings) = Sanitizer.redactStructure(sessionProjectsAsJSON(collection.projects))
    let payload: [String: Any] = [
        "date": date,
        "projects": cleanProjects,
        "stats": ["transcripts_total": collection.stats.transcriptsTotal,
                  "transcripts_scanned": collection.stats.transcriptsScanned,
                  "records_in_day": collection.stats.recordsInDay]]
    let data = try! JSONSerialization.data(withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(data: data, encoding: .utf8) ?? "")
    FileHandle.standardError.write(Data(
        ("\(date): 전사본 \(collection.stats.transcriptsScanned)/\(collection.stats.transcriptsTotal) "
         + "· 레코드 \(collection.stats.recordsInDay) · 프로젝트 \(collection.projects.count) "
         + "· 살균 \(Sanitizer.describe(findings))\n").utf8))

case "collect-git":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args.count >= 3 ? args[2] : LogicalDate.logicalDate(Date(), config: cfg)
    let collection = GitCollector(config: cfg).collectGit(date: date)
    let (cleanPayload, findings) = Sanitizer.redactStructure(gitCollectionAsJSON(collection, date: date))
    let data = try! JSONSerialization.data(withJSONObject: cleanPayload,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(data: data, encoding: .utf8) ?? "")
    let skipNote = collection.skipped.map { " · \($0)" } ?? ""
    FileHandle.standardError.write(Data(
        ("\(date): 커밋 \(collection.commits.count) · 저장소 \(collection.reposScanned) "
         + "· 실패 \(collection.failures.count)\(skipNote) "
         + "· 살균 \(Sanitizer.describe(findings))\n").utf8))

case "collect-codex":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args.count >= 3 ? args[2] : LogicalDate.logicalDate(Date(), config: cfg)
    let collection = CodexCollector(config: cfg).collect(date: date)
    let (cleanPayload, findings) = Sanitizer.redactStructure(codexCollectionAsJSON(collection, date: date))
    let data = try! JSONSerialization.data(withJSONObject: cleanPayload,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(data: data, encoding: .utf8) ?? "")
    let s = collection.stats
    FileHandle.standardError.write(Data(
        ("\(date): 롤아웃 \(s.rolloutsScanned)/\(s.rolloutsTotal) · 레코드 \(s.recordsInDay) "
         + "· cwd \(collection.projects.count) · available \(s.available) "
         + "· 살균 \(Sanitizer.describe(findings))\n").utf8))

case "collect-fs":
    guard args.count >= 4 else { die("usage: daily-report-runner collect-fs <YYYY-MM-DD> <root> [root...]") }
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args[2]
    let roots = Array(args[3...])
    let base = ConfigStore.url().deletingLastPathComponent().path
    let collection = FSCollector(config: cfg, selfArtifactBase: base).collect(
        date: date, roots: roots, committed: [])
    let (cleanPayload, findings) = Sanitizer.redactStructure(fsCollectionAsJSON(collection, date: date))
    let data = try! JSONSerialization.data(withJSONObject: cleanPayload,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(data: data, encoding: .utf8) ?? "")
    let s = collection.stats
    FileHandle.standardError.write(Data(
        ("\(date): 루트 \(s.rootsScanned) · 파일 \(s.files) · 캡초과 드롭 \(s.filesDroppedOverCap) "
         + "· 살균 \(Sanitizer.describe(findings))\n").utf8))

case "collect":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args.count >= 3 ? args[2] : LogicalDate.logicalDate(Date(), config: cfg)
    let base = ConfigStore.url().deletingLastPathComponent().path
    do {
        let refined = try DayCollector(config: cfg, selfArtifactBase: base).collect(date: date)
        let (clean, findings) = Sanitizer.redactStructure(refinedDayAsJSON(refined))
        let data = try! JSONSerialization.data(withJSONObject: clean,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(data: data, encoding: .utf8) ?? "")
        let s = refined.stats
        FileHandle.standardError.write(Data(
            ("\(date): 프로젝트 \(s.projects) · 세션 \(s.sessions) · 파일 \(s.files) · 커밋 \(s.commits) "
             + "· 노이즈 \(s.noiseCommandsDropped) · cwd제거 \(s.cwdsDropped) "
             + "· 살균 \(Sanitizer.describe(findings))\n").utf8))
    } catch { die("수집 실패: \(error)") }

case "summarize":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let date = args.count >= 3 ? args[2] : LogicalDate.logicalDate(Date(), config: cfg)
    let base = ConfigStore.url().deletingLastPathComponent().path
    do {
        let refined = try DayCollector(config: cfg, selfArtifactBase: base).collect(date: date)
        guard !refined.projects.isEmpty else { die("\(date): 활동 없음 — 요약 생략") }
        let summarizer = Summarizer(config: cfg, runner: SummaryEngine.runner(for: cfg))
        let (pre, preMsg) = summarizer.preflight()
        guard pre else { die("preflight 실패: \(preMsg)") }
        let rawReport = try summarizer.summarize(refined)
        let (report, findings) = Sanitizer.redact(rawReport)   // sanitize AFTER the model
        let digest = summarizer.buildDayDigest(refined: refined, report: report, source: "(smoke)")
        print(report)
        FileHandle.standardError.write(Data(
            ("\(date): 보고서 \(report.count)자 · 요약 \"\(digest.summary.prefix(40))…\" "
             + "· 태그 \(digest.tags) · 살균 \(Sanitizer.describe(findings))\n").utf8))
    } catch { die("요약 실패: \(error)") }

case "run-day":
    let (cfg, _) = ConfigStore.load(from: ConfigStore.url())
    let base = ConfigStore.url().deletingLastPathComponent().path
    let stateDir = base + "/state", workDir = base + "/work"
    RunSupport.ensureDirs([stateDir, workDir, base + "/logs"])

    let store = KeychainTokenStore()
    let runToken = ProcessInfo.processInfo.environment["DAILY_REPORT_NOTION_TOKEN"]
        ?? ((try? store.read(TokenAccount.notion)) ?? nil)
    guard let runToken, !runToken.isEmpty else {
        die("토큰이 없습니다 (Keychain 또는 DAILY_REPORT_NOTION_TOKEN)")
    }
    let runParentURL = ProcessInfo.processInfo.environment["DAILY_REPORT_PARENT_PAGE_URL"]
        ?? cfg.notion.parentPageURL

    guard let lock = RunLock.acquire(path: stateDir + "/run.lock") else {
        // Distinct code so the app shows "이미 생성 중" instead of a silent spinner flash.
        print("이미 실행 중입니다. 종료합니다."); exit(RunExit.alreadyRunning)
    }
    defer { lock.release() }

    let runClient = NotionClient(token: runToken, transport: URLSessionTransport(),
                                 schema: NotionSchema(config: cfg))
    let ledgerURL = Ledger.url(stateDir: stateDir)
    let ledgerExists = FileManager.default.fileExists(atPath: ledgerURL)
    var state = Ledger.read(ledgerURL)
    let today = LogicalDate.logicalDate(Date(), config: cfg)

    let explicit = Array(args.dropFirst(2))

    let runSem = DispatchSemaphore(value: 0)
    Task {
        // Resolve the database up front — needed both to reconcile the first-run seed
        // and to run.
        let databaseId: String
        do {
            if let id = cfg.notion.databaseId, !id.isEmpty { databaseId = id }
            else { databaseId = try await runClient.ensureDatabase(parentURL: runParentURL ?? "") }
        } catch { die("Notion DB 확인 실패: \(error)") }

        let runTargets: [String]
        if !explicit.isEmpty {
            runTargets = explicit
        } else {
            // Notion-aware first-run seed: dates already reported in Notion are marked
            // "synced", not "설치 이전 날짜". This converges with the app's reconcile, so a
            // race between the two can't reintroduce false pre-install skips.
            let syncedDates = (try? await runClient.existingReportDates(databaseId: databaseId)) ?? []
            state = Backfill.seedFirstRun(state: state, ledgerExists: ledgerExists, today: today,
                                          syncedDates: syncedDates)
            try? Ledger.write(state, to: ledgerURL)
            runTargets = Backfill.pendingDays(state: state, today: today)
            if runTargets.isEmpty { print("밀린 날짜가 없습니다."); runSem.signal(); return }
            print("밀린 날짜 \(runTargets.count)일: \(runTargets.joined(separator: ", "))")
        }

        var okCount = 0
        var failed: [String] = []
        for date in runTargets {
            let runner = DayRunner(config: cfg, selfArtifactBase: base, stateDir: stateDir,
                workDir: workDir, claudeRunner: SummaryEngine.runner(for: cfg),
                notionClient: runClient, databaseId: databaseId)
            do {
                let r = try await runner.runOne(date: date)
                var entry: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
                if let skip = r.skipped {
                    entry["skipped"] = skip
                } else {
                    entry["projects"] = r.projects; entry["sessions"] = r.sessions
                    entry["files"] = r.files; entry["commits"] = r.commits
                    entry["report_chars"] = r.reportChars
                }
                state = Ledger.record(state, date: date, entry: entry)
                try? Ledger.write(state, to: ledgerURL)
                okCount += 1
                let note = r.skipped ?? "프로젝트 \(r.projects)·세션 \(r.sessions)·파일 \(r.files)"
                    + "·커밋 \(r.commits)·보고서 \(r.reportChars)자·살균 \(Sanitizer.describe(r.digestFindings))"
                FileHandle.standardError.write(Data("\(date): \(note)\n".utf8))
            } catch {
                failed.append(date)
                FileHandle.standardError.write(Data("\(date): 실패 — \(error)\n".utf8))
            }
        }
        if !failed.isEmpty {
            RunSupport.notify(title: "하루 마감 보고서 실패",
                              message: "\(failed.count)일 실패: \(failed.joined(separator: ", "))")
        }
        print("완료 \(okCount)일" + (failed.isEmpty ? "." : " · 실패 \(failed.count)일."))
        runSem.signal()
    }
    runSem.wait()

default:
    die("알 수 없는 커맨드: \(args[1])")
}

/// RefinedDay → [String: Any] (snake_case). Single source lives in the Kit.
func refinedDayAsJSON(_ r: RefinedDay) -> [String: Any] { DigestJSON.object(r) }

/// FSCollection → [String: Any] with snake_case keys matching Python collect_fs.py.
func fsCollectionAsJSON(_ c: FSCollection, date: String) -> [String: Any] {
    ["date": date, "roots": c.roots,
     "stats": ["roots_scanned": c.stats.rootsScanned,
               "files": c.stats.files,
               "files_dropped_over_cap": c.stats.filesDroppedOverCap]]
}

/// CodexCollection → [String: Any] with snake_case keys matching Python collect_codex.py.
func codexCollectionAsJSON(_ c: CodexCollection, date: String) -> [String: Any] {
    var projects: [String: Any] = [:]
    for (cwd, p) in c.projects {
        projects[cwd] = [
            "sessions": p.sessions, "branches": p.branches, "prompts": p.prompts,
            "bash_commands": p.bashCommands, "files_added": p.filesAdded,
            "files_updated": p.filesUpdated, "files_deleted": p.filesDeleted,
            "plans": p.plans, "outcomes": p.outcomes,
            "subagent_threads": p.subagentThreads,
            "first_ts": p.firstTS as Any, "last_ts": p.lastTS as Any]
    }
    return ["date": date, "projects": projects,
            "stats": ["rollouts_total": c.stats.rolloutsTotal,
                      "rollouts_scanned": c.stats.rolloutsScanned,
                      "records_in_day": c.stats.recordsInDay,
                      "available": c.stats.available]]
}

/// Turn a GitCollection into the `[String: Any]` shape redactStructure walks,
/// with snake_case keys matching the Python collect.py JSON.
func gitCollectionAsJSON(_ c: GitCollection, date: String) -> [String: Any] {
    let commits: [[String: Any]] = c.commits.map { k in
        ["repo": k.repo, "project": k.project, "sha": k.sha, "at": k.at,
         "authored_at": k.authoredAt, "author": k.author, "subject": k.subject,
         "files": k.files, "insertions": k.insertions, "deletions": k.deletions,
         "paths": k.paths]
    }
    let failures: [[String: Any]] = c.failures.map { ["repo": $0.repo, "reason": $0.reason] }
    var out: [String: Any] = [
        "date": date, "commits": commits,
        "repos_scanned": c.reposScanned, "failures": failures]
    if let skipped = c.skipped { out["skipped"] = skipped }
    return out
}

/// Turn typed SessionProjects into the `[String: Any]` shape redactStructure walks.
func sessionProjectsAsJSON(_ projects: [String: SessionProject]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (cwd, p) in projects {
        out[cwd] = [
            "sessions": p.sessions, "branches": p.branches, "slugs": p.slugs,
            "skills_used": p.skillsUsed, "prompts": p.prompts,
            "files_written": p.filesWritten, "files_edited": p.filesEdited,
            "files_tracked": p.filesTracked, "bash_commands": p.bashCommands,
            "todos": p.todos, "first_ts": p.firstTS as Any, "last_ts": p.lastTS as Any]
    }
    return out
}
