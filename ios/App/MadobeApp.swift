import SwiftUI

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

@main
struct MadobeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var services: Services
    @StateObject private var tabs: Tabs

    init() {
        let services = Services.shared
        _services = StateObject(wrappedValue: services)
        _tabs = StateObject(wrappedValue: Tabs(services: services, restore: true))
    }

    var body: some Scene {
        WindowGroup { BrowserView(tabs: tabs, services: services) }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { tabs.add() }.keyboardShortcut("t")
                Button("New Private Tab") { tabs.add(isPrivate: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close Tab") { tabs.close(tabs.page) }.keyboardShortcut("w").disabled(tabs.pages.count == 1)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Page") { services.finding = true }.keyboardShortcut("f")
            }
            CommandMenu("Bookmarks") {
                Button("Bookmark This Page") {
                    let page = tabs.page
                    services.library.toggleBookmark(title: page.title, url: page.address)
                }
                .keyboardShortcut("d")
                Button("Show Bookmarks") { services.sheet = .bookmarks }.keyboardShortcut("b", modifiers: [.command, .option])
            }
            CommandMenu("History") {
                Button("Show History") { services.sheet = .history }.keyboardShortcut("y")
                Button("Clear History") { services.library.clearHistory() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { services.sheet = .settings }.keyboardShortcut(",")
            }
        }
    }
}
