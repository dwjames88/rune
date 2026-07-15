import AppKit
import SwiftUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let history = HistoryStore()
    let shortcuts = ShortcutStore()
    let appearance = AppearanceStore()
    let claude = ClaudeService()
    let finder = FinderStore()
    lazy var model = BrowserModel(settings: settings, history: history, shortcuts: shortcuts,
                                  claude: claude, finder: finder)
    lazy var settingsWindow = SettingsWindowController(
        settings: settings, shortcuts: shortcuts, history: history, appearance: appearance, claude: claude)
    lazy var finderWindow = FinderWindowController(model: model, appearance: appearance)
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Rune"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let hosting = NSHostingController(
            rootView: BrowserView(model: model, dispatch: { [weak self] in self?.dispatch($0) })
                .environmentObject(appearance))
        hosting.sizingOptions = []   // never let SwiftUI shrink the window to its ideal size
        window.contentViewController = hosting
        window.minSize = NSSize(width: 900, height: 600)
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
        model.newTab()

        if ProcessInfo.processInfo.environment["RUNE_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.settingsWindow.show() }
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(buildMenu), name: .shortcutsChanged, object: nil)
        center.addObserver(self, selector: #selector(applyWindowChrome), name: .appearanceChanged, object: nil)
        center.addObserver(self, selector: #selector(frontBrowserWindow), name: .frontBrowserWindow, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.persist()
        history.flush()
        appearance.flush()
    }

    // Auto-PiP on leaving the app (the "window blur" case). App-level rather
    // than window-level so opening Settings or the palette doesn't trigger it.
    func applicationDidResignActive(_ notification: Notification) {
        if settings.autoPiP == .tabSwitchAndAppSwitch { model.activeTab?.requestPiPIfPlaying() }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if settings.autoPiP == .tabSwitchAndAppSwitch, settings.autoPiPReturnInline {
            model.activeTab?.exitPiPIfActive()
        }
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private var appliedIconTokens: (String, String)?

    @objc private func frontBrowserWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func applyWindowChrome() {
        let hidden = appearance.appearance.hideTrafficLights
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
        // Custom app icon (nil = back to the bundle's Icon Composer icon).
        // Rendering is 1024px — only redo it when the icon tokens changed, not
        // on every appearance tweak.
        let tokens = (appearance.appearance.appIconBackground, appearance.appearance.appIconGlyph)
        if appliedIconTokens == nil || appliedIconTokens! != tokens {
            appliedIconTokens = tokens
            NSApp.applicationIconImage = AppIconRenderer.custom(for: appearance.appearance)
        }
    }

    // MARK: Menu (from the command registry + current shortcut overrides)

    @objc private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Rune", action: nil, keyEquivalent: "")
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
        switch command {
        case .commandPalette: NotificationCenter.default.post(name: .showCommandPalette, object: nil)
        case .askPage: NotificationCenter.default.post(name: .showAskBar, object: nil)
        case .newTab: model.newTab()
        case .closeTab:
            // ⌘W closes the window you're looking at, not a hidden tab.
            if finderWindow.isKey { finderWindow.close() } else { model.closeActive() }
        case .reload: model.reload()
        case .goBack: model.goBack()
        case .goForward: model.goForward()
        case .focusAddress: NotificationCenter.default.post(name: .focusAddressBar, object: nil)
        case .toggleSidebar: model.sidebarVisible.toggle()
        case .togglePiP: model.activeTab?.togglePiP()
        case .openFinder: finderWindow.toggle()
        case .saveMediaUnderCursor: model.saveMediaUnderCursor()
        case .collectFromPage: model.collectFromPage()
        case .capturePage: model.capturePage()
        case .pinTab: if let t = model.activeTab { model.pin(t) }
        case .nextTab: model.selectAdjacentSession(1)
        case .previousTab: model.selectAdjacentSession(-1)
        case .openSettings: settingsWindow.show()
        }
    }
}
