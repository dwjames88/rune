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
    static func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}

/// A write that waits. Nearly everything Rune keeps changes in bursts — history
/// on every visit, zoom on every ⌘+, tabs.json on every drag of a colour picker
/// — and none of it is worth a file write per tick. Every store wants the same
/// bargain and used to carry its own copy of it: coalesce, and flush on quit,
/// putting at most a second or two of changes at risk on a crash.
@MainActor
final class DebouncedWrite {
    private let delay: Duration
    private let write: () -> Void
    private var task: Task<Void, Never>?

    /// `write` should capture its store weakly — this outlives nothing, but a
    /// store owning a writer that owns the store is a cycle for no reason.
    init(after delay: Duration = .seconds(2), write: @escaping () -> Void) {
        self.delay = delay
        self.write = write
    }

    func schedule() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    func flush() {
        task?.cancel(); task = nil
        write()
    }
}

// MARK: - Zoom

/// What ⌘+ / ⌘− / ⌘0 do to a zoom level.
enum ZoomChange {
    case larger, smaller, reset

    /// The ladder ⌘+/⌘− climbs — the same stops Safari uses.
    static let steps: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

    func applied(to level: Double) -> Double {
        switch self {
        case .larger: Self.steps.first { $0 > level + 0.001 } ?? Self.steps.last!
        case .smaller: Self.steps.last { $0 < level - 0.001 } ?? Self.steps.first!
        case .reset: 1
        }
    }
}

/// What Rune remembers about one site.
///
/// Absent fields mean "no opinion", which is the difference between a store
/// that stays small and one that accumulates a row for every site you ever
/// pressed ⌘0 on.
struct SiteSetting: Codable, Equatable {
    /// nil = 100%.
    var zoom: Double?
    /// nil = follow the global content-blocking setting.
    var blockContent: Bool?

    var isEmpty: Bool { zoom == nil && blockContent == nil }
}

/// Everything remembered per site, keyed by host — because these are properties
/// of the place, not of the tab you happened to open it in.
///
/// Zoom used to have a store of its own, and blocking exceptions would have
/// needed an identical one: a host dictionary, the same debounced write, the
/// same "absence means default" rule. One store instead of two, and the next
/// per-site thing costs a field rather than a file.
@MainActor
final class SiteSettings: ObservableObject {
    @Published private(set) var sites: [String: SiteSetting]

    init() {
        sites = Storage.loadJSON([String: SiteSetting].self, from: "sites.json")
            ?? Self.migratedFromZoom()
    }

    /// zoom.json was the whole store before this one existed; carry it over
    /// once rather than silently resetting everyone's zoom.
    private static func migratedFromZoom() -> [String: SiteSetting] {
        guard let levels = Storage.loadJSON([String: Double].self, from: "zoom.json") else { return [:] }
        let migrated = levels.mapValues { SiteSetting(zoom: $0) }
        Storage.saveJSON(migrated, to: "sites.json")
        Storage.remove("zoom.json")
        return migrated
    }

    // MARK: Zoom

    func zoom(for host: String) -> Double { sites[host]?.zoom ?? 1 }

    func setZoom(_ level: Double, for host: String) {
        // 100% is the absence of a setting, not a stored value.
        update(host) { $0.zoom = abs(level - 1) < 0.001 ? nil : level }
    }

    var zoomedHosts: Int { sites.values.filter { $0.zoom != nil }.count }

    func clearZoom() {
        for host in sites.keys { update(host) { $0.zoom = nil } }
        flush()
    }

    // MARK: Content blocking

    /// Hosts you've told Rune to leave alone. Compiled into the rule list, so
    /// an exception costs nothing at request time.
    var blockingExceptions: [String] {
        sites.compactMap { $0.value.blockContent == false ? $0.key : nil }
    }

    func blocks(_ host: String, default global: Bool) -> Bool {
        sites[host]?.blockContent ?? global
    }

    func setBlocking(_ on: Bool?, for host: String) {
        update(host) { $0.blockContent = on }
        flush()   // the rule list recompiles off this; don't make it wait
    }

    // MARK: Storage

    private func update(_ host: String, _ mutate: (inout SiteSetting) -> Void) {
        var setting = sites[host] ?? SiteSetting()
        mutate(&setting)
        // Don't keep a row that no longer says anything.
        if setting.isEmpty { sites.removeValue(forKey: host) } else { sites[host] = setting }
        save()
    }

    private lazy var writer = DebouncedWrite { [weak self] in
        guard let self else { return }
        Storage.saveJSON(sites, to: "sites.json")
    }
    private func save() { writer.schedule() }
    func flush() { writer.flush() }
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
    case startPage, homePage, duplicateCurrent, lastClosed, addressOverlay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .startPage: "Start page"
        case .homePage: "Home page"
        case .duplicateCurrent: "Duplicate current tab"
        case .lastClosed: "Last closed tab"
        case .addressOverlay: "An address bar"
        }
    }
}

/// What happens when another app opens a link and Rune is your default browser.
enum ExternalLinkBehavior: String, Codable, CaseIterable, Identifiable {
    case newTab, segment
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newTab: "A new tab"
        case .segment: "Its own window (Segment)"
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
    /// Auto-PiP only videos playing sound. Autoplay heroes and hover previews
    /// are forced to start muted, so sound is the tell that you chose to watch.
    @Published var autoPiPAudibleOnly: Bool { didSet { save() } }
    @Published var newTabBehavior: NewTabBehavior { didSet { save() } }
    @Published var homePageURL: String { didSet { save() } }
    @Published var newTabPlacement: NewTabPlacement { didSet { save() } }
    /// Claude link previews: hover a link this long before the summary appears.
    @Published var linkHoverEnabled: Bool { didSet { save(); hoverChanged() } }
    @Published var linkHoverDelay: Double { didSet { save(); hoverChanged() } }
    /// Finder: tag saves automatically with Claude (text-context, cheap).
    @Published var finderAutoTag: Bool { didSet { save() } }
    /// Finder batch collect: skip images smaller than this on either side.
    @Published var finderMinCollectSize: Double { didSet { save() } }
    /// Which model runs Rune's AI. On-device by default — free, private and
    /// offline; Claude is the upgrade you opt into.
    @Published var aiModel: AIModel { didSet { save() } }
    /// Unload a saved tab left alone this long, in minutes. 0 = never. The row
    /// stays; only the page behind it goes, and clicking brings it back.
    @Published var hibernateAfter: Double { didSet { save() } }
    /// Close a session tab left alone this long, in hours. 0 = never. It's in
    /// history either way — this is for the tabs you meant to close.
    @Published var archiveAfter: Double { didSet { save() } }
    /// A link handed to Rune by another app: a tab, or a window of its own.
    @Published var externalLinks: ExternalLinkBehavior { didSet { save() } }
    /// Block ads and trackers. On by default: it's the single biggest thing
    /// WebKit will do for a page's speed and privacy for free.
    @Published var blockContent: Bool { didSet { save(); blockingChanged() } }
    /// Hide cookie-consent walls along with the trackers.
    @Published var hideCookieBanners: Bool { didSet { save(); blockingChanged() } }
    /// Where finished downloads land.
    @Published var downloadLocation: DownloadLocation { didSet { save() } }
    /// Reopen last session's tabs on launch. Off by design: session tabs are
    /// meant to be disposable, but that should be your call, not ours.
    @Published var restoreSession: Bool { didSet { save() } }

    var allEngines: [SearchEngine] { SearchEngine.presets + customEngines }

    private struct Payload: Codable {
        var searchEngine: SearchEngine
        var customEngines: [SearchEngine]
        // Optionals: absent in older settings.json
        var autoPiP: AutoPiPMode?
        var autoPiPReturnInline: Bool?
        var autoPiPAudibleOnly: Bool?
        var newTabBehavior: NewTabBehavior?
        var homePageURL: String?
        var newTabPlacement: NewTabPlacement?
        var linkHoverEnabled: Bool?
        var linkHoverDelay: Double?
        var finderAutoTag: Bool?
        var finderMinCollectSize: Double?
        var downloadLocation: DownloadLocation?
        var restoreSession: Bool?
        var aiModel: AIModel?
        var blockContent: Bool?
        var hideCookieBanners: Bool?
        var externalLinks: ExternalLinkBehavior?
        var hibernateAfter: Double?
        var archiveAfter: Double?
    }

    init() {
        let saved = Storage.loadJSON(Payload.self, from: "settings.json")
        searchEngine = saved?.searchEngine ?? SearchEngine.presets[0]
        customEngines = saved?.customEngines ?? []
        autoPiP = saved?.autoPiP ?? .tabSwitch
        autoPiPReturnInline = saved?.autoPiPReturnInline ?? true
        autoPiPAudibleOnly = saved?.autoPiPAudibleOnly ?? true
        newTabBehavior = saved?.newTabBehavior ?? .startPage
        homePageURL = saved?.homePageURL ?? ""
        newTabPlacement = saved?.newTabPlacement ?? .end
        linkHoverEnabled = saved?.linkHoverEnabled ?? true
        linkHoverDelay = saved?.linkHoverDelay ?? 0.45
        finderAutoTag = saved?.finderAutoTag ?? false
        finderMinCollectSize = saved?.finderMinCollectSize ?? 200
        downloadLocation = saved?.downloadLocation ?? .downloadsFolder
        restoreSession = saved?.restoreSession ?? false
        aiModel = saved?.aiModel ?? .onDevice
        externalLinks = saved?.externalLinks ?? .segment
        hibernateAfter = saved?.hibernateAfter ?? 0
        archiveAfter = saved?.archiveAfter ?? 0
        blockContent = saved?.blockContent ?? true
        hideCookieBanners = saved?.hideCookieBanners ?? true
    }
    // The last store that still wrote on every didSet — typing a home page URL
    // was a file write per keystroke. Same bargain as everywhere else now.
    private lazy var writer = DebouncedWrite { [weak self] in
        guard let self else { return }
        Storage.saveJSON(Payload(searchEngine: searchEngine, customEngines: customEngines,
                                 autoPiP: autoPiP, autoPiPReturnInline: autoPiPReturnInline,
                                 autoPiPAudibleOnly: autoPiPAudibleOnly,
                                 newTabBehavior: newTabBehavior, homePageURL: homePageURL,
                                 newTabPlacement: newTabPlacement,
                                 linkHoverEnabled: linkHoverEnabled, linkHoverDelay: linkHoverDelay,
                                 finderAutoTag: finderAutoTag, finderMinCollectSize: finderMinCollectSize,
                                 downloadLocation: downloadLocation, restoreSession: restoreSession,
                                 aiModel: aiModel, blockContent: blockContent,
                                 hideCookieBanners: hideCookieBanners,
                                 externalLinks: externalLinks,
                                 hibernateAfter: hibernateAfter, archiveAfter: archiveAfter),
                         to: "settings.json")
    }
    private func save() { writer.schedule() }
    func flush() { writer.flush() }
    private func hoverChanged() {
        NotificationCenter.default.post(name: .hoverSettingsChanged, object: nil)
    }
    private func blockingChanged() {
        NotificationCenter.default.post(name: .blockingSettingsChanged, object: nil)
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

    /// True when the URL is a site's front door — nothing after the host but
    /// at most a bare slash. Same slicing diet as fastHost, same reason.
    static func isRoot(_ url: String) -> Bool {
        var s = Substring(url)
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        guard let slash = s.firstIndex(of: "/") else { return true }
        return s[s.index(after: slash)...].isEmpty
    }

    /// Host of a URL string by slicing — no URL/Foundation parsing. Runs for
    /// every history entry on every keystroke, so it has to be cheap.
    static func fastHost(of url: String) -> Substring {
        var s = Substring(url)
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        if let slash = s.firstIndex(of: "/") { s = s[..<slash] }
        if s.hasPrefix("www.") { s = s.dropFirst(4) }
        return s
    }

    /// Auto-predict: rank by *where* the query matches (host prefix beats title
    /// prefix beats a loose contains), then by how often and how recently you
    /// went there. This is what makes the address bar guess the right thing.
    func predict(_ query: String, limit: Int = 5) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let now = Date()

        func score(_ e: HistoryEntry) -> Double? {
            let url = e.url.lowercased()
            let title = e.title.lowercased()
            let host = Self.fastHost(of: url)

            var base: Double
            // The whole host, typed out, is not a prefix you're guessing at:
            // it names the site's front door, and no amount of visits to a
            // deep link on it should outrank that. (The deep links share the
            // exact host too, which is why the tier needs the root check.)
            if host == q, Self.isRoot(url) { base = 1300 }
            else if host.hasPrefix(q) { base = 1000 }
            else if title.hasPrefix(q) { base = 700 }
            else if host.contains(q) { base = 450 }
            else if title.contains(q) { base = 300 }
            else if url.contains(q) { base = 150 }
            else { return nil }

            // Frequency (log-damped) and recency (decays over ~2 weeks).
            let frequency = log2(Double(e.visitCount) + 1) * 20
            let days = max(0, now.timeIntervalSince(e.lastVisited) / 86_400)
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
        return Self.fastHost(of: entry.url.lowercased()).hasPrefix(q)
    }

    func clear() { entries = []; flush() }

    /// Unbounded history is a slow address bar on a long timeline: predict()
    /// touches every entry per keystroke. Trimmed with hysteresis — cut to
    /// `keep` only after passing `cap` — so it isn't re-sorting on every visit.
    private static let cap = 6000, keep = 5000

    private func trimIfNeeded() {
        guard entries.count > Self.cap else { return }
        entries.sort { ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited) }
        entries.removeLast(entries.count - Self.keep)
    }

    // Every page visit used to rewrite all of history.json.
    private lazy var writer = DebouncedWrite { [weak self] in
        guard let self else { return }
        trimIfNeeded()
        Storage.saveJSON(entries, to: "history.json")
    }
    private func save() { writer.schedule() }
    func flush() { writer.flush() }
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
    static let finderToast = Notification.Name("rune.finderToast")
    static let frontBrowserWindow = Notification.Name("rune.frontBrowserWindow")
    static let showFindBar = Notification.Name("rune.showFindBar")
    static let showNewTabOverlay = Notification.Name("rune.showNewTabOverlay")
    /// Wiggle mode: the strip and corner kit start (or stop) taking edits.
    static let toggleControlEdit = Notification.Name("rune.toggleControlEdit")
    /// Open the Finder window already turned to its Downloads section.
    static let finderShowDownloads = Notification.Name("rune.finderShowDownloads")
    static let glanceLink = Notification.Name("rune.glanceLink")
    static let blockingSettingsChanged = Notification.Name("rune.blockingSettingsChanged")
    /// A left click landed on a page. Address bars listen and let focus go —
    /// clicking the web is leaving the field.
    static let pageClicked = Notification.Name("rune.pageClicked")
}
