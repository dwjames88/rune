import Combine
import SwiftUI
import WebKit

// MARK: - Persistent sidebar entries

/// A saved sidebar entry (a favorite or a pinned tab). Persists across launches.
struct SavedTab: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    var name: String
    var customName = false
    var colorHex: String? = nil
    var faviconPNG: Data? = nil
    var folderID: UUID? = nil       // pinned only; favorites can't be foldered
}

struct Folder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "folder.fill"
    var collapsed = false
}

/// What is currently focused in the content area.
enum Selection: Equatable, Hashable {
    case saved(UUID)
    case session(UUID)
}

/// Where a dragged tab was dropped. `index` is the insertion point (nil = append).
enum DropTarget: Equatable {
    case favorites(Int?)
    case pinned(folderID: UUID?, index: Int?)
    case session(Int?)
}

// MARK: - Live tab

/// A live tab. Its WKWebView is created once and kept alive — switching never
/// reloads. Session tabs are ephemeral; a saved entry gets a live tab when opened.
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    var savedID: UUID?              // set when this live tab backs a SavedTab

    @Published var title = "New Tab"
    @Published var urlString = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var favicon: NSImage?

    @Published var customName: String?
    @Published var colorHex: String?

    private var cancellables: Set<AnyCancellable> = []

    init(webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.webView = webView

        webView.publisher(for: \.title).sink { [weak self] in
            if let t = $0, !t.isEmpty { self?.title = t }
        }.store(in: &cancellables)
        webView.publisher(for: \.url).sink { [weak self] in self?.urlString = $0?.absoluteString ?? "" }
            .store(in: &cancellables)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
    }

    var displayName: String { customName ?? (title.isEmpty ? "New Tab" : title) }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    func requestPiPIfPlaying() {
        webView.evaluateJavaScript("""
        (function(){const v=[...document.querySelectorAll('video')].find(v=>!v.paused&&!v.ended&&v.readyState>2);
        if(v&&document.pictureInPictureEnabled&&!document.pictureInPictureElement){v.requestPictureInPicture().catch(()=>{});}})();
        """)
    }
}

// MARK: - Browser model

@MainActor
final class BrowserModel: ObservableObject {
    // Persistent
    @Published var favorites: [SavedTab] = []      // max 6, no folders
    @Published var pinned: [SavedTab] = []
    @Published var folders: [Folder] = []
    // Ephemeral (this session only)
    @Published var sessionTabs: [Tab] = []
    @Published var openTabs: [UUID: Tab] = [:]     // savedID -> live tab
    @Published var selection: Selection?
    @Published var sidebarVisible = true

    static let maxFavorites = 6

    let configuration: WKWebViewConfiguration
    let settings: SettingsStore
    let history: HistoryStore
    let shortcuts: ShortcutStore
    private lazy var coordinator = WebCoordinator(model: self)

    private struct Persisted: Codable { var favorites: [SavedTab]; var pinned: [SavedTab]; var folders: [Folder] }

    init(settings: SettingsStore, history: HistoryStore, shortcuts: ShortcutStore) {
        self.settings = settings; self.history = history; self.shortcuts = shortcuts
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        self.configuration = config

        if let saved = Storage.loadJSON(Persisted.self, from: "tabs.json") {
            favorites = saved.favorites; pinned = saved.pinned; folders = saved.folders
        }
    }

    func persist() {
        Storage.saveJSON(Persisted(favorites: favorites, pinned: pinned, folders: folders), to: "tabs.json")
    }

    // MARK: Live tab lookup

    var activeTab: Tab? {
        switch selection {
        case .session(let id): return sessionTabs.first { $0.id == id }
        case .saved(let id): return openTabs[id]
        case nil: return nil
        }
    }

    private func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration ?? self.configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return webView
    }

    // MARK: Session tabs

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true) -> Tab {
        let tab = Tab(webView: makeWebView())
        sessionTabs.append(tab)
        if let url { tab.load(url) }
        if select { self.select(.session(tab.id)) }
        return tab
    }

    func adoptPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = makeWebView(configuration: configuration)
        let tab = Tab(webView: webView)
        sessionTabs.append(tab)
        select(.session(tab.id))
        return webView
    }

    // MARK: Selection

    func select(_ new: Selection) {
        if let current = activeTab { current.requestPiPIfPlaying() }
        if case .saved(let id) = new, openTabs[id] == nil, let saved = savedTab(id) {
            let tab = Tab(webView: makeWebView())
            tab.savedID = id
            tab.customName = saved.customName ? saved.name : nil
            tab.colorHex = saved.colorHex
            if let png = saved.faviconPNG { tab.favicon = NSImage(data: png) }
            openTabs[id] = tab
            if let url = URL(string: saved.url) { tab.load(url) }
        }
        selection = new
    }

    func savedTab(_ id: UUID) -> SavedTab? {
        favorites.first { $0.id == id } ?? pinned.first { $0.id == id }
    }

    // MARK: Close / unload

    func close(session tab: Tab) {
        tab.webView.stopLoading()
        sessionTabs.removeAll { $0.id == tab.id }
        if selection == .session(tab.id) {
            selection = sessionTabs.last.map { .session($0.id) } ?? pinned.first.map { .saved($0.id) }
        }
    }

    func closeActive() {
        switch selection {
        case .session(let id): if let t = sessionTabs.first(where: { $0.id == id }) { close(session: t) }
        case .saved(let id): unload(savedID: id)
        case nil: break
        }
    }

    /// Unload a saved entry's live tab (keeps the row).
    func unload(savedID: UUID) {
        openTabs[savedID]?.webView.stopLoading()
        openTabs[savedID] = nil
        if selection == .saved(savedID) { selection = nil }
    }

    // MARK: Favorites / pinning

    var canAddFavorite: Bool { favorites.count < Self.maxFavorites }

    func addFavorite(from tab: Tab) {
        guard canAddFavorite, let url = tab.webView.url else { return }
        let saved = SavedTab(url: url.absoluteString, name: tab.displayName,
                             colorHex: tab.colorHex, faviconPNG: tab.favicon?.png)
        favorites.append(saved)
        rebind(tab, to: saved.id); persist()
    }

    func pin(_ tab: Tab) {
        guard let url = tab.webView.url else { return }
        let saved = SavedTab(url: url.absoluteString, name: tab.displayName,
                             colorHex: tab.colorHex, faviconPNG: tab.favicon?.png)
        pinned.append(saved)
        rebind(tab, to: saved.id); persist()
    }

    /// Move a live session tab to be the live tab of a new saved entry.
    private func rebind(_ tab: Tab, to savedID: UUID) {
        sessionTabs.removeAll { $0.id == tab.id }
        tab.savedID = savedID
        openTabs[savedID] = tab
        selection = .saved(savedID)
    }

    func removeFavorite(_ id: UUID) { favorites.removeAll { $0.id == id }; unload(savedID: id); persist() }
    func unpin(_ id: UUID) { pinned.removeAll { $0.id == id }; unload(savedID: id); persist() }

    // MARK: Folders

    @discardableResult
    func addFolder(name: String = "New Folder") -> Folder {
        let folder = Folder(name: name); folders.append(folder); persist(); return folder
    }
    func move(_ savedID: UUID, toFolder folderID: UUID?) {
        guard let i = pinned.firstIndex(where: { $0.id == savedID }) else { return }
        pinned[i].folderID = folderID; persist()
    }
    func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name; persist()
    }
    func setFolderIcon(_ id: UUID, _ icon: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].icon = icon; persist()
    }
    func deleteFolder(_ id: UUID) {
        for i in pinned.indices where pinned[i].folderID == id { pinned[i].folderID = nil }
        folders.removeAll { $0.id == id }; persist()
    }
    func toggleFolder(_ id: UUID) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].collapsed.toggle(); persist()
    }
    func pinned(in folderID: UUID?) -> [SavedTab] { pinned.filter { $0.folderID == folderID } }

    // MARK: Customize name / color

    func setName(_ name: String, for selection: Selection) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch selection {
        case .session(let id):
            sessionTabs.first { $0.id == id }?.customName = trimmed.isEmpty ? nil : trimmed
        case .saved(let id):
            updateSaved(id) { $0.name = trimmed.isEmpty ? $0.name : trimmed; $0.customName = !trimmed.isEmpty }
            openTabs[id]?.customName = trimmed.isEmpty ? nil : trimmed
        }
    }
    func setColor(_ hex: String?, for selection: Selection) {
        switch selection {
        case .session(let id): sessionTabs.first { $0.id == id }?.colorHex = hex
        case .saved(let id):
            updateSaved(id) { $0.colorHex = hex }
            openTabs[id]?.colorHex = hex
        }
    }
    // MARK: Drag & drop

    /// Handle a drop of `drag` onto a destination. `beforePinned` / `beforeSession`
    /// give an insertion point when dropping onto a row.
    func handleDrop(_ drag: TabDrag, to destination: DropTarget) {
        switch destination {
        case .favorites(let index):
            guard let saved = detachToSaved(drag) else { return }
            guard favorites.count < Self.maxFavorites || drag.origin == .favorite else { return }
            favorites.insert(saved, at: min(index ?? favorites.count, favorites.count))

        case .pinned(let folderID, let index):
            guard var saved = detachToSaved(drag) else { return }
            saved.folderID = folderID
            // Insert relative to the siblings in that folder.
            let siblings = pinned(in: folderID)
            if let index, index < siblings.count,
               let anchor = pinned.firstIndex(where: { $0.id == siblings[index].id }) {
                pinned.insert(saved, at: anchor)
            } else {
                pinned.append(saved)
            }

        case .session(let index):
            // Dragging a saved entry back out makes it an ordinary session tab.
            guard drag.origin != .session else { reorderSession(drag.id, to: index); return }
            guard let saved = savedTab(drag.id) else { return }
            let live = openTabs[drag.id]
            removeSaved(drag.id)
            let tab = live ?? Tab(webView: makeWebView())
            tab.savedID = nil
            if live == nil, let url = URL(string: saved.url) { tab.load(url) }
            openTabs[drag.id] = nil
            sessionTabs.insert(tab, at: min(index ?? sessionTabs.count, sessionTabs.count))
            selection = .session(tab.id)
        }
        persist()
    }

    /// Pull the dragged item out of wherever it lives and return it as a SavedTab
    /// (converting a session tab into one, keeping its live web view).
    private func detachToSaved(_ drag: TabDrag) -> SavedTab? {
        switch drag.origin {
        case .session:
            guard let tab = sessionTabs.first(where: { $0.id == drag.id }),
                  let url = tab.webView.url else { return nil }
            let saved = SavedTab(url: url.absoluteString, name: tab.displayName,
                                 customName: tab.customName != nil,
                                 colorHex: tab.colorHex, faviconPNG: tab.favicon?.png)
            sessionTabs.removeAll { $0.id == tab.id }
            tab.savedID = saved.id
            openTabs[saved.id] = tab
            selection = .saved(saved.id)
            return saved
        case .pinned, .favorite:
            guard let saved = savedTab(drag.id) else { return nil }
            removeSaved(drag.id)      // keeps openTabs entry alive
            return saved
        }
    }

    private func removeSaved(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        pinned.removeAll { $0.id == id }
    }

    private func reorderSession(_ id: UUID, to index: Int?) {
        guard let from = sessionTabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = sessionTabs.remove(at: from)
        var target = index ?? sessionTabs.count
        if let i = index, from < i { target = i - 1 }
        sessionTabs.insert(tab, at: min(max(0, target), sessionTabs.count))
    }

    func currentName(for selection: Selection) -> String {
        switch selection {
        case .session(let id): return sessionTabs.first { $0.id == id }?.displayName ?? ""
        case .saved(let id): return savedTab(id)?.name ?? ""
        }
    }
    private func updateSaved(_ id: UUID, _ mutate: (inout SavedTab) -> Void) {
        if let i = favorites.firstIndex(where: { $0.id == id }) { mutate(&favorites[i]) }
        else if let i = pinned.firstIndex(where: { $0.id == id }) { mutate(&pinned[i]) }
        persist()
    }

    // MARK: Favicon (called by coordinator on load finish)

    func updateFavicon(_ image: NSImage, for tab: Tab) {
        tab.favicon = image
        if let savedID = tab.savedID { updateSaved(savedID) { $0.faviconPNG = image.png } }
    }

    // MARK: Navigation

    func navigate(_ input: String) {
        guard let url = resolve(input) else { return }
        let tab = activeTab ?? newTab()
        tab.load(url)
    }
    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }
    func reload() { activeTab?.webView.reload() }
    func recordVisit(_ url: URL, title: String) { history.record(url: url, title: title) }

    func selectAdjacentSession(_ delta: Int) {
        guard !sessionTabs.isEmpty else { return }
        let index = sessionTabs.firstIndex { selection == .session($0.id) } ?? 0
        let next = (index + delta + sessionTabs.count) % sessionTabs.count
        select(.session(sessionTabs[next].id))
    }

    func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains(" ") || (!text.contains(".") && text != "localhost") {
            return settings.searchEngine.url(for: text)
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        return URL(string: "https://\(text)")
    }
}

extension NSImage {
    var png: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
