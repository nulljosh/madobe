import SwiftUI
import WebKit

/// How the Float window looks and where it sits. Pure data, saved in UserDefaults.
struct FloatPrefs: Codable, Equatable {
    static let opacityRange = 0.2...1.0
    static let minSize = CGSize(width: 300, height: 220)
    static let defaultSize = CGSize(width: 440, height: 320)
    static let key = "float.prefs"

    var opacity = 0.85
    var clickThrough = false
    /// x, y, width, height in screen points.
    var frame: [Double]?

    /// Opacity kept between 20% and 100%, so the window can never vanish.
    static func clampOpacity(_ value: Double) -> Double {
        min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    var savedRect: CGRect? {
        guard let f = frame, f.count == 4 else { return nil }
        return CGRect(x: f[0], y: f[1], width: f[2], height: f[3])
    }

    mutating func remember(_ rect: CGRect) { frame = [rect.minX, rect.minY, rect.width, rect.height].map { Double($0) } }

    /// The saved rectangle if it still lands on a screen, else the top right corner of the first one.
    func resolvedFrame(screens: [CGRect]) -> CGRect {
        let fallback = screens.first ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if var r = savedRect {
            r.size.width = max(r.width, FloatPrefs.minSize.width)
            r.size.height = max(r.height, FloatPrefs.minSize.height)
            let visible = screens.contains { s in
                let hit = s.intersection(r)
                return hit.width >= 120 && hit.height >= 60
            }
            if visible { return r }
        }
        let size = FloatPrefs.defaultSize
        return CGRect(x: fallback.maxX - size.width - 24, y: fallback.maxY - size.height - 24,
                      width: size.width, height: size.height)
    }

    static func load(_ defaults: UserDefaults) -> FloatPrefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(FloatPrefs.self, from: data) else {
            return FloatPrefs()
        }
        var fixed = p
        fixed.opacity = clampOpacity(p.opacity)
        return fixed
    }

    func save(_ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: FloatPrefs.key) }
    }
}

#if os(macOS)
import AppKit

/// The window itself: always above other apps, on every Space, and it never takes focus on its own.
final class FloatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatModel: ObservableObject {
    let page: Page
    private let defaults: UserDefaults
    @Published var opacity: Double { didSet { opacity = FloatPrefs.clampOpacity(opacity); changed() } }
    @Published var clickThrough: Bool { didSet { changed() } }
    var onChange: (() -> Void)?

    init(page: Page, prefs: FloatPrefs, defaults: UserDefaults) {
        self.page = page
        self.defaults = defaults
        opacity = prefs.opacity
        clickThrough = prefs.clickThrough
    }

    private func changed() { onChange?() }
}

/// Opens, moves and closes the Float window, and owns the menu bar item that always gets you back.
@MainActor
final class FloatController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = FloatController()

    @Published private(set) var isOpen = false
    @Published private(set) var clickThrough = false
    private var panel: FloatPanel?
    private var model: FloatModel?
    private var prefs = FloatPrefs()
    private var defaults: UserDefaults = .standard
    private var statusItem: NSStatusItem?

    /// Shows the window on `address`, or moves an open one to it. Does not activate the app.
    func open(_ address: String, services: Services) {
        defaults = services.defaults
        if let model, let panel {
            model.page.go(address)
            panel.orderFrontRegardless()
            return
        }
        prefs = FloatPrefs.load(defaults)
        let page = Page(address, services: services)
        page.onNewTab = { [weak page] url in page?.go(url.absoluteString) }
        let model = FloatModel(page: page, prefs: prefs, defaults: defaults)
        model.onChange = { [weak self] in self?.apply() }
        self.model = model

        let screens = NSScreen.screens.map(\.visibleFrame)
        let panel = FloatPanel(contentRect: prefs.resolvedFrame(screens: screens),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.minSize = FloatPrefs.minSize
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatView(model: model, controller: self))
        self.panel = panel
        apply()
        panel.orderFrontRegardless()
        isOpen = true
        makeStatusItem()
    }

    func close() { panel?.close() }

    func setClickThrough(_ on: Bool) { model?.clickThrough = on }

    func toggleClickThrough() { setClickThrough(!clickThrough) }

    func setOpacity(_ value: Double) { model?.opacity = value }

    /// Pushes the model's look onto the window and saves it.
    private func apply() {
        guard let model, let panel else { return }
        panel.alphaValue = model.opacity
        panel.ignoresMouseEvents = model.clickThrough
        clickThrough = model.clickThrough
        prefs.opacity = model.opacity
        prefs.clickThrough = model.clickThrough
        prefs.save(defaults)
        statusItem?.button?.image = statusImage()
    }

    private func statusImage() -> NSImage? {
        NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Madobe Float")
    }

    // MARK: Window events

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }

    private func rememberFrame() {
        guard let panel else { return }
        prefs.remember(panel.frame)
        prefs.save(defaults)
    }

    func windowWillClose(_ notification: Notification) {
        rememberFrame()
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
        model = nil
        isOpen = false
        clickThrough = false
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: Menu bar item

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusImage()
        item.button?.toolTip = "Madobe Float"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }
}

extension FloatController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let through = NSMenuItem(title: "Click-Through", action: #selector(toggleFromMenu), keyEquivalent: "")
        through.target = self
        through.state = clickThrough ? .on : .off
        menu.addItem(through)
        for percent in [100, 75, 50, 30] {
            let item = NSMenuItem(title: "Opacity \(percent)%", action: #selector(opacityFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = Int((model?.opacity ?? 0) * 100 + 0.5) == percent ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let close = NSMenuItem(title: "Close Float Window", action: #selector(closeFromMenu), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
    }

    @objc private func toggleFromMenu() { toggleClickThrough() }
    @objc private func opacityFromMenu(_ item: NSMenuItem) { setOpacity(Double(item.tag) / 100) }
    @objc private func closeFromMenu() { close() }
}

struct FloatView: View {
    @ObservedObject var model: FloatModel
    @ObservedObject var controller: FloatController
    @ObservedObject private var page: Page
    @FocusState private var editing: Bool

    init(model: FloatModel, controller: FloatController) {
        self.model = model
        self.controller = controller
        _page = ObservedObject(wrappedValue: model.page)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button { page.web.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!page.canBack).accessibilityLabel("Back")
                    Button { page.web.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!page.canForward).accessibilityLabel("Forward")
                    TextField("Search or enter address", text: $page.address)
                        .textFieldStyle(.plain)
                        .focused($editing)
                        .onSubmit { page.go(page.address); editing = false }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Button { if page.loading { page.web.stopLoading() } else { page.web.reload() } } label: {
                        Image(systemName: page.loading ? "xmark" : "arrow.clockwise")
                    }
                    .accessibilityLabel(page.loading ? "Stop" : "Reload")
                }
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled").accessibilityHidden(true)
                    Slider(value: $model.opacity, in: FloatPrefs.opacityRange)
                        .accessibilityLabel("Window opacity")
                    Text("\(Int((model.opacity * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    Toggle(isOn: $model.clickThrough) { Text("Click-through") }
                        .toggleStyle(.checkbox)
                        .help("Clicks pass through the window. Turn it off from the Madobe icon in the menu bar.")
                    Button { controller.close() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Close Float window")
                }
                .font(.footnote)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.top, 26).padding(.bottom, 6)
            .background(.bar)
            WebView(web: page.web)
        }
    }
}
#endif
