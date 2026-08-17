import Foundation

/// A single-instance lock via `flock`. `acquire` returns nil if another process
/// (or another instance in this process) already holds it.
public final class RunLock {
    private let fd: Int32
    private init(fd: Int32) { self.fd = fd }

    public static func acquire(path: String) -> RunLock? {
        let fd = open(path, O_WRONLY | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return nil }
        return RunLock(fd: fd)
    }

    public func release() { flock(fd, LOCK_UN); close(fd) }
}

public enum RunSupport {
    /// Create working dirs owner-only, and narrow any files already inside.
    public static func ensureDirs(_ dirs: [String]) {
        let fm = FileManager.default
        for path in dirs {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            for name in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
                let target = path + "/" + name
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: target, isDirectory: &isDir), !isDir.boolValue {
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target)
                }
            }
        }
    }

    /// A failed job that fails silently is worse than none — surface it.
    public static func notify(title: String, message: String) {
        let script = "display notification \(jsonString(message)) with title \(jsonString(title))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}
