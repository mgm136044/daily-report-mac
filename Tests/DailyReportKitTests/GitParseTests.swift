import XCTest
@testable import DailyReportKit

final class GitParseTests: XCTestCase {
    private let US = "\u{1F}"   // unit separator, git field delimiter

    func test_single_commit_with_shortstat_and_paths() {
        let line = "abc123def456\(US)2026-08-12T10:00:00+09:00\(US)2026-08-12T09:00:00+09:00"
            + "\(US)me@example.com\(US)Fix bug"
        let sample = line + "\n 2 files changed, 10 insertions(+), 3 deletions(-)\nsrc/a.swift\nsrc/b.swift"
        let commits = GitCollector.parseGitLog(sample, repo: "/tmp/repo")

        XCTAssertEqual(commits.count, 1)
        let c = commits[0]
        XCTAssertEqual(c.sha, "abc123de")            // first 8 chars only
        XCTAssertEqual(c.at, "2026-08-12T10:00:00+09:00")       // committer date
        XCTAssertEqual(c.authoredAt, "2026-08-12T09:00:00+09:00")
        XCTAssertEqual(c.author, "me@example.com")
        XCTAssertEqual(c.subject, "Fix bug")
        XCTAssertEqual(c.files, 2)
        XCTAssertEqual(c.insertions, 10)
        XCTAssertEqual(c.deletions, 3)
        XCTAssertEqual(c.paths, ["/tmp/repo/src/a.swift", "/tmp/repo/src/b.swift"])
        XCTAssertEqual(c.project, "repo")
    }

    func test_shortstat_order_does_not_matter() {
        // shortstat BEFORE the name-only paths — parser must handle either order.
        let line = "sha00000\(US)c\(US)a\(US)me@x\(US)Subj"
        let sample = line + "\n 1 file changed, 4 insertions(+)\nonly.txt"
        let alt = line + "\nonly.txt\n 1 file changed, 4 insertions(+)"
        let a = GitCollector.parseGitLog(sample, repo: "/r")
        let b = GitCollector.parseGitLog(alt, repo: "/r")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a[0].files, 1)
        XCTAssertEqual(a[0].insertions, 4)
        XCTAssertEqual(a[0].deletions, 0)         // absent marker stays zero
        XCTAssertEqual(a[0].paths, ["/r/only.txt"])
    }

    func test_multiple_commits_split_on_separator_line() {
        let s1 = "sha1aaaa\(US)c1\(US)a1\(US)me@x\(US)First\n 1 file changed, 1 insertion(+)\nf1.txt"
        let s2 = "sha2bbbb\(US)c2\(US)a2\(US)me@x\(US)Second\n 1 file changed, 2 deletions(-)\nf2.txt"
        let commits = GitCollector.parseGitLog(s1 + "\n" + s2, repo: "/r")
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].subject, "First")
        XCTAssertEqual(commits[0].insertions, 1)
        XCTAssertEqual(commits[0].deletions, 0)
        XCTAssertEqual(commits[1].subject, "Second")
        XCTAssertEqual(commits[1].insertions, 0)
        XCTAssertEqual(commits[1].deletions, 2)
    }

    func test_commit_with_no_stat_or_paths() {
        let sample = "deadbeef\(US)c\(US)a\(US)me@x\(US)Empty tree touch"
        let commits = GitCollector.parseGitLog(sample, repo: "/r")
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].files, 0)
        XCTAssertEqual(commits[0].insertions, 0)
        XCTAssertEqual(commits[0].deletions, 0)
        XCTAssertEqual(commits[0].paths, [])
    }

    func test_name_only_path_is_nfc_joined() {
        // Decomposed Korean (NFD) from a name-only line must come back precomposed (NFC).
        let decomposed = "\u{1100}\u{1161}.txt"        // ᄀ + ᅡ  == 가 (NFD)
        let sample = "sha\(US)c\(US)a\(US)me@x\(US)Subj\n" + decomposed
        let commits = GitCollector.parseGitLog(sample, repo: "/r")
        XCTAssertEqual(commits[0].paths, ["/r/가.txt"])  // literal here is NFC
    }
}
