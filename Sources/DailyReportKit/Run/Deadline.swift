import Foundation

/// Run a piece of work with a wall-clock deadline.
///
/// Used to keep an unattended run from hanging on a folder access that blocks on a
/// TCC permission prompt (which can wait indefinitely — it blocked one 04:00 run for
/// seven hours). A timed-out closure keeps running on its background thread — a
/// blocked filesystem syscall cannot be cancelled — but the caller gets `nil` and
/// moves on. The leaked thread dies when the syscall finally returns or the process
/// exits; the run itself no longer stalls.
public enum Deadline {
    private final class Box<T> { var value: T? }

    /// Returns `work()`'s result, or `nil` if it does not finish within `seconds`.
    public static func run<T>(seconds: Double, _ work: @escaping () -> T) -> T? {
        let sem = DispatchSemaphore(value: 0)
        let box = Box<T>()
        DispatchQueue.global().async {
            let result = work()
            box.value = result
            sem.signal()
        }
        return sem.wait(timeout: .now() + seconds) == .success ? box.value : nil
    }
}

/// Decide whether a directory root can be walked without hanging.
public enum RootAccess {
    /// Seconds to wait for a root to respond before treating it as inaccessible.
    /// A readable directory lists its top level in milliseconds; a TCC-blocked one
    /// never returns, so any value comfortably above disk latency works.
    public static let defaultTimeoutSec: Double = 8

    /// True if `path` responds to a directory listing within the deadline.
    ///
    /// A TCC prompt blocks the listing, so the probe times out → `false` (skip it).
    /// A fast permission error still counts as responsive → `true`; the walk's own
    /// `try?` then handles the empty/denied listing normally.
    public static func reachable(_ path: String, timeoutSec: Double = defaultTimeoutSec,
                                 fm: FileManager = .default) -> Bool {
        Deadline.run(seconds: timeoutSec) {
            _ = try? fm.contentsOfDirectory(atPath: path)
            return true
        } != nil
    }
}
