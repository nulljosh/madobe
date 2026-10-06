import SwiftUI
import WebKit

/// What one site is allowed to do in Madobe. Stored on the device, applied through WebKit.
struct SiteRule: Codable, Equatable {
    static let zoomRange = 0.5...2.0

    var zoom = 1.0
    var forceDark = false
    var blockImages = false
    var blockScripts = false
    var blockPopups = false

    var isDefault: Bool { self == SiteRule() }

    /// Zoom kept inside the range the slider offers, whatever a hand-edited file says.
    var pageZoom: Double { min(max(zoom, SiteRule.zoomRange.lowerBound), SiteRule.zoomRange.upperBound) }

    /// A page may open a new window when it is a real link tap, or when pop-ups are not blocked.
    func allowsNewWindow(userTappedLink: Bool) -> Bool { userTappedLink || !blockPopups }

    /// Injected at document start: flips the page to a dark look and flips pictures back.
    static let darkScript = """
    (function () {
      var s = document.createElement('style');
      s.id = 'madobe-dark';
      s.textContent = 'html{filter:invert(1) hue-rotate(180deg) !important;background:#fff !important}' +
        'img,picture,video,canvas,svg image{filter:invert(1) hue-rotate(180deg) !important}';
      (document.head || document.documentElement).appendChild(s);
    })();
    """
}

enum SiteKey {
    /// The key a site's rule is stored under: lower case, no trailing dot, no leading "www.".
    static func normalise(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        if h.hasPrefix("www."), h.count > 4 { h.removeFirst(4) }
        return h
    }

    /// The key for a web address, or nil for anything that is not an http(s) page with a host.
    static func key(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else { return nil }
        return normalise(host)
    }

    /// "docs.example.com" then "example.com": a rule on a site covers its subdomains.
    static func chain(_ key: String) -> [String] {
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return [key] }
        return (0..<(parts.count - 1)).map { parts[$0...].joined(separator: ".") }
    }
}

/// Per-site settings in one small JSON file. Nothing here is sent anywhere.
@MainActor
final class SiteRules: ObservableObject {
    @Published private(set) var rules: [String: SiteRule] = [:]
    private let file: URL
    /// Called after the stored rules change.
    var onChange: (() -> Void)?

    init(directory: URL) {
        file = directory.appendingPathComponent("site-rules.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: SiteRule].self, from: data) {
            rules = saved
        }
    }

    /// The rule for this key or its nearest parent site, else the defaults.
    func rule(forKey key: String) -> SiteRule {
        for k in SiteKey.chain(key) { if let r = rules[k] { return r } }
        return SiteRule()
    }

    func rule(for url: URL?) -> SiteRule {
        SiteKey.key(for: url).map(rule(forKey:)) ?? SiteRule()
    }

    /// Saves the rule under its own key. A rule equal to the defaults is removed instead of stored.
    func set(_ rule: SiteRule, forKey key: String) {
        let key = SiteKey.normalise(key)
        guard !key.isEmpty else { return }
        if rule.isDefault { rules.removeValue(forKey: key) } else { rules[key] = rule }
        if let data = try? JSONEncoder().encode(rules) { try? data.write(to: file, options: .atomic) }
        onChange?()
    }

    func reset(key: String) { set(SiteRule(), forKey: key) }

    /// WebKit content-blocker JSON that drops images for every site with "block images" on.
    /// Nil when no site needs it.
    static func imageRulesJSON(_ rules: [String: SiteRule]) -> String? {
        let hosts = rules.filter { $0.value.blockImages }.keys.sorted().map { "*" + $0 }
        guard !hosts.isEmpty else { return nil }
        let rule: [[String: Any]] = [[
            "trigger": ["url-filter": ".*", "resource-type": ["image"], "if-domain": hosts],
            "action": ["type": "block"],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: rule) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Keeps one content rule list attached to every web view, swapping it when the rules change.
@MainActor
final class RuleListHost {
    private let identifier: String
    private var list: WKContentRuleList?
    private let views = NSHashTable<WKWebView>.weakObjects()
    private let attached = NSMapTable<WKWebView, WKContentRuleList>.weakToStrongObjects()
    private var generation = 0

    init(identifier: String) { self.identifier = identifier }

    func register(_ web: WKWebView) {
        views.add(web)
        attach(to: web)
    }

    /// Compiles `json` (or removes the list when nil) and attaches the result everywhere.
    func update(json: String?) async {
        generation += 1
        let mine = generation
        let store = WKContentRuleListStore.default()
        var compiled: WKContentRuleList?
        if let json { compiled = try? await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) }
        guard mine == generation else { return }
        list = compiled
        for web in views.allObjects { attach(to: web) }
    }

    func setAttached(_ on: Bool, json: String?) async {
        await update(json: on ? json : nil)
    }

    private func attach(to web: WKWebView) {
        let controller = web.configuration.userContentController
        if let old = attached.object(forKey: web) { controller.remove(old); attached.removeObject(forKey: web) }
        if let list { controller.add(list); attached.setObject(list, forKey: web) }
    }
}

struct SiteRulesView: View {
    @ObservedObject var page: Page
    @ObservedObject var sites: SiteRules
    @Environment(\.dismiss) private var dismiss
    @State private var rule = SiteRule()
    @State private var before = SiteRule()
    @State private var key = ""

    var body: some View {
        NavigationStack {
            Form {
                if key.isEmpty {
                    ContentUnavailableView("No site open", systemImage: "globe",
                                           description: Text("Open a web page, then choose Site Rules."))
                } else {
                    Section {
                        VStack(alignment: .leading) {
                            Text("Page zoom \(Int((rule.zoom * 100).rounded()))%")
                            Slider(value: $rule.zoom, in: SiteRule.zoomRange, step: 0.1)
                                .accessibilityLabel("Page zoom")
                        }
                        Toggle("Dark appearance", isOn: $rule.forceDark)
                        Toggle("Block images", isOn: $rule.blockImages)
                        Toggle("Block scripts", isOn: $rule.blockScripts)
                        Toggle("Block pop-ups", isOn: $rule.blockPopups)
                    } header: {
                        Text(key)
                    } footer: {
                        Text("These settings stay on this device and also cover subdomains of \(key).")
                    }
                    Section { Button("Reset This Site", role: .destructive) { rule = SiteRule() }.disabled(rule.isDefault) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Site Rules")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { finish() } } }
            .onChange(of: rule) { _, new in
                guard !key.isEmpty else { return }
                sites.set(new, forKey: key)
                page.applyZoom()
            }
        }
        .onAppear {
            key = SiteKey.key(for: page.web.url) ?? ""
            rule = sites.rule(forKey: key)
            before = rule
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func finish() {
        let changed = rule != before
        dismiss()
        if changed { page.web.reload() }
    }
}
