import AppIntents
import Foundation

/// Shortcuts action: open a link in Madobe.
struct OpenInMadobeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Madobe"
    static let description = IntentDescription("Opens a link in a new Madobe tab.")
    static let openAppWhenRun = true

    @Parameter(title: "Link") var url: URL

    @MainActor func perform() async throws -> some IntentResult {
        Services.shared.receive(url, in: .tab)
        return .result()
    }
}

#if os(macOS)
/// Shortcuts action (Mac): open a link in the floating, see-through Float window.
struct OpenInFloatIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Float Window"
    static let description = IntentDescription("Opens a link in Madobe's floating window that stays above other apps.")
    static let openAppWhenRun = true

    @Parameter(title: "Link") var url: URL

    @MainActor func perform() async throws -> some IntentResult {
        Services.shared.receive(url, in: .float)
        return .result()
    }
}
#endif

struct MadobeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenInMadobeIntent(), phrases: ["Open a link in \(.applicationName)"],
                    shortTitle: "Open in Madobe", systemImageName: "safari")
        #if os(macOS)
        AppShortcut(intent: OpenInFloatIntent(), phrases: ["Float a link in \(.applicationName)"],
                    shortTitle: "Open in Float Window", systemImageName: "pip")
        #endif
    }
}
