import SwiftUI
import WebKit

@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults
    var onBlockChange: ((Bool) -> Void)?

    @Published var engine: SearchEngine { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    @Published var homepage: String { didSet { defaults.set(homepage, forKey: "homepage") } }
    @Published var blockTrackers: Bool {
        didSet {
            defaults.set(blockTrackers, forKey: "blockTrackers")
            onBlockChange?(blockTrackers)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = SearchEngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .duckDuckGo
        homepage = defaults.string(forKey: "homepage") ?? "https://duckduckgo.com"
        blockTrackers = defaults.object(forKey: "blockTrackers") as? Bool ?? true
    }
}

/// Blocks third-party requests to well-known ad and tracking hosts, using WebKit's own content
/// rule lists. The rules compile once, then attach to every page and detach when switched off.
@MainActor
final class ContentBlocker {
    private(set) var enabled: Bool
    private var list: WKContentRuleList?
    private let views = NSHashTable<WKWebView>.weakObjects()
    private let attached = NSMapTable<WKWebView, WKContentRuleList>.weakToStrongObjects()

    static let blockedDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "adservice.google.com", "connect.facebook.net", "scorecardresearch.com", "quantserve.com",
        "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "adnxs.com", "rubiconproject.com",
        "pubmatic.com", "openx.net", "amazon-adsystem.com", "hotjar.com", "mixpanel.com",
        "fullstory.com", "moatads.com", "adsrvr.org", "advertising.com", "2mdn.net",
        "casalemedia.com", "bluekai.com", "krxd.net", "demdex.net", "everesttech.net",
        "mathtag.com", "bidswitch.net", "smartadserver.com", "yieldmo.com", "teads.tv",
        "zedo.com", "serving-sys.com", "adform.net", "lijit.com", "sharethrough.com", "3lift.com",
    ]

    /// WebKit content-blocker JSON: block third-party loads from each listed host.
    static var rulesJSON: String {
        let rules: [[String: Any]] = blockedDomains.map { domain in
            [
                "trigger": [
                    "url-filter": domain.replacingOccurrences(of: ".", with: "\\."),
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(data: data, encoding: .utf8)!
    }

    init(enabled: Bool) {
        self.enabled = enabled
        Task { await compile() }
    }

    func register(_ web: WKWebView) {
        views.add(web)
        apply(to: web)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        for web in views.allObjects { apply(to: web) }
    }

    private func apply(to web: WKWebView) {
        let controller = web.configuration.userContentController
        if let old = attached.object(forKey: web) { controller.remove(old); attached.removeObject(forKey: web) }
        if enabled, let list { controller.add(list); attached.setObject(list, forKey: web) }
    }

    private func compile() async {
        let store = WKContentRuleListStore.default()
        list = try? await store?.compileContentRuleList(forIdentifier: "madobe-trackers",
                                                         encodedContentRuleList: ContentBlocker.rulesJSON)
        for web in views.allObjects { apply(to: web) }
    }
}

/// Everything the pages and screens share.
@MainActor
final class Services: ObservableObject {
    static let shared = Services()

    enum Sheet: String, Identifiable {
        case bookmarks, history, settings, siteRules
        var id: String { rawValue }
    }

    let library: Library
    let settings: Settings
    let blocker: ContentBlocker
    let sites: SiteRules
    let siteBlocker = RuleListHost(identifier: "madobe-sites")
    let defaults: UserDefaults
    let dataStore: WKWebsiteDataStore
    @Published var sheet: Sheet?
    @Published var finding = false
    /// Bumped by the Open Location command; the page focuses its address bar when this changes.
    @Published var addressFocusTick = 0

    /// Links waiting to be opened: from Shortcuts, the Share extension or a menu. The window drains them.
    @Published var incoming: [IncomingLink] = []

    func receive(_ url: URL, in destination: IncomingLink.Destination = .tab) {
        incoming.append(IncomingLink(url: url, destination: destination))
    }

    init(directory: URL = Library.defaultDirectory, defaults: UserDefaults = Profile.defaults,
         dataStore: WKWebsiteDataStore? = nil) {
        let settings = Settings(defaults: defaults)
        self.defaults = defaults
        self.dataStore = dataStore ?? Profile.dataStore
        self.library = Library(directory: directory)
        self.sites = SiteRules(directory: directory)
        self.settings = settings
        self.blocker = ContentBlocker(enabled: settings.blockTrackers)
        settings.onBlockChange = { [blocker] on in blocker.setEnabled(on) }
        let refresh = { [sites, siteBlocker] in
            let json = SiteRules.imageRulesJSON(sites.rules)
            Task { await siteBlocker.update(json: json) }
        }
        sites.onChange = refresh
        refresh()
    }
}

struct IncomingLink: Equatable, Identifiable {
    enum Destination: Equatable { case tab, pair, float }
    let id = UUID()
    let url: URL
    var destination: Destination
}

/// A named throwaway profile (MADOBE_PROFILE=name) keeps tests and QA runs away from real data.
enum Profile {
    static var name: String? {
        let n = ProcessInfo.processInfo.environment["MADOBE_PROFILE"]
        return n?.isEmpty == false ? n : nil
    }

    static var defaults: UserDefaults {
        name.flatMap { UserDefaults(suiteName: "com.nulljosh.lucarne.profile.\($0)") } ?? .standard
    }

    @MainActor static var dataStore: WKWebsiteDataStore {
        guard let name else { return .default() }
        var bytes = Array(name.utf8.prefix(16))
        while bytes.count < 16 { bytes.append(0x4d) }
        return WKWebsiteDataStore(forIdentifier: UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                                              bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])))
    }
}
