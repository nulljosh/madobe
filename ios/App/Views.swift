import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var services: Services

    var body: some View {
        Group {
            #if os(iOS)
            if let pair = tabs.pair {
                PairView(tabs: tabs, pair: pair)
            } else {
                NavigationStack { PageView(tabs: tabs, page: tabs.page, services: services).id(tabs.current) }
            }
            #else
            PageView(tabs: tabs, page: tabs.page, services: services).id(tabs.current)
            #endif
        }
        .onAppear { drain() }
        .onChange(of: services.incoming) { _, _ in drain() }
        .sheet(item: $services.sheet) { sheet in
            switch sheet {
            case .bookmarks: BookmarksView(tabs: tabs, library: services.library)
            case .history: HistoryView(tabs: tabs, library: services.library)
            case .settings: SettingsView(settings: services.settings, library: services.library)
            case .siteRules: SiteRulesView(page: tabs.page, sites: services.sites)
            }
        }
    }

    /// Opens links that arrived from Shortcuts or the Share extension.
    private func drain() {
        let links = services.incoming
        guard !links.isEmpty else { return }
        services.incoming = []
        for link in links {
            #if os(macOS)
            if link.destination == .float { FloatController.shared.open(link.url.absoluteString, services: services); continue }
            #endif
            tabs.open(link)
        }
    }
}

struct PageView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var page: Page
    @ObservedObject var services: Services
    @ObservedObject private var library: Library
    @ObservedObject private var settings: Settings
    @FocusState private var editing: Bool

    init(tabs: Tabs, page: Page, services: Services) {
        self.tabs = tabs
        self.page = page
        self.services = services
        _library = ObservedObject(wrappedValue: services.library)
        _settings = ObservedObject(wrappedValue: services.settings)
    }

    private var bookmarked: Bool { library.isBookmarked(page.address) }

    var body: some View {
        VStack(spacing: 0) {
            chrome
            if tabs.pages.count > 1 { TabStrip(tabs: tabs) }
            if services.finding { FindBar(page: page, isShowing: $services.finding) }
            if let error = page.errorMessage {
                Text(error).font(.callout).padding().accessibilityLabel("Page error: " + error)
            }
            WebView(web: page.web).ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(page.title)
        .onChange(of: services.addressFocusTick) { _, _ in editing = true }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Like every browser: tapping the address selects all of it, so typing replaces it.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
        #endif
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            Button { page.web.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!page.canBack).keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
            Button { page.web.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!page.canForward).keyboardShortcut("]", modifiers: .command)
                .accessibilityLabel("Forward")
            addressField
            Button { if page.loading { page.web.stopLoading() } else { page.web.reload() } } label: {
                Image(systemName: page.loading ? "xmark" : "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel(page.loading ? "Stop" : "Reload")
            Button {
                library.toggleBookmark(title: page.title, url: page.address)
            } label: {
                Image(systemName: bookmarked ? "star.fill" : "star").foregroundStyle(bookmarked ? .yellow : .primary)
            }
            .disabled(page.address.isEmpty)
            .accessibilityLabel(bookmarked ? "Remove bookmark" : "Add bookmark")
            menu
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(page.isPrivate ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.bar))
    }

    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: addressIcon).foregroundStyle(.secondary).font(.footnote)
                .accessibilityLabel(page.secure ? "Secure connection" : "Address")
            TextField(page.isPrivate ? "Private tab: search or enter address" : "Search or enter address",
                      text: $page.address)
                .textFieldStyle(.plain)
                .focused($editing)
                .onSubmit { page.go(page.address); editing = false }
                #if os(iOS)
                .keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var addressIcon: String {
        if page.isPrivate { return "eyeglasses" }
        if page.secure { return "lock.fill" }
        if page.address.hasPrefix("http://") { return "exclamationmark.triangle" }
        return "magnifyingglass"
    }

    private var menu: some View {
        Menu {
            Button { tabs.add() } label: { Label("New Tab", systemImage: "plus") }
            Button { tabs.add(isPrivate: true) } label: { Label("New Private Tab", systemImage: "eyeglasses") }
            Button { tabs.close(page) } label: { Label("Close Tab", systemImage: "xmark.square") }
                .disabled(tabs.pages.count == 1)
            Divider()
            Button { services.finding = true } label: { Label("Find in Page", systemImage: "magnifyingglass") }
            Toggle(isOn: $settings.blockTrackers) { Label("Block Trackers and Ads", systemImage: "shield") }
            Button { services.sheet = .siteRules } label: { Label("Site Rules", systemImage: "slider.horizontal.3") }
                .disabled(SiteKey.key(for: page.web.url) == nil)
            #if os(iOS)
            Button { tabs.startPair() } label: { Label("Pair: Two Pages at Once", systemImage: "rectangle.split.2x1") }
            #else
            Button { FloatController.shared.open(page.address, services: services) } label: {
                Label("Float This Page", systemImage: "pip")
            }
            .disabled(page.address.isEmpty)
            #endif
            if let url = page.web.url {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { openExternally(url) } label: { Label("Open in Default Browser", systemImage: "safari") }
            }
            Divider()
            Button { services.sheet = .bookmarks } label: { Label("Bookmarks", systemImage: "star") }
            Button { services.sheet = .history } label: { Label("History", systemImage: "clock") }
            Button { services.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
    }
}

struct TabStrip: View {
    @ObservedObject var tabs: Tabs
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs.pages) { p in TabChip(tabs: tabs, page: p) }
            }.padding(.horizontal, 8).padding(.vertical, 6)
        }
        .background(.bar)
    }
}

struct TabChip: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var page: Page
    var body: some View {
        Button { tabs.current = page.id } label: {
            HStack(spacing: 4) {
                if page.isPrivate { Image(systemName: "eyeglasses").font(.caption) }
                Text(page.title).lineLimit(1).frame(maxWidth: 160)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tabs.current == page.id ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((page.isPrivate ? "Private tab, " : "Tab, ") + page.title)
    }
}

struct FindBar: View {
    @ObservedObject var page: Page
    @Binding var isShowing: Bool
    @State private var text = ""
    @State private var found: Bool?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in page", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { run(backwards: false) }
                #if os(iOS)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
            if found == false { Text("Not found").font(.footnote).foregroundStyle(.secondary) }
            Button { run(backwards: true) } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Previous match")
            Button { run(backwards: false) } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Next match")
            Button("Done") { isShowing = false }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
        .onAppear { focused = true }
    }

    private func run(backwards: Bool) {
        guard !text.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        Task { found = (try? await page.web.find(text, configuration: config))?.matchFound }
    }
}

struct BookmarksView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var items: [Bookmark] {
        filter.isEmpty ? library.bookmarks
            : library.bookmarks.filter { $0.title.localizedCaseInsensitiveContains(filter) || $0.url.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { b in
                    Button { tabs.page.go(b.url); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).lineLimit(1)
                            Text(b.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Delete", role: .destructive) { library.removeBookmarks([b]) } }
                }
                .onDelete { offsets in library.removeBookmarks(offsets.map { items[$0] }) }
            }
            .overlay {
                if library.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks yet", systemImage: "star",
                                           description: Text("Tap the star in the address bar to save a page."))
                }
            }
            .searchable(text: $filter)
            .navigationTitle("Bookmarks")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }
}

struct HistoryView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var confirmClear = false

    private var items: [HistoryItem] {
        filter.isEmpty ? library.history
            : library.history.filter { $0.title.localizedCaseInsensitiveContains(filter) || $0.url.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { h in
                    Button { tabs.page.go(h.url); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).lineLimit(1)
                            HStack {
                                Text(h.url).lineLimit(1)
                                Spacer()
                                Text(h.visited, format: .relative(presentation: .named))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in library.removeHistory(offsets.map { items[$0] }) }
            }
            .overlay {
                if library.history.isEmpty {
                    ContentUnavailableView("No history", systemImage: "clock",
                                           description: Text("Pages you visit show up here. Private tabs are never recorded."))
                }
            }
            .searchable(text: $filter)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { confirmClear = true }.disabled(library.history.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all browsing history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
        #endif
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    Picker("Search engine", selection: $settings.engine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                    }
                    LabeledContent("Homepage") {
                        TextField("Homepage", text: $settings.homepage)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                    }
                }
                Section {
                    Toggle("Block trackers and ads", isOn: $settings.blockTrackers)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Blocks third-party requests to well-known ad and tracking hosts. Private tabs also keep no history, cookies or cache.")
                }
                Section("Data") {
                    Button("Clear History") { library.clearHistory() }.disabled(library.history.isEmpty)
                    Button(cleared ? "Website Data Cleared" : "Clear Cookies and Website Data") {
                        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                                modifiedSince: .distantPast) { cleared = true }
                    }
                    .disabled(cleared)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}
