import SwiftUI
import WebKit

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

@main
struct FensterApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup { BrowserView() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
    }
}

/// Turns what the user typed into a URL: a scheme-less host gets https, anything else becomes a search.
func resolve(_ input: String) -> URL? {
    let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.contains("://"), let u = URL(string: s) { return u }
    if !s.contains(" "), s.contains("."), let u = URL(string: "https://" + s) { return u }
    var c = URLComponents(string: "https://duckduckgo.com/")!
    c.queryItems = [URLQueryItem(name: "q", value: s)]
    return c.url
}

@MainActor
final class Page: NSObject, ObservableObject, Identifiable, WKNavigationDelegate {
    let id = UUID()
    let web = WKWebView()
    @Published var address = ""
    @Published var title = ""
    @Published var loading = false
    @Published var canBack = false
    @Published var canForward = false

    init(_ start: String = "https://duckduckgo.com") {
        super.init()
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        go(start)
    }

    func go(_ input: String) {
        guard let u = resolve(input) else { return }
        web.load(URLRequest(url: u))
    }

    private func sync() {
        address = web.url?.absoluteString ?? address
        title = web.title.flatMap { $0.isEmpty ? nil : $0 } ?? web.url?.host() ?? "New Tab"
        loading = web.isLoading
        canBack = web.canGoBack
        canForward = web.canGoForward
    }
    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { sync() }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { sync() }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { sync() }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { sync() }
}

/// Tab list. ponytail: in-memory only, no restore across launches; persist URLs when that matters.
@MainActor
final class Tabs: ObservableObject {
    @Published var pages: [Page] = [Page()]
    @Published var current: UUID
    init() { current = UUID(); current = pages[0].id }
    var page: Page { pages.first { $0.id == current } ?? pages[0] }
    func add() { let p = Page(); pages.append(p); current = p.id }
    func close(_ p: Page) {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == p.id }) else { return }
        pages.remove(at: i)
        if current == p.id { current = pages[min(i, pages.count - 1)].id }
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

struct BrowserView: View {
    @StateObject private var tabs = Tabs()
    var body: some View {
        #if os(iOS)
        NavigationStack { PageView(tabs: tabs, page: tabs.page).id(tabs.current) }
        #else
        PageView(tabs: tabs, page: tabs.page).id(tabs.current)
        #endif
    }
}

struct PageView: View {
    @ObservedObject var tabs: Tabs
    @ObservedObject var page: Page
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { page.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canBack).keyboardShortcut("[", modifiers: .command)
                Button { page.web.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!page.canForward).keyboardShortcut("]", modifiers: .command)
                TextField("Search or enter address", text: $page.address)
                    .textFieldStyle(.roundedBorder)
                    .focused($editing)
                    .onSubmit { page.go(page.address); editing = false }
                    #if os(iOS)
                    .keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                Button { if page.loading { page.web.stopLoading() } else { page.web.reload() } } label: {
                    Image(systemName: page.loading ? "xmark" : "arrow.clockwise")
                }.keyboardShortcut("r", modifiers: .command)
                Button { tabs.add() } label: { Image(systemName: "plus") }
                    .keyboardShortcut("t", modifiers: .command)
                Button { tabs.close(page) } label: { Image(systemName: "xmark.square") }
                    .keyboardShortcut("w", modifiers: .command).disabled(tabs.pages.count == 1)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.bar)
            if tabs.pages.count > 1 { TabStrip(tabs: tabs) }
            WebView(web: page.web).ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(page.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            Text(page.title).lineLimit(1).frame(maxWidth: 160)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tabs.current == page.id ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
}
