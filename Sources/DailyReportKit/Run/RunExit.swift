import Foundation

/// Shared contract for how the runner's process exit code is interpreted.
///
/// The runner used to `exit(0)` when another run already held the flock, so the
/// app could not tell "already running" apart from "finished" — a manual run just
/// flashed its spinner and cleared with nothing to show. The runner now exits with
/// a distinct code, and both the runner and the app agree on its meaning here.
public enum RunExit {
    /// Returned by the runner when another run already holds `run.lock`.
    /// 75 == EX_TEMPFAIL ("temporary failure; retry later").
    public static let alreadyRunning: Int32 = 75

    /// Returned by the runner when it ran to completion but produced no report
    /// (every target had no activity, or there was nothing to back-fill). A distinct
    /// code so the app can tell this apart from 0 (finished with output) and 75 (busy),
    /// and show a neutral "no activity" notice instead of clearing silently.
    /// 73 == EX_CANTCREAT ("can't create output").
    public static let noActivity: Int32 = 73

    /// User-facing meaning of a runner exit code.
    /// - `.ok`: finished normally (no message).
    /// - `.busy`: a run is already in progress — informational, NOT an error.
    /// - `.noActivity`: finished but made nothing — informational. The message is
    ///   assembled by the app, which knows the requested date(s).
    /// - `.failed`: a real failure — surface as an error.
    public enum Outcome: Equatable {
        case ok
        case busy(String)
        case noActivity
        case failed(String)
    }

    public static func outcome(for code: Int32) -> Outcome {
        switch code {
        case 0:
            return .ok
        case alreadyRunning:
            return .busy("이미 보고서를 생성 중입니다. 진행 중인 작업이 끝나면 자동으로 반영됩니다.")
        case noActivity:
            return .noActivity
        default:
            return .failed("보고서 생성 실패 (종료코드 \(code)) — 설정에서 토큰·엔진을 확인하세요.")
        }
    }

    /// Pure decision function: pick the process exit code from the run's outcome.
    /// Conservative scope — only "finished with nothing produced and no failures"
    /// maps to `noActivity`; failures keep the existing exit-0 behavior (improving the
    /// failure exit code is a separate change).
    public static func finalCode(produced: Int, failed: Int) -> Int32 {
        (failed == 0 && produced == 0) ? noActivity : 0
    }
}
