import Foundation

public struct ClaudeResult: Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
}

public enum ClaudeOutcome: Equatable {
    case launchFailed(String)
    case timedOut
    case completed(ClaudeResult)
}

public protocol ClaudeRunner {
    func run(prompt: String, maxTurns: Int, timeoutSec: Int) -> ClaudeOutcome
}

public enum Summarize {
    static let requiredPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Built explicitly so a launchd run behaves the same as a terminal run.
    /// USER is mandatory — the login keychain is keyed on it.
    public static func childEnv() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        let home = ("~" as NSString).expandingTildeInPath
        var out: [String: String] = [
            "HOME": home,
            "PATH": requiredPath,
            "USER": env["USER"] ?? (home as NSString).lastPathComponent,
            "LANG": env["LANG"] ?? "en_US.UTF-8",
            "TZ": "Asia/Seoul",
        ]
        if let shell = env["SHELL"] { out["SHELL"] = shell }
        return out
    }

    /// A temp directory to run the summarizer from, so its own transcript has no
    /// project root and is dropped from the next day's collection.
    public static func scratchDir() -> String {
        let dir = NSTemporaryDirectory() + "daily-report-summarizer"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Run a process whose executable/args/env/cwd are already configured, optionally
    /// feeding `stdinPrompt` to stdin (else stdin = /dev/null), draining stdout/stderr
    /// with a Swift-side timeout. Shared by the Claude engine (prompt on stdin) and the
    /// Codex engine (prompt as an arg; stdin must be /dev/null or codex blocks).
    static func capture(_ proc: Process, stdinPrompt: String?, timeoutSec: Int) -> ClaudeOutcome {
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe
        proc.standardInput = (stdinPrompt != nil) ? inPipe : FileHandle.nullDevice

        do { try proc.run() } catch { return .launchFailed("\(type(of: error))") }

        if let prompt = stdinPrompt {
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(Data(prompt.utf8))
                try? inPipe.fileHandleForWriting.close()
            }
        }
        var outData = Data(), errData = Data()
        let drain = DispatchGroup()
        drain.enter(); DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }
        drain.enter(); DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); drain.leave() }

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { proc.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + .seconds(timeoutSec)) == .timedOut {
            proc.terminate(); _ = drain.wait(timeout: .now() + .seconds(2)); return .timedOut
        }
        drain.wait()
        return .completed(ClaudeResult(status: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""))
    }
}

/// Chooses the summary engine from config: "codex" → Codex, anything else → Claude.
public enum SummaryEngine {
    public static func runner(for config: DayConfig) -> ClaudeRunner {
        config.summary.engine == "codex" ? ProcessCodexRunner() : ProcessClaudeRunner()
    }
}

/// Real `claude -p` shell-out: prompt on stdin, child env, scratch cwd, Swift-side timeout.
public struct ProcessClaudeRunner: ClaudeRunner {
    public init() {}
    public func run(prompt: String, maxTurns: Int, timeoutSec: Int) -> ClaudeOutcome {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["claude", "-p", "--max-turns", String(maxTurns)]
        proc.environment = Summarize.childEnv()
        proc.currentDirectoryURL = URL(fileURLWithPath: Summarize.scratchDir())
        return Summarize.capture(proc, stdinPrompt: prompt, timeoutSec: timeoutSec)
    }
}

/// Real `codex exec` shell-out. The prompt is a positional arg (not stdin) and stdin
/// is /dev/null — codex otherwise blocks reading additional input. Live flags only,
/// per the codex-delegation rule: model gpt-5.5, sandbox read-only, skip-git-repo-check
/// (gpt-5.2-codex/gpt-5-codex and --full-auto are dead). maxTurns is not applicable.
public struct ProcessCodexRunner: ClaudeRunner {
    let model: String
    public init(model: String = "gpt-5.5") { self.model = model }

    /// The argv handed to /usr/bin/env — pure, so the flag set is unit-testable.
    public static func arguments(prompt: String, model: String) -> [String] {
        ["codex", "exec", "--model", model, "--sandbox", "read-only",
         "--skip-git-repo-check", prompt]
    }

    public func run(prompt: String, maxTurns: Int, timeoutSec: Int) -> ClaudeOutcome {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = Self.arguments(prompt: prompt, model: model)
        proc.environment = Summarize.childEnv()
        proc.currentDirectoryURL = URL(fileURLWithPath: Summarize.scratchDir())
        return Summarize.capture(proc, stdinPrompt: nil, timeoutSec: timeoutSec)
    }
}

/// Test double: records the prompt it was handed, returns a scripted outcome.
public final class MockClaudeRunner: ClaudeRunner {
    public var lastPrompt: String?
    private let outcome: ClaudeOutcome
    public init(_ outcome: ClaudeOutcome) { self.outcome = outcome }
    public func run(prompt: String, maxTurns: Int, timeoutSec: Int) -> ClaudeOutcome {
        lastPrompt = prompt; return outcome
    }
}
