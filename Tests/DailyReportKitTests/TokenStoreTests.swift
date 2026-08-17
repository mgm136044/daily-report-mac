import XCTest
@testable import DailyReportKit

final class TokenStoreTests: XCTestCase {
    func test_in_memory_round_trip() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.read("k"))
        try store.write("secret-value", account: "k")
        XCTAssertEqual(try store.read("k"), "secret-value")
    }

    func test_in_memory_overwrite_and_delete() throws {
        let store = InMemoryTokenStore()
        try store.write("one", account: "k")
        try store.write("two", account: "k")           // overwrite, not duplicate
        XCTAssertEqual(try store.read("k"), "two")
        try store.delete("k")
        XCTAssertNil(try store.read("k"))
    }
}
