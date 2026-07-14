import AppKit
import Combine

/// On-disk location for Rune's data (settings, history). The web session
/// (cookies, logins, localStorage) lives in WKWebsiteDataStore.default(), which
/// persists automatically — that's what keeps you signed in across launches.
enum Storage {
    static var root: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rune")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    static func loadJSON<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func saveJSON<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) { try? data.write(to: url(name), options: .atomic) }
    }
}

// MARK: - Search engine

struct SearchEngine: Codable, Hashable, Identifiable {
    var name: String
    /// Query template with {q} where the search terms go.
    var queryTemplate: String
    var id: String { name }

    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: queryTemplate.replacingOccurrences(of: "{q}", with: encoded))
    }

    static let presets: [SearchEngine] = [
        SearchEngine(name: "DuckDuckGo", queryTemplate: "https://duckduckgo.com/?q={q}"),
        SearchEngine(name: "Google", queryTemplate: "https://www.google.com/search?q={q}"),
        SearchEngine(name: "Bing", queryTemplate: "https://www.bing.com/search?q={q}"),
        SearchEngine(name: "Brave", queryTemplate: "https://search.brave.com/search?q={q}"),
        SearchEngine(name: "Kagi", queryTemplate: "https://kagi.com/search?q={q}"),
    ]
}

// MARK: - Settings

@MainActor
final class SettingsStore: ObservableObject {
    @Published var searchEngine: SearchEngine { didSet { save() } }
    @Published var customEngines: [SearchEngine] { didSet { save() } }

    var allEngines: [SearchEngine] { SearchEngine.presets + customEngines }

    private struct Payload: Codable { var searchEngine: SearchEngine; var customEngines: [SearchEngine] }

    init() {
        let saved = Storage.loadJSON(Payload.self, from: "settings.json")
        searchEngine = saved?.searchEngine ?? SearchEngine.presets[0]
        customEngines = saved?.customEngines ?? []
    }
    private func save() {
        Storage.saveJSON(Payload(searchEngine: searchEngine, customEngines: customEngines), to: "settings.json")
    }
}

// MARK: - History

struct HistoryEntry: Codable, Identifiable, Hashable {
    var url: String
    var title: String
    var lastVisited: Date
    var visitCount: Int
    var id: String { url }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry]

    init() {
        entries = Storage.loadJSON([HistoryEntry].self, from: "history.json") ?? []
    }

    func record(url: URL, title: String) {
        let key = url.absoluteString
        guard url.scheme == "http" || url.scheme == "https" else { return }
        if let i = entries.firstIndex(where: { $0.url == key }) {
            entries[i].lastVisited = Date()
            entries[i].visitCount += 1
            if !title.isEmpty { entries[i].title = title }
        } else {
            entries.append(HistoryEntry(url: key, title: title, lastVisited: Date(), visitCount: 1))
        }
        save()
    }

    /// Best matches for a query, ranked by recency + frequency.
    func search(_ query: String, limit: Int = 6) -> [HistoryEntry] {
        let q = query.lowercased()
        let matches = q.isEmpty ? entries : entries.filter {
            $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
        return matches.sorted {
            ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited)
        }.prefix(limit).map { $0 }
    }

    func clear() { entries = []; save() }
    private func save() { Storage.saveJSON(entries, to: "history.json") }
}

// MARK: - Shortcuts (remappable)

struct Shortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt   // NSEvent.ModifierFlags rawValue

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Human-readable, e.g. ⇧⌘K.
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var overrides: [String: Shortcut]

    init() {
        overrides = Storage.loadJSON([String: Shortcut].self, from: "shortcuts.json") ?? [:]
    }

    func shortcut(for command: Command) -> Shortcut {
        if let o = overrides[command.rawValue] { return o }
        let (key, mods) = command.defaultShortcut
        return Shortcut(key: key, modifiers: mods.rawValue)
    }

    func set(_ shortcut: Shortcut?, for command: Command) {
        if let shortcut { overrides[command.rawValue] = shortcut }
        else { overrides.removeValue(forKey: command.rawValue) }   // reset to default
        Storage.saveJSON(overrides, to: "shortcuts.json")
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    func resetAll() {
        overrides = [:]
        Storage.saveJSON(overrides, to: "shortcuts.json")
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("rune.shortcutsChanged")
    static let showCommandPalette = Notification.Name("rune.showCommandPalette")
    static let focusAddressBar = Notification.Name("rune.focusAddressBar")
}
