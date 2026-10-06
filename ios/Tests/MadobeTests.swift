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

final class SiteKeyTests: XCTestCase {
    func testNormaliseLowercasesAndStripsWww() {
        XCTAssertEqual(SiteKey.normalise("WWW.Example.COM"), "example.com")
        XCTAssertEqual(SiteKey.normalise("example.com."), "example.com")
        XCTAssertEqual(SiteKey.normalise("www"), "www")
    }
    func testKeyForURLDropsPortAndRejectsOtherSchemes() {
        XCTAssertEqual(SiteKey.key(for: URL(string: "https://www.Apple.com:8443/a?b=1")), "apple.com")
        XCTAssertNil(SiteKey.key(for: URL(string: "mailto:a@b.c")))
        XCTAssertNil(SiteKey.key(for: URL(string: "about:blank")))
        XCTAssertNil(SiteKey.key(for: nil))
    }
    func testChainWalksToParents() {
        XCTAssertEqual(SiteKey.chain("a.b.example.com"), ["a.b.example.com", "b.example.com", "example.com"])
        XCTAssertEqual(SiteKey.chain("localhost"), ["localhost"])
    }
}

@MainActor
final class SiteRulesTests: XCTestCase {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testStoresAndReloadsRules() {
        let d = dir()
        let sites = SiteRules(directory: d)
        sites.set(SiteRule(zoom: 1.4, forceDark: true), forKey: "WWW.Example.com")
        let again = SiteRules(directory: d)
        XCTAssertEqual(again.rule(forKey: "example.com").zoom, 1.4)
        XCTAssertTrue(again.rule(for: URL(string: "https://www.example.com/x")).forceDark)
        XCTAssertTrue(again.rule(for: URL(string: "https://other.org")).isDefault)
    }

    func testSubdomainsInheritAndOwnRuleWins() {
        let sites = SiteRules(directory: dir())
        sites.set(SiteRule(blockImages: true), forKey: "example.com")
        XCTAssertTrue(sites.rule(forKey: "docs.example.com").blockImages)
        sites.set(SiteRule(blockScripts: true), forKey: "docs.example.com")
        XCTAssertFalse(sites.rule(forKey: "docs.example.com").blockImages)
        XCTAssertTrue(sites.rule(forKey: "docs.example.com").blockScripts)
    }

    func testDefaultRuleIsNotStored() {
        let d = dir()
        let sites = SiteRules(directory: d)
        sites.set(SiteRule(blockPopups: true), forKey: "a.example")
        XCTAssertEqual(sites.rules.count, 1)
        sites.reset(key: "a.example")
        XCTAssertTrue(sites.rules.isEmpty)
        XCTAssertTrue(SiteRules(directory: d).rules.isEmpty)
    }

    func testChangeCallbackFires() {
        let sites = SiteRules(directory: dir())
        var count = 0
        sites.onChange = { count += 1 }
        sites.set(SiteRule(forceDark: true), forKey: "a.example")
        XCTAssertEqual(count, 1)
    }

    func testZoomIsClampedAndPopupsRule() {
        XCTAssertEqual(SiteRule(zoom: 9).pageZoom, 2.0)
        XCTAssertEqual(SiteRule(zoom: 0.1).pageZoom, 0.5)
        XCTAssertFalse(SiteRule(blockPopups: true).allowsNewWindow(userTappedLink: false))
        XCTAssertTrue(SiteRule(blockPopups: true).allowsNewWindow(userTappedLink: true))
        XCTAssertTrue(SiteRule().allowsNewWindow(userTappedLink: false))
    }

    func testImageRulesJSON() throws {
        XCTAssertNil(SiteRules.imageRulesJSON([:]))
        XCTAssertNil(SiteRules.imageRulesJSON(["a.example": SiteRule(forceDark: true)]))
        let json = try XCTUnwrap(SiteRules.imageRulesJSON(["b.example": SiteRule(blockImages: true),
                                                           "a.example": SiteRule(blockImages: true)]))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 1)
        let trigger = try XCTUnwrap(rules[0]["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["if-domain"] as? [String], ["*a.example", "*b.example"])
        XCTAssertEqual(trigger["resource-type"] as? [String], ["image"])
    }

    func testWebKitCompilesImageRules() async throws {
        let json = try XCTUnwrap(SiteRules.imageRulesJSON(["example.com": SiteRule(blockImages: true)]))
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(forIdentifier: "test-\(UUID().uuidString)", encodedContentRuleList: json)
        XCTAssertNotNil(list)
    }

    func testPageAppliesZoomRule() {
        let services = makeServices()
        services.sites.set(SiteRule(zoom: 1.5), forKey: "example.com")
        let page = Page("", services: services)
        page.web.loadHTMLString("<p>x</p>", baseURL: URL(string: "https://example.com"))
        page.applyZoom()
        XCTAssertEqual(page.web.pageZoom, 1.5)
        page.web.loadHTMLString("<p>x</p>", baseURL: URL(string: "https://other.org"))
        page.applyZoom()
        XCTAssertEqual(page.web.pageZoom, 1.0)
    }

    func testDarkScriptIsInjectedOnlyWhenRuleIsOn() async {
        let services = makeServices()
        services.sites.set(SiteRule(forceDark: true, blockScripts: true), forKey: "example.com")
        let page = Page("", services: services)
        let prefs = WKWebpagePreferences()
        let request = URLRequest(url: URL(string: "https://example.com/")!)
        let (policy, out) = await page.decide(request: request, preferences: prefs)
        XCTAssertEqual(policy, .allow)
        XCTAssertFalse(out.allowsContentJavaScript)
        XCTAssertEqual(page.web.configuration.userContentController.userScripts.count, 1)
        let plain = await page.decide(request: URLRequest(url: URL(string: "https://other.org/")!), preferences: WKWebpagePreferences())
        XCTAssertTrue(plain.1.allowsContentJavaScript)
        XCTAssertEqual(page.web.configuration.userContentController.userScripts.count, 0)
    }
}

@MainActor
final class PairTests: XCTestCase {
    func testSplitIsClampedAndSwapKeepsBothPages() {
        let t = Tabs(services: makeServices())
        t.startPair(second: "")
        let pair = try! XCTUnwrap(t.pair)
        let a = pair.first.id, b = pair.second.id
        XCTAssertEqual(a, t.page.id, "the current tab is the first pane")
        pair.setSplit(0.01); XCTAssertEqual(pair.split, 0.25)
        pair.setSplit(0.99); XCTAssertEqual(pair.split, 0.75)
        pair.setSplit(0.6); XCTAssertEqual(pair.split, 0.6)
        pair.swap()
        XCTAssertEqual(pair.first.id, b); XCTAssertEqual(pair.second.id, a)
    }

    func testLayoutAxisAndDragFraction() {
        XCTAssertTrue(PairModel.sideBySide(width: 1024, height: 768))
        XCTAssertFalse(PairModel.sideBySide(width: 390, height: 844))
        XCTAssertTrue(PairModel.sideBySide(width: 834, height: 1194, roomy: true), "iPad portrait still goes side by side")
        XCTAssertEqual(PairModel.fraction(offset: 100, length: 400), 0.25)
        XCTAssertEqual(PairModel.fraction(offset: 10, length: 0), 0.5)
    }

    func testStartingAgainReusesPairAndEndClearsIt() {
        let t = Tabs(services: makeServices())
        t.startPair(second: "")
        let first = t.pair
        t.startPair(second: "")
        XCTAssertTrue(first === t.pair)
        t.endPair()
        XCTAssertNil(t.pair)
    }

    func testIncomingLinksRoute() {
        let t = Tabs(services: makeServices())
        let url = URL(string: "https://example.com")!
        t.open(IncomingLink(url: url, destination: .tab))
        XCTAssertEqual(t.pages.count, 2)
        t.open(IncomingLink(url: url, destination: .pair))
        XCTAssertNotNil(t.pair)
    }

    func testServicesQueueIncomingLinks() {
        let s = makeServices()
        s.receive(URL(string: "https://example.com")!, in: .float)
        XCTAssertEqual(s.incoming.count, 1)
        XCTAssertEqual(s.incoming[0].destination, .float)
    }
}

final class FloatPrefsTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testOpacityNeverLeavesTheRange() {
        XCTAssertEqual(FloatPrefs.clampOpacity(0), 0.2)
        XCTAssertEqual(FloatPrefs.clampOpacity(5), 1.0)
        XCTAssertEqual(FloatPrefs.clampOpacity(0.5), 0.5)
    }

    func testSavedFrameIsKeptWhenOnScreen() {
        var p = FloatPrefs()
        p.remember(CGRect(x: 100, y: 120, width: 500, height: 400))
        XCTAssertEqual(p.resolvedFrame(screens: [screen]), CGRect(x: 100, y: 120, width: 500, height: 400))
    }

    func testOffScreenFrameFallsBackToTopRight() {
        var p = FloatPrefs()
        p.remember(CGRect(x: 9000, y: 9000, width: 500, height: 400))
        let r = p.resolvedFrame(screens: [screen])
        XCTAssertTrue(screen.contains(r))
        XCTAssertEqual(r.size, FloatPrefs.defaultSize)
        XCTAssertEqual(FloatPrefs().resolvedFrame(screens: [screen]), r)
    }

    func testTinySavedFrameGrowsToMinimum() {
        var p = FloatPrefs()
        p.remember(CGRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertEqual(p.resolvedFrame(screens: [screen]).size, FloatPrefs.minSize)
    }

    func testPersistence() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertEqual(FloatPrefs.load(defaults), FloatPrefs())
        var p = FloatPrefs()
        p.opacity = 0.4; p.clickThrough = true; p.remember(CGRect(x: 1, y: 2, width: 300, height: 220))
        p.save(defaults)
        XCTAssertEqual(FloatPrefs.load(defaults), p)
        defaults.set(try! JSONEncoder().encode(FloatPrefs(opacity: 0.0)), forKey: FloatPrefs.key)
        XCTAssertEqual(FloatPrefs.load(defaults).opacity, 0.2, "a hand-edited value is clamped")
    }
}
