import XCTest
@testable import DailyReportKit

final class FSNoiseTests: XCTestCase {
    private func collector(selfBase: String = "/opt/daily-report") -> FSCollector {
        FSCollector(config: .defaultConfig, selfArtifactBase: selfBase)
    }

    func test_noise_names_and_suffixes() {
        let c = collector()
        XCTAssertTrue(c.isNoise("/p/.DS_Store"))
        XCTAssertTrue(c.isNoise("/p/uv.lock"))
        XCTAssertTrue(c.isNoise("/p/foo.pyc"))
        XCTAssertTrue(c.isNoise("/p/build.log"))
        XCTAssertTrue(c.isNoise("/p/.env.local"))     // .env.* prefix
        XCTAssertTrue(c.isNoise("/p/id_rsa"))
        XCTAssertFalse(c.isNoise("/p/main.swift"))
    }

    func test_noise_dir_parts() {
        let c = collector()
        XCTAssertTrue(c.isNoise("/p/node_modules/react/index.js"))
        XCTAssertTrue(c.isNoise("/p/.venv/lib/x.py"))
        XCTAssertTrue(c.isNoise("/p/.git/config"))
        XCTAssertTrue(c.isNoise("/home/u/.claude/projects/x.jsonl"))
        XCTAssertFalse(c.isNoise("/p/src/app.py"))
    }

    func test_self_artifact_dirs_excluded() {
        let c = collector(selfBase: "/opt/daily-report")
        XCTAssertTrue(c.isNoise("/opt/daily-report/work/digest.json"))
        XCTAssertTrue(c.isNoise("/opt/daily-report/state/ledger.json"))
        XCTAssertTrue(c.isNoise("/opt/daily-report/logs/run.log"))
        XCTAssertFalse(c.isNoise("/opt/daily-report/src/main.swift"))
    }

    func test_trailing_slash_dir_uses_empty_basename() {
        // Python os.path.basename("/p/credentials/") == "" — a dir named like a
        // noise file is NOT flagged by name, only by NOISE_DIR_PARTS.
        let c = collector()
        XCTAssertFalse(c.isNoise("/p/credentials/"))   // dir, not the file "credentials"
        XCTAssertTrue(c.isNoise("/p/credentials"))     // the file
    }
}
