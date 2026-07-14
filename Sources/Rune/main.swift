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
    lazy var model = BrowserModel(settings: settings, history: history, shortcuts: shortcuts)
    lazy var settingsWindow = SettingsWindowController(
        settings: settings, shortcuts: shortcuts, history: history, appearance: appearance)
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
        window.center()
        window.setFrameAutosaveName("RuneMainWindow")
        window.contentViewController = NSHostingController(
            rootView: BrowserView(model: model, dispatch: { [weak self] in self?.dispatch($0) })
                .environmentObject(appearance))
        window.minSize = NSSize(width: 720, height: 480)
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
    }

    func applicationWillTerminate(_ notification: Notification) { model.persist() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func applyWindowChrome() {
        let hidden = appearance.appearance.hideTrafficLights
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
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
        case .newTab: model.newTab()
        case .closeTab: model.closeActive()
        case .reload: model.reload()
        case .goBack: model.goBack()
        case .goForward: model.goForward()
        case .focusAddress: NotificationCenter.default.post(name: .focusAddressBar, object: nil)
        case .toggleSidebar: model.sidebarVisible.toggle()
        case .pinTab: if let t = model.activeTab { model.pin(t) }
        case .nextTab: model.selectAdjacentSession(1)
        case .previousTab: model.selectAdjacentSession(-1)
        case .openSettings: settingsWindow.show()
        }
    }
}
