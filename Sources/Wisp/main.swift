import AppKit
import SwiftUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BrowserModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Wisp"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.setFrameAutosaveName("WispMainWindow")
        window.contentViewController = NSHostingController(rootView: BrowserView(model: model))
        window.minSize = NSSize(width: 720, height: 480)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        model.newTab()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menu (built from the Command registry)

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Wisp", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // One submenu per command section.
        for section in Command.MenuSection.allCases {
            let sectionItem = NSMenuItem()
            let sectionMenu = NSMenu(title: section.rawValue)
            for command in Command.allCases where command.menu == section {
                let (key, mods) = command.defaultShortcut
                let item = NSMenuItem(title: command.title,
                                      action: #selector(runCommand(_:)),
                                      keyEquivalent: key)
                item.keyEquivalentModifierMask = mods
                item.representedObject = command.rawValue
                item.target = self
                sectionMenu.addItem(item)
            }
            sectionItem.submenu = sectionMenu
            sectionItem.title = section.rawValue
            mainMenu.addItem(sectionItem)
        }

        // Standard Edit menu so Cut/Copy/Paste/Select-All work in fields and pages.
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

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = Command(rawValue: raw) else { return }
        dispatch(command)
    }

    func dispatch(_ command: Command) {
        switch command {
        case .newTab: model.newTab()
        case .closeTab: model.closeSelected()
        case .reload: model.reload()
        case .goBack: model.goBack()
        case .goForward: model.goForward()
        case .focusAddress: NotificationCenter.default.post(name: .focusAddressBar, object: nil)
        case .toggleSidebar: model.sidebarVisible.toggle()
        case .pinTab: model.togglePinSelected()
        case .nextTab: model.selectAdjacent(1)
        case .previousTab: model.selectAdjacent(-1)
        }
    }
}
