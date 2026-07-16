import Combine
import SwiftUI
import WebKit

// MARK: - Persistent sidebar entries

/// A saved sidebar entry (a favorite or a pinned tab). Persists across launches.
///
/// Tabs carry no colour of their own: a tab is identified by its favicon, and
/// colour belongs to the folder that groups it. Older tabs.json files may still
/// hold a `colorHex` key — the decoder ignores it.
struct SavedTab: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    var name: String
    var customName = false
    var faviconPNG: Data? = nil
    var folderID: UUID? = nil       // pinned only; favorites can't be foldered
}

/// A space: a theme and the tabs that belong with it. Work, home, a project —
/// each keeps its own shelf and its own look, and switching between them
/// doesn't disturb what the other was doing.
struct Space: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "square.stack"
    /// Name of the theme preset this space wears. nil = leave the theme alone,
    /// which is what every space does until you give it one.
    var preset: String?
    var favorites: [SavedTab] = []
    var pinned: [SavedTab] = []
    var folders: [Folder] = []
}

/// The only coloured thing in the sidebar.
struct Folder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "folder.fill"
    var collapsed = false
    var colorHex: String? = nil     // nil = the appearance accent
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

    /// Reported by the page bridge — the tab is making noise right now.
    @Published var isPlayingAudio = false
    @Published var muted = false

    @Published var customName: String?

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

    // MARK: Audio

    func toggleMute() { muted.toggle(); applyMuteToPage() }

    /// Push the mute flag into the live document. Called again after every
    /// navigation — the bridge is injected per page, so a fresh document knows
    /// nothing about a tab that was muted before.
    func applyMuteToPage() {
        webView.evaluateJavaScript("window.__runeMute && window.__runeMute(\(muted))")
    }

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
    // Persistent. These are the *current space's* shelf: switching spaces swaps
    // them, which is why nothing else in the app had to learn what a space is.
    @Published var favorites: [SavedTab] = []      // max 6, no folders
    @Published var pinned: [SavedTab] = []
    @Published var folders: [Folder] = []
    @Published var spaces: [Space] = []
    @Published private(set) var currentSpaceID = UUID()
    // Ephemeral (this session only)
    @Published var sessionTabs: [Tab] = []
    @Published var openTabs: [UUID: Tab] = [:]     // savedID -> live tab
    @Published var selection: Selection?
    /// The second pane, when you're in Split View. A split is two tabs shown at
    /// once, not a new kind of tab — so it's just a second selection.
    @Published var splitSelection: Selection?
    /// Which pane commands act on. Meaningless without a split, and reset
    /// whenever one closes.
    @Published var focusedPane: Pane = .primary
    @Published var sidebarVisible = true
    /// Batch-collect candidates; non-nil presents the collect sheet.
    @Published var collectCandidates: [CollectCandidate]?

    static let maxFavorites = 6

    let configuration: WKWebViewConfiguration
    let settings: SettingsStore
    let history: HistoryStore
    let shortcuts: ShortcutStore
    /// Rune's AI, whichever model is behind it today.
    let ai: AIService
    let finder: FinderStore
    let downloads: DownloadStore
    let sites: SiteSettings
    let blocker: ContentBlocker
    /// A space wears a theme, so the model needs to be able to put one on.
    let appearance: AppearanceStore

    /// A private window: nothing it does touches the disk. Its web views share
    /// no cookies or cache with the rest of Rune, its pages never reach
    /// history, and it starts with no favorites or pinned tabs to leak.
    let isPrivate: Bool

    private lazy var coordinator = WebCoordinator(model: self)

    /// tabs.json, both shapes. Before Spaces there was one unnamed shelf at the
    /// top level; those keys stay decodable so an existing library migrates
    /// into its first space instead of vanishing.
    private struct Persisted: Codable {
        var spaces: [Space]?
        var currentSpaceID: UUID?
        // Pre-Spaces layout.
        var favorites: [SavedTab]?
        var pinned: [SavedTab]?
        var folders: [Folder]?
    }

    init(settings: SettingsStore, history: HistoryStore, shortcuts: ShortcutStore,
         ai: AIService, finder: FinderStore, downloads: DownloadStore,
         sites: SiteSettings, blocker: ContentBlocker, appearance: AppearanceStore,
         isPrivate: Bool = false) {
        self.settings = settings; self.history = history; self.shortcuts = shortcuts
        self.ai = ai; self.finder = finder; self.downloads = downloads
        self.sites = sites; self.blocker = blocker; self.appearance = appearance
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        self.configuration = config

        loadSpaces()

        // Claude's page bridge — link hovers and selections.
        config.userContentController.addUserScript(PageBridge.userScript(
            hoverDelayMs: Int(settings.linkHoverDelay * 1000), hoverEnabled: settings.linkHoverEnabled))
        config.userContentController.add(coordinator, name: PageBridge.handlerName)

        hoverObserver = NotificationCenter.default.addObserver(
            forName: .hoverSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHoverSettings() }
        }
        blockingObserver = NotificationCenter.default.addObserver(
            forName: .blockingSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadBlocking() }
        }
        // Rules attach to the configuration every web view is built from, so
        // this covers tabs that don't exist yet — including a private window's,
        // which gets blocking for free.
        reloadBlocking()
    }

    private var hoverObserver: (any NSObjectProtocol)?
    private var blockingObserver: (any NSObjectProtocol)?

    /// Recompile if the rules changed, then hand them to the configuration and
    /// to every page already open.
    func reloadBlocking() {
        Task { @MainActor in
            await blocker.reload()
            blocker.apply(to: configuration.userContentController)
            for tab in allTabs { blocker.apply(to: tab.webView.configuration.userContentController) }
        }
    }

    /// Every live web view this window owns.
    var allTabs: [Tab] { sessionTabs + Array(openTabs.values) }

    /// Push changed hover settings to future pages (rebuilt user script) and to
    /// every live page (window globals the script reads at event time).
    private func applyHoverSettings() {
        configuration.userContentController.removeAllUserScripts()
        configuration.userContentController.addUserScript(PageBridge.userScript(
            hoverDelayMs: Int(settings.linkHoverDelay * 1000), hoverEnabled: settings.linkHoverEnabled))
        let js = "window.__runeHoverMs = \(Int(settings.linkHoverDelay * 1000));"
            + "window.__runeHoverOff = \(settings.linkHoverEnabled ? "false" : "true");"
        for tab in allTabs { tab.webView.evaluateJavaScript(js) }
    }

    // MARK: Spaces

    /// A space's live tabs while you're somewhere else. Parked, not closed:
    /// coming back to a space must not reload it, which is the same promise a
    /// tab makes and the reason a space is worth having at all.
    private struct Parked {
        var session: [Tab] = []
        var open: [UUID: Tab] = [:]
        var selection: Selection?
        var split: Selection?
    }
    private var parked: [UUID: Parked] = [:]

    var currentSpace: Space? { spaces.first { $0.id == currentSpaceID } }

    private func loadSpaces() {
        // A private window is its own world and keeps nothing, so it gets one
        // space that never touches disk.
        guard !isPrivate else {
            let only = Space(name: "Private")
            spaces = [only]; currentSpaceID = only.id
            return
        }
        let saved = Storage.loadJSON(Persisted.self, from: "tabs.json")
        if let existing = saved?.spaces, !existing.isEmpty {
            spaces = existing
            currentSpaceID = saved?.currentSpaceID.flatMap { id in
                existing.contains { $0.id == id } ? id : nil
            } ?? existing[0].id
        } else {
            // Everything you had before Spaces becomes your first one.
            let first = Space(name: "Home",
                              favorites: saved?.favorites ?? [],
                              pinned: saved?.pinned ?? [],
                              folders: saved?.folders ?? [])
            spaces = [first]
            currentSpaceID = first.id
        }
        adoptCurrentSpace()
    }

    /// Bring the current space's shelf into the published arrays everything
    /// else reads. Spaces are a swap, which is why no other code had to learn
    /// what a space is.
    private func adoptCurrentSpace() {
        guard let space = currentSpace else { return }
        favorites = space.favorites
        pinned = space.pinned
        folders = space.folders
    }

    /// And back the other way, before anything is written.
    private func syncCurrentSpace() {
        guard let i = spaces.firstIndex(where: { $0.id == currentSpaceID }) else { return }
        spaces[i].favorites = favorites
        spaces[i].pinned = pinned
        spaces[i].folders = folders
    }

    func switchTo(space id: UUID) {
        guard id != currentSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        // Park what's on screen — including which pane was showing what.
        syncCurrentSpace()
        parked[currentSpaceID] = Parked(session: sessionTabs, open: openTabs,
                                        selection: selection, split: splitSelection)

        currentSpaceID = id
        let restored = parked[id] ?? Parked()
        sessionTabs = restored.session
        openTabs = restored.open
        selection = restored.selection
        splitSelection = restored.split
        focusedPane = restored.split == nil ? .primary : focusedPane
        adoptCurrentSpace()
        wearPreset()

        if sessionTabs.isEmpty, selection == nil { newTab() }
        persist()
    }

    /// A space wears a theme. One without a preset leaves whatever you're
    /// wearing alone, so this stays opt-in per space.
    ///
    /// A preset is the whole Appearance — which is right when you pick one
    /// yourself in Settings, and wrong here: changing rooms shouldn't
    /// rearrange your buttons. So a space changes how Rune *looks* and leaves
    /// the things that are muscle memory where you put them.
    private func wearPreset() {
        guard let name = currentSpace?.preset,
              let preset = appearance.presets.first(where: { $0.name == name }) else { return }
        var next = preset.appearance
        let current = appearance.appearance
        next.toolbarButtons = current.toolbarButtons
        next.compactAddressBar = current.compactAddressBar
        next.sidebarOnRight = current.sidebarOnRight
        next.hideTrafficLights = current.hideTrafficLights
        appearance.appearance = next
    }

    @discardableResult
    func addSpace(name: String = "New Space") -> Space {
        let space = Space(name: name)
        spaces.append(space)
        persist()
        return space
    }

    /// Always leaves one: a browser with no space has nowhere to put a tab.
    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1 else { return }
        if currentSpaceID == id, let other = spaces.first(where: { $0.id != id }) {
            switchTo(space: other.id)
        }
        // Its tabs die with it — nothing parked should outlive its space.
        if let gone = parked[id] {
            for tab in gone.session + Array(gone.open.values) {
                tab.webView.stopLoading()
                tab.webView.closeAllMediaPresentations {}
            }
        }
        parked[id] = nil
        spaces.removeAll { $0.id == id }
        persist()
    }

    func updateSpace(_ id: UUID, _ mutate: (inout Space) -> Void) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&spaces[i])
        if id == currentSpaceID { wearPreset() }
        persist()
    }

    func selectAdjacentSpace(_ delta: Int) {
        guard spaces.count > 1,
              let i = spaces.firstIndex(where: { $0.id == currentSpaceID }) else { return }
        switchTo(space: spaces[(i + delta + spaces.count) % spaces.count].id)
    }

    // MARK: Storage

    /// tabs.json carries every saved favicon, so it is not a cheap write — and
    /// the things that call this arrive in bursts (dragging a folder's colour
    /// picker, reordering rows). Coalesce them; AppDelegate flushes on quit.
    /// Same bargain as history: at most a second of changes at risk on a crash.
    private var saveTask: Task<Void, Never>?

    func persist() {
        guard !isPrivate else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel(); saveTask = nil
        guard !isPrivate else { return }
        syncCurrentSpace()
        Storage.saveJSON(Persisted(spaces: spaces, currentSpaceID: currentSpaceID), to: "tabs.json")
    }

    // MARK: Live tab lookup

    /// The pane a command lands in. Without a split there is only `.primary`,
    /// which is why every command written before Split View still reads
    /// `activeTab` and means the right thing.
    enum Pane: Equatable { case primary, secondary }

    /// What's showing in the pane you last touched.
    var activeTab: Tab? { currentSelection.flatMap(tab(for:)) }

    var currentSelection: Selection? {
        focusedPane == .secondary ? splitSelection : selection
    }

    private var otherSelection: Selection? {
        focusedPane == .secondary ? selection : splitSelection
    }

    var isSplit: Bool { splitSelection != nil }

    func selection(for pane: Pane) -> Selection? {
        pane == .secondary ? splitSelection : selection
    }

    func tab(for pane: Pane) -> Tab? { selection(for: pane).flatMap(tab(for:)) }

    func tab(for selection: Selection) -> Tab? {
        switch selection {
        case .session(let id): sessionTabs.first { $0.id == id }
        case .saved(let id): openTabs[id]
        }
    }

    // MARK: Split View

    /// Split the view, or close it. The second pane starts on the tab next
    /// along — splitting to look at the same page twice isn't useful, and a
    /// live web view can't be in both panes anyway.
    func toggleSplit() {
        guard !isSplit else { closeSplit(); return }
        let taken = selection
        if let other = sessionTabs.first(where: { Selection.session($0.id) != taken }) {
            splitSelection = .session(other.id)
        } else {
            splitSelection = .session(newTab(select: false).id)
        }
        focusedPane = .secondary
    }

    func closeSplit() {
        splitSelection = nil
        focusedPane = .primary
    }

    /// A web view has one superview, so the same tab can't be in both panes.
    /// Asking for the one that's already opposite means you want them swapped.
    private func swapPanes() {
        let primary = selection
        selection = splitSelection
        splitSelection = primary
    }

    /// Keep a closed or unloaded tab from leaving a pane pointing at nothing.
    private func forget(_ gone: Selection) {
        if splitSelection == gone { closeSplit() }
        if selection == gone {
            selection = splitSelection ?? sessionTabs.last.map { .session($0.id) }
                ?? pinned.first.map { .saved($0.id) }
            if selection == splitSelection { closeSplit() }
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
        // Saving the same asset twice shouldn't clone it.
        if finder.items.contains(where: { $0.assetURL == assetURL.absoluteString }) {
            if !quiet { NotificationCenter.default.post(name: .finderToast, object: "Already in Finder") }
            return
        }
        let source = webView?.url?.absoluteString ?? ""
        let title = webView?.title ?? ""
        Task { @MainActor in
            do {
                let item = try await finder.save(assetURL: assetURL, sourceURL: source,
                                                 sourceTitle: title, tags: tags)
                if !quiet { NotificationCenter.default.post(name: .finderToast, object: "Saved to Finder") }
                if settings.finderAutoTag {
                    let ai = self.ai, finder = self.finder
                    Task { await finder.autoTag(item, using: ai) }
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

    /// ⇧⌘S: scan the page and open the batch-collect sheet. Retries once —
    /// invoked right after navigation, images may not have loaded yet.
    func collectFromPage(retried: Bool = false) {
        guard let tab = activeTab else { return }
        tab.webView.evaluateJavaScript(PageBridge.collectMediaJS) { [weak self] result, _ in
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let found = try? JSONDecoder().decode([CollectCandidate].self, from: data) else { return }
            Task { @MainActor in
                guard let self else { return }
                let min = Int(self.settings.finderMinCollectSize)
                let kept = found.filter { $0.w == 0 || ($0.w >= min && $0.h >= min) }
                if kept.isEmpty {
                    if retried {
                        NotificationCenter.default.post(name: .finderToast, object: "Nothing collectable on this page")
                    } else {
                        try? await Task.sleep(for: .seconds(1.5))
                        self.collectFromPage(retried: true)
                    }
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

    /// Tabs you've closed this session, newest last. ⇧⌘T pops it, and the
    /// "last closed" new-tab behavior reads the top.
    private(set) var closedURLs: [String] = []
    private static let maxClosed = 25

    var lastClosedURL: String? { closedURLs.last }

    private func rememberClosed(_ url: URL?) {
        // A private window leaves no trail, not even an undo stack.
        guard !isPrivate, let url, url.scheme?.hasPrefix("http") == true else { return }
        closedURLs.append(url.absoluteString)
        if closedURLs.count > Self.maxClosed { closedURLs.removeFirst() }
    }

    /// ⇧⌘T — bring back the tab you just closed, then the one before it.
    func undoCloseTab() {
        guard let url = closedURLs.popLast().flatMap(URL.init(string:)) else { return }
        newTab(url: url)
    }

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true) -> Tab {
        // ⌘T with a start page already open focuses it instead of stacking blanks.
        if url == nil, settings.newTabBehavior == .startPage,
           let empty = sessionTabs.first(where: { $0.urlString.isEmpty && !$0.isLoading }) {
            if select { self.select(.session(empty.id)) }
            NotificationCenter.default.post(name: .focusStartPage, object: self)
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
        // The overlay asks first, then opens the tab with an answer already in
        // hand — so a tab made this way is only ever made with a URL.
        case .addressOverlay: nil
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

    func adoptPopup(configuration: WKWebViewConfiguration, select: Bool = true) -> WKWebView {
        let webView = makeWebView(configuration: configuration)
        let tab = Tab(webView: webView)
        insertSession(tab)
        if select { self.select(.session(tab.id)) }
        return webView
    }

    // MARK: Session restore

    /// Session tabs are ephemeral by design; this is the opt-in that carries
    /// them over a quit. Only addresses are kept — a restored tab loads fresh.
    func persistSession() {
        guard !isPrivate else { return }
        guard settings.restoreSession else { Storage.remove("session.json"); return }
        Storage.saveJSON(sessionTabs.compactMap { $0.webView.url?.absoluteString }, to: "session.json")
    }

    /// Reopen last launch's tabs. False when there was nothing to restore, so
    /// the caller can fall back to opening a fresh tab.
    @discardableResult
    func restoreSession() -> Bool {
        guard !isPrivate, settings.restoreSession,
              let urls = Storage.loadJSON([String].self, from: "session.json")
        else { return false }
        for url in urls.compactMap(URL.init(string:)) { newTab(url: url, select: false) }
        guard let first = sessionTabs.first else { return false }
        select(.session(first.id))
        return true
    }

    // MARK: Selection

    func select(_ new: Selection) {
        guard new != currentSelection else { return }
        // Already opposite: you can't pull it out of the other pane (one web
        // view, one superview), so trade places instead.
        if new == otherSelection { swapPanes(); return }

        if settings.autoPiP != .off, let current = activeTab { current.requestPiPIfPlaying() }
        if case .saved(let id) = new, openTabs[id] == nil, let saved = savedTab(id) {
            let tab = Tab(webView: makeWebView())
            tab.savedID = id
            tab.customName = saved.customName ? saved.name : nil
            if let png = saved.faviconPNG { tab.favicon = NSImage(data: png) }
            openTabs[id] = tab
            if let url = URL(string: saved.url) { tab.load(url) }
        }
        // A sidebar click lands in the pane you last touched.
        if focusedPane == .secondary, isSplit { splitSelection = new } else { selection = new }
        if settings.autoPiPReturnInline { activeTab?.exitPiPIfActive() }
    }

    func savedTab(_ id: UUID) -> SavedTab? {
        favorites.first { $0.id == id } ?? pinned.first { $0.id == id }
    }

    // MARK: Close / unload

    func close(session tab: Tab) {
        rememberClosed(tab.webView.url)
        tab.webView.stopLoading()
        tab.webView.closeAllMediaPresentations {}   // don't leak a PiP window
        sessionTabs.removeAll { $0.id == tab.id }
        forget(.session(tab.id))
    }

    func closeActive() {
        switch currentSelection {
        case .session(let id): if let t = sessionTabs.first(where: { $0.id == id }) { close(session: t) }
        case .saved(let id): unload(savedID: id)
        case nil: break
        }
    }

    /// Unload a saved entry's live tab (keeps the row). Deliberately not on the
    /// undo stack — the row is still in the sidebar, so nothing was lost.
    func unload(savedID: UUID) {
        openTabs[savedID]?.webView.stopLoading()
        openTabs[savedID]?.webView.closeAllMediaPresentations {}   // don't leak a PiP window
        openTabs[savedID] = nil
        forget(.saved(savedID))
    }

    // MARK: Favorites / pinning

    var canAddFavorite: Bool { favorites.count < Self.maxFavorites }

    func addFavorite(from tab: Tab) {
        guard canAddFavorite, let url = tab.webView.url else { return }
        let saved = SavedTab(url: url.absoluteString, name: tab.displayName,
                             faviconPNG: tab.favicon?.png)
        favorites.append(saved)
        rebind(tab, to: saved.id); persist()
    }

    func pin(_ tab: Tab) {
        guard let url = tab.webView.url else { return }
        let saved = SavedTab(url: url.absoluteString, name: tab.displayName,
                             faviconPNG: tab.favicon?.png)
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
    func setFolderColor(_ id: UUID, _ hex: String?) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].colorHex = hex; persist()
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
                                 faviconPNG: tab.favicon?.png)
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
        let tab = activeTab ?? newTab()
        tab.load(url)
    }
    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }
    func reload() { activeTab?.webView.reload() }
    func recordVisit(_ url: URL, title: String) {
        guard !isPrivate else { return }
        history.record(url: url, title: title)
    }

    // MARK: Zoom

    /// ⌘+ / ⌘− / ⌘0. The level belongs to the site rather than the tab, so
    /// every open tab on that host moves together and the next visit remembers.
    func zoom(_ change: ZoomChange) {
        guard let host = activeTab?.webView.url?.host else { return }
        sites.setZoom(change.applied(to: sites.zoom(for: host)), for: host)
        for tab in allTabs where tab.webView.url?.host == host { applyZoom(to: tab) }
    }

    /// Put a tab at its site's remembered level. Called on every commit, so it
    /// has to no-op cheaply for the overwhelmingly common 100% case.
    func applyZoom(to tab: Tab) {
        let level = tab.webView.url?.host.map { sites.zoom(for: $0) } ?? 1
        if abs(tab.webView.pageZoom - level) > 0.001 { tab.webView.pageZoom = level }
    }

    // MARK: Content blocking

    /// Is blocking on for the site you're looking at?
    var blocksActiveSite: Bool {
        guard let host = activeTab?.webView.url?.host else { return settings.blockContent }
        return settings.blockContent && sites.blocks(host, default: true)
    }

    /// "Don't block on this site". Recompiling is what applies it — exceptions
    /// live inside the rule list, so nothing is checked per request. Reloads the
    /// page after, since a rule change can't reach requests already made.
    func toggleBlockingForActiveSite() {
        guard let host = activeTab?.webView.url?.host else { return }
        let blocking = sites.blocks(host, default: true)
        // Back to nil rather than `true` when re-enabling: no opinion is not the
        // same as an opinion that happens to match, and it keeps sites.json small.
        sites.setBlocking(blocking ? false : nil, for: host)
        reloadBlocking()
        NotificationCenter.default.post(name: .finderToast,
                                        object: blocking ? "Not blocking on \(host)" : "Blocking on \(host)")
        reload()
    }

    // MARK: Page actions

    /// The address behind a sidebar row, loaded or not — a pinned tab knows
    /// where it points before you ever open it.
    func url(for selection: Selection) -> String? {
        if let live = tab(for: selection)?.webView.url { return live.absoluteString }
        if case .saved(let id) = selection { return savedTab(id)?.url }
        return nil
    }

    /// ⇧⌘C — the current address on the clipboard.
    func copyURL() {
        if let url = activeTab?.webView.url?.absoluteString { copy(url) }
    }

    func copy(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        NotificationCenter.default.post(name: .finderToast, object: "Copied link")
    }

    /// ⌘P. "Save as PDF" lives inside the system print panel, so this one
    /// command covers printing and exporting both.
    func printPage() {
        guard let tab = activeTab, let window = NSApp.keyWindow else { return }
        let operation = tab.webView.printOperation(with: NSPrintInfo.shared)
        operation.printPanel.options.insert([.showsPaperSize, .showsOrientation, .showsScaling])
        operation.view?.frame = tab.webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func selectAdjacentSession(_ delta: Int) {
        guard !sessionTabs.isEmpty else { return }
        let index = sessionTabs.firstIndex { selection == .session($0.id) } ?? 0
        let next = (index + delta + sessionTabs.count) % sessionTabs.count
        select(.session(sessionTabs[next].id))
    }

    /// "that article about titanium frames" → the actual URL, picked out of your
    /// history by whichever model is running. Local prediction handles prefixes;
    /// this handles intent.
    func findInHistory(_ query: String) async throws -> URL? {
        let candidates = history.entries
            .sorted { ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited) }
            .prefix(120)
        guard !candidates.isEmpty else { return nil }

        let list = candidates.enumerated()
            .map { "\($0.offset). \($0.element.title) — \($0.element.url)" }
            .joined(separator: "\n")

        let answer = try await ai.complete(
            system: "You match a person's vague description to a page in their browsing history. "
                + "Reply with ONLY the number of the best match, or NONE if nothing fits.",
            user: "History:\n\(list)\n\nThey're looking for: \(query)",
            maxTokens: 12, effort: .low)

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
        // An explicit scheme means you typed a destination, whatever else it
        // looks like. This has to come first: "http://localhost:8765" has no
        // dot in it, and the guess below would otherwise hand it to Google.
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        if text.contains(" ") || (!text.contains(".") && text != "localhost") {
            return settings.searchEngine.url(for: text)
        }
        return URL(string: "https://\(text)")
    }
}

extension Notification {
    /// Overlays (the palette, the find bar, the downloads list) live inside a
    /// BrowserView and are asked for by broadcast. The sender names the model
    /// it meant, so a second browser window ignores what wasn't for it.
    func aimed(at model: BrowserModel) -> Bool { (object as? BrowserModel) === model }
}

extension NSImage {
    var png: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
