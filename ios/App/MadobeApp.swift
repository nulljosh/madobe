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
    #if os(macOS)
    @ObservedObject private var floating = FloatController.shared
    #endif

    init() {
        let services = Services.shared
        _services = StateObject(wrappedValue: services)
        _tabs = StateObject(wrappedValue: Tabs(services: services, restore: true, defaults: services.defaults))
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
            #if os(macOS)
            CommandGroup(after: .toolbar) {
                Button("Float Current Tab") { floating.open(tabs.page.address, services: services) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(tabs.page.address.isEmpty)
                Button(floating.clickThrough ? "Turn Float Click-Through Off" : "Turn Float Click-Through On") {
                    floating.toggleClickThrough()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!floating.isOpen)
                Button("Close Float Window") { floating.close() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                    .disabled(!floating.isOpen)
            }
            #endif
            CommandGroup(after: .textEditing) {
                Button("Find in Page") { services.finding = true }.keyboardShortcut("f")
                Button("Open Location") { services.addressFocusTick += 1 }.keyboardShortcut("l")
            }
            CommandMenu("Site") {
                Button("Site Rules…") { services.sheet = .siteRules }.keyboardShortcut("s", modifiers: [.command, .option])
                #if os(iOS)
                Button("Pair Two Pages") { tabs.startPair() }.keyboardShortcut("p", modifiers: [.command, .option])
                #endif
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
