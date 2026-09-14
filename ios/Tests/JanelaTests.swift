import XCTest
@testable import Janela

final class ResolveTests: XCTestCase {
    func testEmpty() { XCTAssertNil(resolve("  ")) }
    func testFullURL() { XCTAssertEqual(resolve("http://a.b/c")?.absoluteString, "http://a.b/c") }
    func testBareHost() { XCTAssertEqual(resolve("apple.com")?.absoluteString, "https://apple.com") }
    func testSearch() { XCTAssertEqual(resolve("hello world")?.absoluteString, "https://duckduckgo.com/?q=hello%20world") }
    func testWordIsSearch() { XCTAssertTrue(resolve("swift")!.absoluteString.hasPrefix("https://duckduckgo.com/")) }
}

@MainActor
final class TabsTests: XCTestCase {
    func testAddAndClose() {
        let t = Tabs()
        t.add(); XCTAssertEqual(t.pages.count, 2); XCTAssertEqual(t.current, t.pages[1].id)
        t.close(t.pages[1]); XCTAssertEqual(t.pages.count, 1); XCTAssertEqual(t.current, t.pages[0].id)
    }
    func testNeverClosesLast() { let t = Tabs(); t.close(t.pages[0]); XCTAssertEqual(t.pages.count, 1) }
}
