import XCTest
import WebKit
@testable import Madobe

@MainActor
private func makeServices() -> Services {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    return Services(directory: dir, defaults: defaults)
}

final class ResolveTests: XCTestCase {
    func testEmpty() { XCTAssertNil(resolve("  ")) }
    func testFullURL() { XCTAssertEqual(resolve("http://a.b/c")?.absoluteString, "http://a.b/c") }
    func testBareHost() { XCTAssertEqual(resolve("apple.com")?.absoluteString, "https://apple.com") }
    func testSearch() { XCTAssertEqual(resolve("hello world")?.absoluteString, "https://duckduckgo.com/?q=hello%20world") }
    func testWordIsSearch() { XCTAssertTrue(resolve("swift")!.absoluteString.hasPrefix("https://duckduckgo.com/")) }
    func testSearchUsesChosenEngine() {
        XCTAssertEqual(resolve("hello", engine: .brave)?.absoluteString, "https://search.brave.com/search?q=hello")
    }
    func testEveryEngineBuildsAQuery() {
        for engine in SearchEngine.allCases {
            let url = resolve("a b", engine: engine)
            XCTAssertEqual(url?.scheme, "https", engine.name)
            XCTAssertTrue(url?.absoluteString.contains("q=a%20b") ?? false, engine.name)
        }
    }
}

@MainActor
final class TabsTests: XCTestCase {
    func testAddAndClose() {
        let t = Tabs(services: makeServices())
        t.add(""); XCTAssertEqual(t.pages.count, 2); XCTAssertEqual(t.current, t.pages[1].id)
        t.close(t.pages[1]); XCTAssertEqual(t.pages.count, 1); XCTAssertEqual(t.current, t.pages[0].id)
    }
    func testNeverClosesLast() { let t = Tabs(services: makeServices()); t.close(t.pages[0]); XCTAssertEqual(t.pages.count, 1) }

    func testRestoresSavedTabs() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(["https://a.example", "https://b.example"], forKey: Tabs.restoreKey)
        let t = Tabs(services: makeServices(), restore: true, defaults: defaults)
        XCTAssertEqual(t.pages.count, 2)
        XCTAssertEqual(t.current, t.pages[0].id)
    }

    func testPrivateTabUsesNonPersistentStore() {
        let t = Tabs(services: makeServices())
        t.add("", isPrivate: true)
        XCTAssertTrue(t.page.isPrivate)
        XCTAssertFalse(t.page.web.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(t.pages[0].web.configuration.websiteDataStore.isPersistent)
    }

    func testNewWindowLinkOpensATab() {
        let t = Tabs(services: makeServices())
        t.pages[0].onNewTab?(URL(string: "https://example.com")!)
        XCTAssertEqual(t.pages.count, 2)
    }
}

@MainActor
final class LibraryTests: XCTestCase {
    private func library() -> Library {
        Library(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testBookmarkToggleAndPersistence() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let lib = Library(directory: dir)
        lib.toggleBookmark(title: "Apple", url: "https://apple.com")
        XCTAssertTrue(lib.isBookmarked("https://apple.com"))
        XCTAssertEqual(Library(directory: dir).bookmarks.count, 1, "saved to disk")
        lib.toggleBookmark(title: "Apple", url: "https://apple.com")
        XCTAssertFalse(lib.isBookmarked("https://apple.com"))
        XCTAssertEqual(Library(directory: dir).bookmarks.count, 0)
    }

    func testHistoryMovesRepeatVisitToTop() {
        let lib = library()
        lib.record(title: "A", url: "https://a.example")
        lib.record(title: "B", url: "https://b.example")
        lib.record(title: "A again", url: "https://a.example")
        XCTAssertEqual(lib.history.map(\.url), ["https://a.example", "https://b.example"])
        XCTAssertEqual(lib.history.first?.title, "A again")
    }

    func testHistoryIsCapped() {
        let lib = library()
        for i in 0..<(Library.historyLimit + 25) { lib.record(title: "p\(i)", url: "https://x.example/\(i)") }
        XCTAssertEqual(lib.history.count, Library.historyLimit)
        XCTAssertEqual(lib.history.first?.url, "https://x.example/\(Library.historyLimit + 24)")
    }

    func testClearAndRemoveHistory() {
        let lib = library()
        lib.record(title: "A", url: "https://a.example")
        lib.record(title: "B", url: "https://b.example")
        lib.removeHistory([lib.history[0]])
        XCTAssertEqual(lib.history.count, 1)
        lib.clearHistory()
        XCTAssertTrue(lib.history.isEmpty)
    }

    func testEmptyTitleFallsBackToURL() {
        let lib = library()
        lib.record(title: "", url: "https://a.example")
        XCTAssertEqual(lib.history[0].title, "https://a.example")
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    func testSettingsPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let a = Settings(defaults: defaults)
        XCTAssertTrue(a.blockTrackers, "blocking is on by default")
        XCTAssertEqual(a.engine, .duckDuckGo)
        a.engine = .google
        a.blockTrackers = false
        a.homepage = "https://example.com"
        let b = Settings(defaults: defaults)
        XCTAssertEqual(b.engine, .google)
        XCTAssertFalse(b.blockTrackers)
        XCTAssertEqual(b.homepage, "https://example.com")
    }

    func testBlockerFollowsTheSetting() {
        let services = makeServices()
        XCTAssertTrue(services.blocker.enabled)
        services.settings.blockTrackers = false
        XCTAssertFalse(services.blocker.enabled)
    }
}

@MainActor
final class ContentBlockerTests: XCTestCase {
    func testRulesAreValidJSONWithOneRulePerDomain() throws {
        let data = Data(ContentBlocker.rulesJSON.utf8)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, ContentBlocker.blockedDomains.count)
        for rule in rules {
            XCTAssertNotNil(rule["trigger"])
            XCTAssertEqual((rule["action"] as? [String: String])?["type"], "block")
        }
    }

    func testWebKitCompilesTheRules() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(forIdentifier: "test-\(UUID().uuidString)",
                                                          encodedContentRuleList: ContentBlocker.rulesJSON)
        XCTAssertNotNil(list)
    }
}

@MainActor
final class NavigationFailureTests: XCTestCase {
    func testFailuresAreVisibleAndClearOnNavigation() {
        let page = Page("", services: makeServices())
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
