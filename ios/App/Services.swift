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
        controller.removeAllContentRuleLists()
        if enabled, let list { controller.add(list) }
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
        case bookmarks, history, settings
        var id: String { rawValue }
    }

    let library: Library
    let settings: Settings
    let blocker: ContentBlocker
    @Published var sheet: Sheet?
    @Published var finding = false
    /// Bumped by the Open Location command; the page focuses its address bar when this changes.
    @Published var addressFocusTick = 0

    init(directory: URL = Library.defaultDirectory, defaults: UserDefaults = .standard) {
        let settings = Settings(defaults: defaults)
        self.library = Library(directory: directory)
        self.settings = settings
        self.blocker = ContentBlocker(enabled: settings.blockTrackers)
        settings.onBlockChange = { [blocker] on in blocker.setEnabled(on) }
    }
}
