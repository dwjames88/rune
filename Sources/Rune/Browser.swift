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

    // Claude's ambient hooks into the page
    @Published var hoveredLink: HoverTarget?
    @Published var selection: SelectionTarget?

    /// Readable text of the current page (for "ask about this page").
    func pageText() async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(PageBridge.pageTextJS) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    init(webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.webView = webView

        // KVO fires repeatedly with unchanged values (especially title on SPAs);
        // only publish real changes so observing rows don't re-render for nothing.
        webView.publisher(for: \.title).sink { [weak self] in
            if let self, let t = $0, !t.isEmpty, t != self.title { self.title = t }
        }.store(in: &cancellables)
        webView.publisher(for: \.url).sink { [weak self] in
            if let self { let s = $0?.absoluteString ?? ""; if s != self.urlString { self.urlString = s } }
        }.store(in: &cancellables)
        webView.publisher(for: \.isLoading).removeDuplicates().assign(to: &$isLoading)
        webView.publisher(for: \.canGoBack).removeDuplicates().assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).removeDuplicates().assign(to: &$canGoForward)
    }

    var displayName: String { customName ?? (title.isEmpty ? "New Tab" : title) }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    // MARK: Picture in Picture
    //
    // WebKit does not implement the W3C Picture-in-Picture API
    // (document.pictureInPictureEnabled is undefined) — its native path is
    // video.webkitSetPresentationMode('picture-in-picture'), which also works
    // without transient user activation. Keep the W3C call as a fallback in
    // case WebKit ever ships it.

    private static let enterPiPJS = """
    (function(){
      const vids=[...document.querySelectorAll('video')];
      if(vids.some(v=>v.webkitPresentationMode==='picture-in-picture')||document.pictureInPictureElement){return 'already-pip';}
      const v=vids.find(v=>!v.paused&&!v.ended&&v.readyState>2);
      if(!v){return 'no-playing-video';}
      if(v.webkitSupportsPresentationMode&&v.webkitSupportsPresentationMode('picture-in-picture')){
        v.webkitSetPresentationMode('picture-in-picture');return 'webkit';
      }
      if(document.pictureInPictureEnabled&&v.requestPictureInPicture){
        v.requestPictureInPicture().catch(e=>{});return 'w3c';
      }
      return 'unsupported';
    })();
    """

    private static let exitPiPJS = """
    (function(){
      const v=[...document.querySelectorAll('video')].find(v=>v.webkitPresentationMode==='picture-in-picture');
      if(v){v.webkitSetPresentationMode('inline');return 'webkit';}
      if(document.pictureInPictureElement){document.exitPictureInPicture().catch(e=>{});return 'w3c';}
      return 'none';
    })();
    """

    func requestPiPIfPlaying() {
        webView.evaluateJavaScript(Self.enterPiPJS) { _, error in
            if let error { NSLog("Rune PiP enter failed: %@", error.localizedDescription) }
        }
    }

    /// Bring a PiP'd video back into the page (used when its tab is reselected).
    func exitPiPIfActive() {
        webView.evaluateJavaScript(Self.exitPiPJS) { _, error in
            if let error { NSLog("Rune PiP exit failed: %@", error.localizedDescription) }
        }
    }

    /// Manual toggle: exit if a video is in PiP, otherwise send one there.
    /// Unlike the automatic path, a paused video qualifies too, and the outcome
    /// is logged — a manual toggle that does nothing is worth diagnosing.
    func togglePiP() {
        webView.evaluateJavaScript("""
        (function(){
          const vids=[...document.querySelectorAll('video')];
          const active=vids.find(v=>v.webkitPresentationMode==='picture-in-picture');
          if(active){active.webkitSetPresentationMode('inline');return 'exited';}
          if(document.pictureInPictureElement){document.exitPictureInPicture().catch(e=>{});return 'exited';}
          const v=vids.find(v=>!v.paused&&!v.ended&&v.readyState>2)||vids.find(v=>v.readyState>2);
          if(!v){return 'no-video';}
          if(v.webkitSupportsPresentationMode&&v.webkitSupportsPresentationMode('picture-in-picture')){
            v.webkitSetPresentationMode('picture-in-picture');return 'entered';
          }
          if(document.pictureInPictureEnabled&&v.requestPictureInPicture){
            v.requestPictureInPicture().catch(e=>{});return 'entered';
          }
          return 'unsupported';
        })();
        """) { result, error in
            if let error { NSLog("Rune PiP toggle failed: %@", error.localizedDescription) }
            else { NSLog("Rune PiP toggle: %@", result as? String ?? "?") }
        }
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
    /// The Finder library surface (shown over the content area).
    @Published var showingFinder = false
    /// Batch-collect candidates; non-nil presents the collect sheet.
    @Published var collectCandidates: [CollectCandidate]?

    static let maxFavorites = 6

    let configuration: WKWebViewConfiguration
    let settings: SettingsStore
    let history: HistoryStore
    let shortcuts: ShortcutStore
    let claude: ClaudeService
    let finder: FinderStore
    private lazy var coordinator = WebCoordinator(model: self)

    private struct Persisted: Codable { var favorites: [SavedTab]; var pinned: [SavedTab]; var folders: [Folder] }

    init(settings: SettingsStore, history: HistoryStore, shortcuts: ShortcutStore,
         claude: ClaudeService, finder: FinderStore) {
        self.settings = settings; self.history = history; self.shortcuts = shortcuts
        self.claude = claude; self.finder = finder
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        self.configuration = config

        if let saved = Storage.loadJSON(Persisted.self, from: "tabs.json") {
            favorites = saved.favorites; pinned = saved.pinned; folders = saved.folders
        }

        // Claude's page bridge — link hovers and selections.
        config.userContentController.addUserScript(PageBridge.userScript(
            hoverDelayMs: Int(settings.linkHoverDelay * 1000), hoverEnabled: settings.linkHoverEnabled))
        config.userContentController.add(coordinator, name: PageBridge.handlerName)

        hoverObserver = NotificationCenter.default.addObserver(
            forName: .hoverSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHoverSettings() }
        }
    }

    private var hoverObserver: (any NSObjectProtocol)?

    /// Push changed hover settings to future pages (rebuilt user script) and to
    /// every live page (window globals the script reads at event time).
    private func applyHoverSettings() {
        configuration.userContentController.removeAllUserScripts()
        configuration.userContentController.addUserScript(PageBridge.userScript(
            hoverDelayMs: Int(settings.linkHoverDelay * 1000), hoverEnabled: settings.linkHoverEnabled))
        let js = "window.__runeHoverMs = \(Int(settings.linkHoverDelay * 1000));"
            + "window.__runeHoverOff = \(settings.linkHoverEnabled ? "false" : "true");"
        for tab in sessionTabs { tab.webView.evaluateJavaScript(js) }
        for tab in openTabs.values { tab.webView.evaluateJavaScript(js) }
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
        let webView = RuneWebView(frame: .zero, configuration: configuration ?? self.configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.onSaveToFinder = { [weak self, weak webView] url, _ in
            self?.saveToFinder(assetURL: url, from: webView)
        }
        return webView
    }

    // MARK: Finder capture

    /// The one save path every capture flow funnels through: download, toast,
    /// optional Claude auto-tagging.
    func saveToFinder(assetURL: URL, from webView: WKWebView?, tags: [String] = [], quiet: Bool = false) {
        let source = webView?.url?.absoluteString ?? ""
        let title = webView?.title ?? ""
        Task { @MainActor in
            do {
                let item = try await finder.save(assetURL: assetURL, sourceURL: source,
                                                 sourceTitle: title, tags: tags)
                if !quiet { NotificationCenter.default.post(name: .finderToast, object: "Saved to Finder") }
                if settings.finderAutoTag {
                    let claude = self.claude, finder = self.finder
                    Task { await finder.autoTag(item, using: claude) }
                }
            } catch {
                if !quiet {
                    NotificationCenter.default.post(name: .finderToast,
                                                    object: "Couldn't save — \(error.localizedDescription)")
                }
            }
        }
    }

    /// ⌥S: save whatever image/video sits under the cursor right now.
    func saveMediaUnderCursor() {
        guard let tab = activeTab else { return }
        tab.webView.evaluateJavaScript("JSON.stringify(window.__runeMedia ? window.__runeMedia() : null)") { [weak self, weak tab] result, _ in
            guard let json = result as? String, json != "null",
                  let data = json.data(using: .utf8),
                  let info = try? JSONDecoder().decode([String: String].self, from: data),
                  let src = info["src"], let url = URL(string: src) else {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .finderToast, object: "No image under the cursor")
                }
                return
            }
            Task { @MainActor in self?.saveToFinder(assetURL: url, from: tab?.webView) }
        }
    }

    /// ⇧⌘S: scan the page and open the batch-collect sheet.
    func collectFromPage() {
        guard let tab = activeTab else { return }
        tab.webView.evaluateJavaScript(PageBridge.collectMediaJS) { [weak self] result, _ in
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let found = try? JSONDecoder().decode([CollectCandidate].self, from: data) else { return }
            Task { @MainActor in
                guard let self else { return }
                let min = Int(self.settings.finderMinCollectSize)
                let kept = found.filter { $0.w == 0 || ($0.w >= min && $0.h >= min) }
                if kept.isEmpty {
                    NotificationCenter.default.post(name: .finderToast, object: "Nothing collectable on this page")
                } else {
                    self.collectCandidates = kept
                }
            }
        }
    }

    /// Capture the visible page as an image item.
    func capturePage() {
        guard let tab = activeTab else { return }
        tab.webView.takeSnapshot(with: nil) { [weak self, weak tab] image, _ in
            guard let self, let tab, let image, let png = image.png else { return }
            Task { @MainActor in
                let name = tab.title.isEmpty ? "Page Capture" : tab.title
                if (try? await self.finder.save(data: png, ext: "png", fileName: name,
                                                sourceURL: tab.urlString, sourceTitle: tab.title)) != nil {
                    NotificationCenter.default.post(name: .finderToast, object: "Captured page to Finder")
                }
            }
        }
    }

    // MARK: Session tabs

    /// URL of the most recently closed tab (for the "last closed" new-tab behavior).
    private(set) var lastClosedURL: String?

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true) -> Tab {
        // ⌘T with a start page already open focuses it instead of stacking blanks.
        if url == nil, settings.newTabBehavior == .startPage,
           let empty = sessionTabs.first(where: { $0.urlString.isEmpty && !$0.isLoading }) {
            if select { self.select(.session(empty.id)) }
            NotificationCenter.default.post(name: .focusStartPage, object: nil)
            return empty
        }
        let tab = Tab(webView: makeWebView())
        let target = url ?? defaultNewTabURL()
        insertSession(tab)
        if let target { tab.load(target) }
        if select { self.select(.session(tab.id)) }
        return tab
    }

    private func defaultNewTabURL() -> URL? {
        switch settings.newTabBehavior {
        case .startPage: nil
        case .homePage: resolve(settings.homePageURL)
        case .duplicateCurrent: activeTab?.webView.url
        case .lastClosed: lastClosedURL.flatMap { URL(string: $0) }
        }
    }

    private func insertSession(_ tab: Tab) {
        if settings.newTabPlacement == .nextToActive,
           case .session(let id)? = selection,
           let i = sessionTabs.firstIndex(where: { $0.id == id }) {
            sessionTabs.insert(tab, at: i + 1)
        } else {
            sessionTabs.append(tab)
        }
    }

    func adoptPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = makeWebView(configuration: configuration)
        let tab = Tab(webView: webView)
        insertSession(tab)
        select(.session(tab.id))
        return webView
    }

    // MARK: Selection

    func select(_ new: Selection) {
        showingFinder = false
        guard new != selection else { return }
        if settings.autoPiP != .off, let current = activeTab { current.requestPiPIfPlaying() }
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
        if settings.autoPiPReturnInline { activeTab?.exitPiPIfActive() }
    }

    func savedTab(_ id: UUID) -> SavedTab? {
        favorites.first { $0.id == id } ?? pinned.first { $0.id == id }
    }

    // MARK: Close / unload

    func close(session tab: Tab) {
        if let url = tab.webView.url { lastClosedURL = url.absoluteString }
        tab.webView.stopLoading()
        tab.webView.closeAllMediaPresentations {}   // don't leak a PiP window
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
        if let url = openTabs[savedID]?.webView.url { lastClosedURL = url.absoluteString }
        openTabs[savedID]?.webView.stopLoading()
        openTabs[savedID]?.webView.closeAllMediaPresentations {}   // don't leak a PiP window
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
        guard let savedID = tab.savedID, let png = image.png,
              savedTab(savedID)?.faviconPNG != png else { return }   // skip a tabs.json write when unchanged
        updateSaved(savedID) { $0.faviconPNG = png }
    }

    // MARK: Navigation

    func navigate(_ input: String) {
        guard let url = resolve(input) else { return }
        showingFinder = false   // typing an address means "browse", not "browse the library"
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

    /// "that article about titanium frames" → the actual URL, chosen by Claude
    /// from your history. Local prediction handles prefixes; this handles intent.
    func findInHistory(_ query: String) async throws -> URL? {
        let candidates = history.entries
            .sorted { ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited) }
            .prefix(120)
        guard !candidates.isEmpty else { return nil }

        let list = candidates.enumerated()
            .map { "\($0.offset). \($0.element.title) — \($0.element.url)" }
            .joined(separator: "\n")

        let answer = try await claude.complete(
            system: "You match a person's vague description to a page in their browsing history. "
                + "Reply with ONLY the number of the best match, or NONE if nothing fits.",
            user: "History:\n\(list)\n\nThey're looking for: \(query)",
            maxTokens: 12, effort: "low")

        let digits = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(while: \.isNumber)
        guard let index = Int(digits), candidates.indices.contains(candidates.startIndex + index) else {
            return nil
        }
        return URL(string: Array(candidates)[index].url)
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
