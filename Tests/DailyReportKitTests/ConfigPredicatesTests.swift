import XCTest
@testable import DailyReportKit

final class ConfigPredicatesTests: XCTestCase {
    private func config(exclude: [String] = [], walk: [String] = [],
                        rename: [String: String] = [:]) -> DayConfig {
        var c = DayConfig.defaultConfig
        c.exclude.paths = exclude
        c.sources.walkExclude = walk
        c.labels.rename = rename
        return c
    }

    func test_excluded_matches_as_a_path_fragment() {
        let c = config(exclude: ["/node_modules/"])
        XCTAssertTrue(c.isExcluded("/Users/me/app/node_modules/x"))
        XCTAssertFalse(c.isExcluded("/Users/me/app/src"))
    }

    func test_trailing_slash_is_added_before_matching() {
        // "/secret" as the last component must still match the fragment "/secret/"
        let c = config(exclude: ["/secret/"])
        XCTAssertTrue(c.isExcluded("/Users/me/secret"))
    }

    func test_walk_excluded_is_a_superset_of_excluded() {
        let c = config(exclude: ["/a/"], walk: ["/b/"])
        XCTAssertTrue(c.isWalkExcluded("/a/x"))   // from exclude
        XCTAssertTrue(c.isWalkExcluded("/b/x"))   // from walk-only
        XCTAssertFalse(c.isExcluded("/b/x"))      // walk-only does NOT affect collection
    }

    func test_whitelisted_extraRepoRoot_bypasses_walk_exclusion() {
        // A user-named project under an otherwise-excluded folder (e.g. ~/Downloads)
        // must be scannable — root and its whole subtree.
        var c = config(walk: ["/Downloads/"])
        c.sources.extraRepoRoots = ["/Users/me/Downloads/AutoSafer/proj"]
        XCTAssertTrue(c.isWalkExcluded("/Users/me/Downloads/Other"))               // not whitelisted
        XCTAssertFalse(c.isWalkExcluded("/Users/me/Downloads/AutoSafer/proj"))     // whitelisted root
        XCTAssertFalse(c.isWalkExcluded("/Users/me/Downloads/AutoSafer/proj/src")) // whitelisted subtree
    }

    func test_whitelist_does_not_override_hard_excludes() {
        var c = config(exclude: ["/node_modules/"], walk: ["/Downloads/"])
        c.sources.extraRepoRoots = ["/Users/me/Downloads/AutoSafer/proj"]
        XCTAssertTrue(c.isWalkExcluded("/Users/me/Downloads/AutoSafer/proj/node_modules/x"))
    }

    func test_whitelist_expands_tilde() {
        var c = config(walk: ["/Downloads/"])
        c.sources.extraRepoRoots = ["~/Downloads/AutoSafer/proj"]
        let home = ("~" as NSString).expandingTildeInPath
        XCTAssertFalse(c.isWalkExcluded(home + "/Downloads/AutoSafer/proj"))
    }

    func test_display_label_renames_known_folders_only() {
        let c = config(rename: [".claude": "Claude Code 설정"])
        XCTAssertEqual(c.displayLabel(".claude"), "Claude Code 설정")
        XCTAssertEqual(c.displayLabel("my-app"), "my-app")
    }

    func test_nfc_composes_decomposed_korean() {
        let decomposed = "\u{1112}\u{1161}\u{11AB}"   // ㅎ+ㅏ+ㄴ (NFD) → "한"
        XCTAssertEqual(DayConfig.nfc(decomposed), "한")
    }
}
