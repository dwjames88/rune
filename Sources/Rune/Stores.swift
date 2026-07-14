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

/// When a playing video should automatically pop into Picture in Picture.
enum AutoPiPMode: String, Codable, CaseIterable, Identifiable {
    case off
    case tabSwitch
    case tabSwitchAndAppSwitch

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .tabSwitch: "When switching tabs"
        case .tabSwitchAndAppSwitch: "Tab switch + leaving Rune"
        }
    }
}

/// What a fresh tab opens with.
enum NewTabBehavior: String, Codable, CaseIterable, Identifiable {
    case startPage, homePage, duplicateCurrent, lastClosed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .startPage: "Start page"
        case .homePage: "Home page"
        case .duplicateCurrent: "Duplicate current tab"
        case .lastClosed: "Last closed tab"
        }
    }
}

/// Where a fresh tab lands in the session list.
enum NewTabPlacement: String, Codable, CaseIterable, Identifiable {
    case end, nextToActive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .end: "At the end"
        case .nextToActive: "Next to the active tab"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var searchEngine: SearchEngine { didSet { save() } }
    @Published var customEngines: [SearchEngine] { didSet { save() } }
    @Published var autoPiP: AutoPiPMode { didSet { save() } }
    /// Bring a PiP'd video back into the page when you return to its tab.
    @Published var autoPiPReturnInline: Bool { didSet { save() } }
    @Published var newTabBehavior: NewTabBehavior { didSet { save() } }
    @Published var homePageURL: String { didSet { save() } }
    @Published var newTabPlacement: NewTabPlacement { didSet { save() } }
    /// Claude link previews: hover a link this long before the summary appears.
    @Published var linkHoverEnabled: Bool { didSet { save(); hoverChanged() } }
    @Published var linkHoverDelay: Double { didSet { save(); hoverChanged() } }

    var allEngines: [SearchEngine] { SearchEngine.presets + customEngines }

    private struct Payload: Codable {
        var searchEngine: SearchEngine
        var customEngines: [SearchEngine]
        // Optionals: absent in older settings.json
        var autoPiP: AutoPiPMode?
        var autoPiPReturnInline: Bool?
        var newTabBehavior: NewTabBehavior?
        var homePageURL: String?
        var newTabPlacement: NewTabPlacement?
        var linkHoverEnabled: Bool?
        var linkHoverDelay: Double?
    }

    init() {
        let saved = Storage.loadJSON(Payload.self, from: "settings.json")
        searchEngine = saved?.searchEngine ?? SearchEngine.presets[0]
        customEngines = saved?.customEngines ?? []
        autoPiP = saved?.autoPiP ?? .tabSwitch
        autoPiPReturnInline = saved?.autoPiPReturnInline ?? true
        newTabBehavior = saved?.newTabBehavior ?? .startPage
        homePageURL = saved?.homePageURL ?? ""
        newTabPlacement = saved?.newTabPlacement ?? .end
        linkHoverEnabled = saved?.linkHoverEnabled ?? true
        linkHoverDelay = saved?.linkHoverDelay ?? 0.45
    }
    private func save() {
        Storage.saveJSON(Payload(searchEngine: searchEngine, customEngines: customEngines,
                                 autoPiP: autoPiP, autoPiPReturnInline: autoPiPReturnInline,
                                 newTabBehavior: newTabBehavior, homePageURL: homePageURL,
                                 newTabPlacement: newTabPlacement,
                                 linkHoverEnabled: linkHoverEnabled, linkHoverDelay: linkHoverDelay),
                         to: "settings.json")
    }
    private func hoverChanged() {
        NotificationCenter.default.post(name: .hoverSettingsChanged, object: nil)
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

    /// Auto-predict: rank by *where* the query matches (host prefix beats title
    /// prefix beats a loose contains), then by how often and how recently you
    /// went there. This is what makes the address bar guess the right thing.
    func predict(_ query: String, limit: Int = 5) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        func score(_ e: HistoryEntry) -> Double? {
            let url = e.url.lowercased()
            let title = e.title.lowercased()
            let host = URL(string: e.url)?.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""

            var base: Double
            if host.hasPrefix(q) { base = 1000 }
            else if title.hasPrefix(q) { base = 700 }
            else if host.contains(q) { base = 450 }
            else if title.contains(q) { base = 300 }
            else if url.contains(q) { base = 150 }
            else { return nil }

            // Frequency (log-damped) and recency (decays over ~2 weeks).
            let frequency = log2(Double(e.visitCount) + 1) * 20
            let days = max(0, Date().timeIntervalSince(e.lastVisited) / 86_400)
            let recency = max(0, 60 - days * 4)
            // Prefer shorter URLs — usually the canonical page, not a deep link.
            let brevity = max(0, 30 - Double(e.url.count) / 8)
            return base + frequency + recency + brevity
        }

        return entries.compactMap { e in score(e).map { ($0, e) } }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map(\.1)
    }

    /// A confident hit: you typed the start of a host you actually visit
    /// ("pink" → pinkbike.com). These lead the list instead of a generic search.
    func isConfident(_ query: String, _ entry: HistoryEntry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, !q.contains(" ") else { return false }
        let host = URL(string: entry.url)?.host?
            .lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
        return host.hasPrefix(q)
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
    static let showAskBar = Notification.Name("rune.showAskBar")
    static let focusStartPage = Notification.Name("rune.focusStartPage")
    static let hoverSettingsChanged = Notification.Name("rune.hoverSettingsChanged")
}
