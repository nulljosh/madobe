import SwiftUI
import WebKit

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo, brave, ecosia, startpage, google
    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .brave: "Brave Search"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .google: "Google"
        }
    }

    private var base: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/"
        case .brave: "https://search.brave.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        case .startpage: "https://www.startpage.com/do/search"
        case .google: "https://www.google.com/search"
        }
    }

    func searchURL(_ query: String) -> URL? {
        var c = URLComponents(string: base)!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url
    }
}

/// Turns what the user typed into a URL: a scheme-less host gets https, anything else becomes a search.
func resolve(_ input: String, engine: SearchEngine = .duckDuckGo) -> URL? {
    let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.contains("://"), let u = URL(string: s) { return u }
    if !s.contains(" "), s.contains("."), let u = URL(string: "https://" + s) { return u }
    return engine.searchURL(s)
}

/// Hands a non-web link (mailto:, tel:, an app's own scheme) to the system.
func openExternally(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

@MainActor
final class Page: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let web: WKWebView
    let isPrivate: Bool
    private let services: Services
    @Published var address = ""
    @Published var title = ""
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var canBack = false
    @Published var canForward = false
    @Published var secure = false
    /// A link asked for a new window (target=_blank). The tab list opens it as a tab.
    var onNewTab: ((URL) -> Void)?
    /// Something worth saving changed (a page finished loading).
    var onChange: (() -> Void)?

    /// `start` nil opens the homepage, "" opens nothing.
    init(_ start: String? = nil, services: Services = .shared, isPrivate: Bool = false) {
        self.services = services
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : services.dataStore
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        services.blocker.register(web)
        services.siteBlocker.register(web)
        go(start ?? services.settings.homepage)
    }

    /// Applies the zoom from this site's rule to the page on screen.
    func applyZoom() { web.pageZoom = services.sites.rule(for: web.url).pageZoom }

    func go(_ input: String) {
        guard let u = resolve(input, engine: services.settings.engine) else { return }
        web.load(URLRequest(url: u))
    }

    private func sync() {
        address = web.url?.absoluteString ?? address
        title = web.title.flatMap { $0.isEmpty ? nil : $0 } ?? web.url?.host() ?? "New Tab"
        loading = web.isLoading
        canBack = web.canGoBack
        canForward = web.canGoForward
        secure = web.url?.scheme == "https" && web.hasOnlySecureContent
    }

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { errorMessage = nil; sync() }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        sync()
        if !isPrivate, let url = w.url, url.scheme == "https" || url.scheme == "http" {
            services.library.record(title: title, url: url.absoluteString)
        }
        onChange?()
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        sync()
        if (e as NSError).code != NSURLErrorCancelled { errorMessage = e.localizedDescription }
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        webView(w, didFail: n, withError: e)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        errorMessage = "This page stopped responding. Reload to try again."
    }

    /// Web links stay in the tab; mailto:, tel: and other schemes go to the system.
    /// Page loads also pick up the site's rules: scripts on or off, a dark look, zoom.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        await decide(request: action.request, mainFrame: action.targetFrame?.isMainFrame ?? true, preferences: preferences)
    }

    /// The decision behind the delegate call, kept apart so tests can run it without a real navigation.
    func decide(request: URLRequest, mainFrame: Bool = true,
                preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = request.url, let scheme = url.scheme?.lowercased() else { return (.allow, preferences) }
        if ["http", "https"].contains(scheme) {
            if mainFrame { applyRules(for: url, to: preferences) }
            return (.allow, preferences)
        }
        if ["about", "blob", "data", "file"].contains(scheme) { return (.allow, preferences) }
        openExternally(url)
        return (.cancel, preferences)
    }

    private func applyRules(for url: URL, to preferences: WKWebpagePreferences) {
        let rule = services.sites.rule(for: url)
        preferences.allowsContentJavaScript = !rule.blockScripts
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        if rule.forceDark {
            controller.addUserScript(WKUserScript(source: SiteRule.darkScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web.pageZoom = rule.pageZoom
    }

    func webView(_ w: WKWebView, createWebViewWith config: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let rule = services.sites.rule(for: w.url)
        guard rule.allowsNewWindow(userTappedLink: action.navigationType == .linkActivated) else { return nil }
        if let url = action.request.url { onNewTab?(url) }
        return nil
    }
}

/// The open tabs. Normal tabs are restored on the next launch; private tabs never are.
@MainActor
final class Tabs: ObservableObject {
    @Published var pages: [Page]
    @Published var current: UUID
    /// Two pages in one window (iPhone and iPad). Nil when not pairing.
    @Published var pair: PairModel?
    private let services: Services
    private let defaults: UserDefaults?
    static let restoreKey = "tabs.urls"

    init(services: Services = .shared, restore: Bool = false, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = restore ? defaults : nil
        var start: [Page] = []
        if restore, let saved = defaults.stringArray(forKey: Tabs.restoreKey), !saved.isEmpty {
            start = saved.map { Page($0, services: services) }
        }
        if start.isEmpty { start = [Page(services: services)] }
        pages = start
        current = start[0].id
        for p in start { wire(p) }
    }

    var page: Page { pages.first { $0.id == current } ?? pages[0] }

    private func wire(_ p: Page) {
        p.onNewTab = { [weak self] url in self?.add(url.absoluteString) }
        p.onChange = { [weak self] in self?.save() }
    }

    func add(_ start: String? = nil, isPrivate: Bool = false) {
        let p = Page(start, services: services, isPrivate: isPrivate)
        wire(p)
        pages.append(p)
        current = p.id
        save()
    }

    func close(_ p: Page) {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == p.id }) else { return }
        pages.remove(at: i)
        if current == p.id { current = pages[min(i, pages.count - 1)].id }
        save()
    }

    /// Opens a link that arrived from outside the window. Float is handled by the Mac window code.
    func open(_ link: IncomingLink) {
        switch link.destination {
        case .tab, .float: add(link.url.absoluteString)
        case .pair: startPair(second: link.url.absoluteString)
        }
    }

    /// Splits the window: the current tab on one side, `second` (or the homepage) on the other.
    func startPair(second: String? = nil) {
        if let pair {
            if let second { pair.second.go(second) }
            return
        }
        let p = Page(second, services: services)
        p.onNewTab = { [weak p] url in p?.go(url.absoluteString) }
        pair = PairModel(first: page, second: p)
    }

    func endPair() { pair = nil }

    private func save() {
        guard let defaults else { return }
        let urls = pages.filter { !$0.isPrivate }.compactMap { $0.web.url?.absoluteString }
        defaults.set(urls, forKey: Tabs.restoreKey)
    }
}

#if os(macOS)
struct WebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
#else
struct WebView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
#endif
