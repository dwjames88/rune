import AppKit
import SwiftUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = SettingsStore()
    let history = HistoryStore()
    let shortcuts = ShortcutStore()
    let appearance = AppearanceStore()
    let claude = ClaudeService()
    let finder = FinderStore()
    let downloads = DownloadStore()
    let sites = SiteSettings()
    lazy var blocker = ContentBlocker(settings: settings, sites: sites)
    lazy var ai = AIService(claude: claude, settings: settings)
    lazy var model = BrowserModel(settings: settings, history: history, shortcuts: shortcuts,
                                  ai: ai, finder: finder, downloads: downloads,
                                  sites: sites, blocker: blocker, appearance: appearance)
    lazy var settingsWindow = SettingsWindowController(
        settings: settings, shortcuts: shortcuts, history: history, appearance: appearance,
        ai: ai, sites: sites, model: { [unowned self] in self.model })
    lazy var finderWindow = FinderWindowController(model: model, appearance: appearance)
    private var window: NSWindow?

    /// Every browser window and the model behind it — the main one, plus any
    /// private windows. Stays small, so a linear lookup is the right tool.
    private var browsers: [(window: NSWindow, model: BrowserModel)] = []

    /// Glances and segments. They hold themselves open (isReleasedWhenClosed is
    /// off) and drop out of here when their window goes.
    private var detached: [DetachedWindow] = []

    /// Commands act on the browser window you're actually looking at, which is
    /// what makes a private window feel like its own browser rather than a
    /// second view onto the main one.
    private var frontModel: BrowserModel {
        if let key = NSApp.keyWindow, let hit = browsers.first(where: { $0.window === key }) {
            return hit.model
        }
        return model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let window = makeBrowserWindow(for: model)
        // Reopen at the last size/position; first launch gets a generous default.
        // Clamp to minSize — frames autosaved by older builds could be tiny.
        if window.setFrameUsingName("RuneMainWindow") {
            var frame = window.frame
            if frame.width < window.minSize.width || frame.height < window.minSize.height {
                frame.size.width = max(frame.width, window.minSize.width)
                frame.size.height = max(frame.height, window.minSize.height)
                window.setFrame(frame, display: false)
            }
        } else {
            window.setContentSize(NSSize(width: 1280, height: 820))
            window.center()
        }
        window.setFrameAutosaveName("RuneMainWindow")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        applyWindowChrome()

        NSApp.activate(ignoringOtherApps: true)
        // Restoring is opt-in; without it, or with nothing to restore, you get
        // the usual empty tab.
        if !model.restoreSession() { model.newTab() }

        if ProcessInfo.processInfo.environment["RUNE_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.settingsWindow.show() }
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(buildMenu), name: .shortcutsChanged, object: nil)
        center.addObserver(self, selector: #selector(applyWindowChrome), name: .appearanceChanged, object: nil)
        center.addObserver(self, selector: #selector(frontBrowserWindow), name: .frontBrowserWindow, object: nil)
        center.addObserver(forName: .glanceLink, object: nil, queue: .main) { [weak self] note in
            // Pull the URL out before hopping: a Notification isn't Sendable,
            // and a URL is.
            let url = note.object as? URL
            MainActor.assumeIsolated {
                guard let url else { return }
                self?.detach(url, floating: true)
            }
        }

        // System-wide capture: "Save to Rune Finder" in every app's Services
        // menu (declared in Info.plist; handled below).
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        FinderQuickAction.installIfNeeded()

        // The first minute of a public build: offer default-browser once,
        // after the window has had a moment to be a browser.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.offerDefaultBrowser() }
    }

    /// Asked exactly once, ever — and never when Rune already is the default.
    /// macOS puts up its own confirmation on top of this, which is the real
    /// consent; this is just Rune raising its hand.
    private func offerDefaultBrowser() {
        let key = "rune.offeredDefaultBrowser"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if let http = URL(string: "http://example.com"),
           let current = NSWorkspace.shared.urlForApplication(toOpen: http),
           current == Bundle.main.bundleURL { return }
        let alert = NSAlert()
        alert.messageText = "Make Rune your default browser?"
        alert.informativeText = "Links from other apps will open here — in their own window, so they never barge into your tabs. macOS will ask you to confirm."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
        model.persistSession()
        history.flush()
        appearance.flush()
        sites.flush()
        settings.flush()
    }

    // MARK: Browser windows

    /// The main window and every private window are the same thing built around
    /// a different model.
    private func makeBrowserWindow(for browserModel: BrowserModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = browserModel.isPrivate ? "Private" : "Rune"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let hosting = NSHostingController(
            rootView: BrowserView(model: browserModel, dispatch: { [weak self] in self?.dispatch($0) })
                .environmentObject(appearance))
        hosting.sizingOptions = []   // never let SwiftUI shrink the window to its ideal size
        window.contentViewController = hosting
        window.minSize = NSSize(width: 900, height: 600)
        window.delegate = self
        // A window built this way releases itself on close, which under ARC is
        // one release too many once `browsers` holds it too — closing a private
        // window would take the whole app down with it.
        window.isReleasedWhenClosed = false
        TitlebarRemover.strip(window)
        browsers.append((window, browserModel))
        return window
    }

    /// One page, one window. Floating = a glance: peek a link over what you're
    /// reading. Not floating = a segment: a link another app handed us, which
    /// deserves a window rather than a place in your tabs.
    private func detach(_ url: URL, floating: Bool) {
        let owner = frontModel
        detached.append(DetachedWindow(
            tab: owner.detachedTab(url: url),
            floating: floating,
            appearance: appearance,
            promote: { [weak self] tab in
                // Keep it: the page moves into tabs at the URL it ended on, not
                // the one it started at — you may have clicked through.
                guard let url = tab.webView.url else { return }
                owner.newTab(url: url)
                self?.window?.makeKeyAndOrderFront(nil)
            },
            onClose: { [weak self] window in self?.detached.removeAll { $0 === window } }))
    }

    /// A window that leaves nothing behind: its own ephemeral data store, no
    /// history, no saved tabs, no undo stack. Closing it ends that session for
    /// good.
    private func newPrivateWindow() {
        let privateModel = BrowserModel(settings: settings, history: history, shortcuts: shortcuts,
                                        ai: ai, finder: finder, downloads: downloads,
                                        sites: sites, blocker: blocker, appearance: appearance,
                                        isPrivate: true)
        let window = makeBrowserWindow(for: privateModel)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        applyWindowChrome()
        privateModel.newTab()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              let index = browsers.firstIndex(where: { $0.window === closing }) else { return }
        let model = browsers.remove(at: index).model
        guard model.isPrivate else { return }
        // Nothing from a private session outlives its window.
        model.retireEverything()
    }

    // MARK: System-wide capture

    /// Services menu: "Save to Rune Finder" — takes files, URLs, images, or
    /// selected text from any app.
    @objc func saveToRuneFinder(_ pboard: NSPasteboard, userData: String,
                                error: AutoreleasingUnsafeMutablePointer<NSString>) {
        ingest(pasteboard: pboard)
    }

    /// Same handler, second registration: Finder's context menu matches file
    /// services on a pure NSSendFileTypes declaration, while text/image/URL
    /// selections match NSSendTypes — so the service is declared twice under
    /// one menu title (only one fits any given context).
    @objc func saveToRuneFinderData(_ pboard: NSPasteboard, userData: String,
                                    error: AutoreleasingUnsafeMutablePointer<NSString>) {
        ingest(pasteboard: pboard)
    }

    /// Dock drops and "Open With Rune": web URLs open as tabs, files land in
    /// the Finder library.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                Task { @MainActor in
                    if (try? await finder.importFile(url)) != nil { savedFeedback() }
                }
            } else if settings.externalLinks == .segment {
                // A link from another app is a visit, not a commitment.
                detach(url, floating: false)
            } else {
                model.newTab(url: url)
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func ingest(pasteboard pboard: NSPasteboard) {
        // Snapshot pasteboard content NOW — service pasteboards don't outlive the call.
        var fileURLs = (pboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if fileURLs.isEmpty, let paths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            fileURLs = paths.map { URL(fileURLWithPath: $0) }
        }
        let imageData = pboard.data(forType: .png) ?? pboard.data(forType: .tiff)
        let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            var saved = 0
            // 1. Files (Finder selections, image drags from apps)
            if !fileURLs.isEmpty {
                for url in fileURLs {
                    do { _ = try await finder.importFile(url); saved += 1 }
                    catch { NSLog("Rune service: import failed for %@ — %@", url.path, "\(error)") }
                }
            }
            // 2. Raw image data (copied images)
            else if let data = imageData {
                let png = NSImage(data: data)?.png ?? data
                if (try? await finder.save(data: png, ext: "png", fileName: "Image",
                                           sourceURL: "", sourceTitle: "")) != nil { saved += 1 }
            }
            // 3. Text: URLs download, anything else is kept as a snippet
            else if let text, !text.isEmpty {
                if let url = URL(string: text), let scheme = url.scheme, scheme.hasPrefix("http") {
                    if (try? await finder.save(assetURL: url, sourceURL: text, sourceTitle: "")) != nil { saved += 1 }
                } else if (try? await finder.saveText(text)) != nil { saved += 1 }
            }
            if saved > 0 { savedFeedback(count: saved) }
        }
    }

    /// Feedback that works even when Rune is in the background: in-app toast
    /// plus a gentle dock bounce.
    private func savedFeedback(count: Int = 1) {
        NotificationCenter.default.post(name: .finderToast,
                                        object: count == 1 ? "Saved to Finder" : "Saved \(count) items to Finder")
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    // Auto-PiP on leaving the app (the "window blur" case). App-level rather
    // than window-level so opening Settings or the palette doesn't trigger it.
    func applicationDidResignActive(_ notification: Notification) {
        if settings.autoPiP == .tabSwitchAndAppSwitch {
            model.activeTab?.requestPiPIfPlaying(audibleOnly: settings.autoPiPAudibleOnly)
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if settings.autoPiP == .tabSwitchAndAppSwitch, settings.autoPiPReturnInline {
            model.activeTab?.exitPiPIfActive()
        }
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private var appliedIconChoice: String?

    @objc private func frontBrowserWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func applyWindowChrome() {
        for browser in browsers {
            TitlebarRemover.strip(browser.window)
        }
        // App icon (nil = the bundle's own icon, which the system adapts).
        // Only redo it when the choice changed, not on every appearance tweak.
        let choice = appearance.appearance.appIconName
        if appliedIconChoice != choice {
            appliedIconChoice = choice
            NSApp.applicationIconImage = appearance.appIcon()
        }
    }

    // MARK: Menu (from the command registry + current shortcut overrides)

    @objc private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Rune",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        addCommandItem(.openSettings, to: appMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Rune", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        for section in Command.MenuSection.allCases where section != .app {
            let sectionItem = NSMenuItem()
            let sectionMenu = NSMenu(title: section.rawValue)
            for command in Command.allCases where command.menu == section {
                addCommandItem(command, to: sectionMenu)
            }
            sectionItem.submenu = sectionMenu
            sectionItem.title = section.rawValue
            mainMenu.addItem(sectionItem)
        }

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        editItem.title = "Edit"
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func addCommandItem(_ command: Command, to menu: NSMenu) {
        let shortcut = shortcuts.shortcut(for: command)
        let item = NSMenuItem(title: command.title, action: #selector(runCommand(_:)), keyEquivalent: shortcut.key)
        item.keyEquivalentModifierMask = shortcut.flags
        item.representedObject = command.rawValue
        item.target = self
        menu.addItem(item)
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = Command(rawValue: raw) else { return }
        dispatch(command)
    }

    func dispatch(_ command: Command) {
        // Commands that act on the browser should be seen acting: invoked from
        // the Finder window, ⌘K/⌘T/⌘L would otherwise work invisibly behind it.
        let worksAnywhere: Set<Command> = [.openFinder, .openSettings, .closeTab, .newPrivateWindow,
                                          .showDownloads]
        if finderWindow.isKey, !worksAnywhere.contains(command) {
            window?.makeKeyAndOrderFront(nil)
        }
        let model = frontModel
        // Overlays live inside a BrowserView, so they're asked for by
        // broadcast; naming the model keeps a second window out of it.
        func show(_ name: Notification.Name) {
            NotificationCenter.default.post(name: name, object: model)
        }
        switch command {
        case .commandPalette: show(.showCommandPalette)
        case .askPage: show(.showAskBar)
        case .newTab:
            if settings.newTabBehavior == .addressOverlay { show(.showNewTabOverlay) }
            else { model.newTab() }
        case .closeTab:
            // ⌘W closes the window you're looking at, not a hidden tab.
            if finderWindow.isKey { finderWindow.close() } else { model.closeActive() }
        case .reload: model.reload()
        case .goBack: model.goBack()
        case .goForward: model.goForward()
        case .focusAddress: show(.focusAddressBar)
        case .toggleSidebar: model.sidebarVisible.toggle()
        case .togglePiP: model.activeTab?.togglePiP()
        case .findInPage: show(.showFindBar)
        case .undoCloseTab: model.undoCloseTab()
        case .copyURL: model.copyURL()
        case .zoomIn: model.zoom(.larger)
        case .zoomOut: model.zoom(.smaller)
        case .zoomReset: model.zoom(.reset)
        case .printPage: model.printPage()
        case .showDownloads: finderWindow.showDownloads()
        case .toggleBlocking: model.toggleBlockingForActiveSite()
        case .toggleSplit: model.toggleSplit()
        case .togglePanel: model.togglePanel()
        case .toggleReader:
            Task {
                guard let tab = model.activeTab, await !tab.toggleReader() else { return }
                NotificationCenter.default.post(name: .finderToast, object: "No article on this page")
            }
        case .saveSession: model.saveSession()
        case .newSpace: model.switchTo(space: model.addSpace().id)
        case .nextSpace: model.selectAdjacentSpace(1)
        case .previousSpace: model.selectAdjacentSpace(-1)
        case .muteTab: model.activeTab?.toggleMute()
        case .newPrivateWindow: newPrivateWindow()
        case .openFinder: finderWindow.toggle()
        case .saveMediaUnderCursor: model.saveMediaUnderCursor()
        case .collectFromPage: model.collectFromPage()
        case .capturePage: model.capturePage()
        case .pinTab: if let t = model.activeTab { model.pin(t) }
        case .nextTab: model.selectAdjacentSession(1)
        case .previousTab: model.selectAdjacentSession(-1)
        case .editControls: show(.toggleControlEdit)
        case .openSettings: settingsWindow.show()
        }
    }
}

/// The titled window's dirty secret: an invisible 28pt strip across the top
/// that draws nothing and owns every click. This removes it — the container
/// view is hidden outright, the traffic lights are re-parented into the
/// content view so they survive it, and dragging moves to the window
/// background. Idempotent; safe to call again when the lights setting flips.
@MainActor
enum TitlebarRemover {
    static func strip(_ window: NSWindow, showLights: Bool = false) {
        // The whole container goes — including the system traffic lights.
        // Re-parenting them was a losing fight (AppKit re-lays out its managed
        // buttons whenever it likes, which is how they ended up at the bottom
        // of the sidebar). Rune draws its own lights instead (TrafficLights).
        window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
        // Deliberately NOT movable-by-background: that setting turns every
        // passive surface into a window drag — which is how the split handle
        // stopped splitting. Dragging is granted surface-by-surface instead
        // (WindowDragArea behind the strip, the sidebar, the pane bars).
        window.isMovableByWindowBackground = false
        // Native transparency: the window itself is clear glass; what you see
        // through it is the behind-window blur, dimmed by the container fills.
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
