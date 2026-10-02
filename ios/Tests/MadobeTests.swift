import XCTest
@testable import Madobe

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


@MainActor
final class NavigationFailureTests: XCTestCase {
    func testFailuresAreVisibleAndClearOnNavigation() {
        let page = Page("")
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        page.webView(page.web, didFailProvisionalNavigation: nil, withError: error)
        XCTAssertEqual(page.errorMessage, error.localizedDescription)
        page.webView(page.web, didStartProvisionalNavigation: nil)
        XCTAssertNil(page.errorMessage)
        page.webView(page.web, didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        XCTAssertNil(page.errorMessage)
        page.loading = true
        page.webViewWebContentProcessDidTerminate(page.web)
        XCTAssertNotNil(page.errorMessage)
        XCTAssertFalse(page.loading)
    }
}
