import XCTest
@testable import DailyReportKit

final class ProjectRootsTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func mkdir(_ rel: String) -> URL {
        let u = tmp.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func touch(_ dir: URL, _ name: String) {
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
    }
    // Temp dirs on macOS live under /var → /private/var (a symlink). Standardize
    // so expected paths match what ProjectRoots computes.
    private func std(_ u: URL) -> String { (u.path as NSString).standardizingPath }

    func test_walks_up_to_the_nearest_marker() {
        let root = mkdir("app"); touch(root, "CONTEXT.md")
        let deep = mkdir("app/docs/04_report")
        let pr = ProjectRoots(config: .defaultConfig)
        XCTAssertEqual(pr.projectRoot(deep.path), std(root))
        XCTAssertEqual(pr.projectLabel(deep.path), "app")
    }

    func test_no_marker_returns_nil() {
        let deep = mkdir("loose/sub")
        var c = DayConfig.defaultConfig; c.projects.containers = []
        let pr = ProjectRoots(config: c)
        XCTAssertNil(pr.projectRoot(deep.path))
    }

    // The Claude desktop app runs Claude Code from the HOME dir by default, so those
    // sessions must land in a "홈" bucket instead of being dropped as unrooted.
    private var home: String { (("~" as NSString).expandingTildeInPath as NSString).standardizingPath }

    func test_home_dir_is_labeled_home() {
        let pr = ProjectRoots(config: .defaultConfig)
        XCTAssertEqual(pr.projectRoot(home), home)
        XCTAssertEqual(pr.projectLabel(home), "홈")
    }

    func test_home_subdir_without_marker_rolls_up_to_home() {
        var c = DayConfig.defaultConfig; c.projects.containers = []
        let pr = ProjectRoots(config: c)
        let sub = ("~/dr-nomarker-\(UUID().uuidString)" as NSString).expandingTildeInPath
        XCTAssertEqual(pr.projectLabel(sub), "홈")
    }

    func test_root_slash_still_dropped() {
        let pr = ProjectRoots(config: .defaultConfig)
        XCTAssertNil(pr.projectRoot("/"))
    }

    func test_direct_child_of_a_container_is_a_project_even_without_marker() {
        let container = mkdir("Downloads")
        let child = mkdir("Downloads/thing")
        var c = DayConfig.defaultConfig; c.projects.containers = [std(container)]
        let pr = ProjectRoots(config: c)
        XCTAssertEqual(pr.projectRoot(child.path), std(child))
        // ...but the container itself is never a project.
        XCTAssertNil(pr.projectRoot(container.path))
    }

    func test_never_list_drops_the_path() {
        let root = mkdir("secret"); touch(root, ".git")
        var c = DayConfig.defaultConfig
        c.projects.containers = []
        c.projects.never = [std(root)]
        let pr = ProjectRoots(config: c)
        XCTAssertNil(pr.projectRoot(root.path))
    }

    func test_relative_or_excluded_cwd_is_dropped() {
        var c = DayConfig.defaultConfig; c.exclude.paths = ["/node_modules/"]
        let pr = ProjectRoots(config: c)
        XCTAssertNil(pr.projectRoot("relative/path"))        // not absolute
        XCTAssertNil(pr.projectRoot("/x/node_modules/y"))    // excluded
    }
}
