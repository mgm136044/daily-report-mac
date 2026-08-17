import XCTest
@testable import DailyReportKit

final class DayConfigTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-\(UUID().uuidString)")
            .appendingPathComponent("config.json")
    }

    func test_defaults_have_a_four_am_boundary_and_korean_report() {
        XCTAssertEqual(DayConfig.defaultConfig.day.boundaryHour, 4)
        XCTAssertEqual(DayConfig.defaultConfig.report.language, "ko")
    }

    func test_missing_file_yields_defaults_and_flags_it() {
        let (config, usingDefaults) = ConfigStore.load(from: tempURL())
        XCTAssertTrue(usingDefaults)
        XCTAssertEqual(config, DayConfig.defaultConfig)
    }

    func test_defaults_have_noise_settings() {
        let n = DayConfig.defaultConfig.noise
        XCTAssertEqual(n.promptMaxChars, 1400)
        XCTAssertEqual(n.dedupePrefixChars, 60)
        XCTAssertEqual(n.commandMaxChars, 400)
        XCTAssertTrue(n.bashCommandPrefixes.contains("ls"))
    }

    func test_saved_config_round_trips() throws {
        let url = tempURL()
        var config = DayConfig.defaultConfig
        config.git.authors = ["me@example.com"]
        config.notion.databaseId = "db-123"
        try ConfigStore.save(config, to: url)

        let (loaded, usingDefaults) = ConfigStore.load(from: url)
        XCTAssertFalse(usingDefaults)
        XCTAssertEqual(loaded, config)
    }

    func test_defaults_have_git_walk_settings() {
        let s = DayConfig.defaultConfig.sources
        XCTAssertEqual(s.gitSearchRoot, "~")
        XCTAssertEqual(s.gitMaxDepth, 6)
        XCTAssertEqual(s.extraRepoRoots, [])
        XCTAssertTrue(s.walkExclude.contains("/Library/Mobile Documents/"))
        XCTAssertTrue(s.walkExclude.contains("/.Trash/"))
        XCTAssertEqual(s.walkExclude.count, 9)
    }
}
