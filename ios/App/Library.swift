import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var added = Date()
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var visited = Date()
}

/// Bookmarks and history, saved as two small JSON files. Private tabs never reach this.
@MainActor
final class Library: ObservableObject {
    static let historyLimit = 500

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var history: [HistoryItem] = []
    private let directory: URL

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Madobe", isDirectory: true)
    }

    init(directory: URL = Library.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        bookmarks = load("bookmarks.json") ?? []
        history = load("history.json") ?? []
    }

    // MARK: Bookmarks

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    /// Adds the page, or removes it if it is already saved.
    func toggleBookmark(title: String, url: String) {
        if let i = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.insert(Bookmark(title: title.isEmpty ? url : title, url: url), at: 0)
        }
        save(bookmarks, to: "bookmarks.json")
    }

    func removeBookmarks(_ items: [Bookmark]) {
        let ids = Set(items.map(\.id))
        bookmarks.removeAll { ids.contains($0.id) }
        save(bookmarks, to: "bookmarks.json")
    }

    // MARK: History

    /// Newest first. Visiting a page again moves it to the top instead of duplicating it.
    func record(title: String, url: String) {
        history.removeAll { $0.url == url }
        history.insert(HistoryItem(title: title.isEmpty ? url : title, url: url), at: 0)
        if history.count > Library.historyLimit { history.removeLast(history.count - Library.historyLimit) }
        save(history, to: "history.json")
    }

    func removeHistory(_ items: [HistoryItem]) {
        let ids = Set(items.map(\.id))
        history.removeAll { ids.contains($0.id) }
        save(history, to: "history.json")
    }

    func clearHistory() {
        history = []
        save(history, to: "history.json")
    }

    // MARK: Storage

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
