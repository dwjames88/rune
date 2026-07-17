import AppKit

/// Every user-invokable command lives here exactly once. The menu bar, the
/// (future) command palette, and the (future) shortcut-remapping settings all
/// read from this one list — so "a keyboard shortcut for anything" and "a
/// setting for everything" are structural, not special-cased per feature.
enum Command: String, CaseIterable, Identifiable {
    case commandPalette
    case askPage
    case newTab
    case closeTab
    case reload
    case goBack
    case goForward
    case focusAddress
    case toggleSidebar
    case togglePiP
    case pinTab
    case nextTab
    case previousTab
    case findInPage
    case undoCloseTab
    case copyURL
    case zoomIn
    case zoomOut
    case zoomReset
    case printPage
    case showDownloads
    case toggleBlocking
    case toggleSplit
    case togglePanel
    case toggleReader
    case saveSession
    case newSpace
    case nextSpace
    case previousSpace
    case muteTab
    case newPrivateWindow
    case openFinder
    case saveMediaUnderCursor
    case collectFromPage
    case capturePage
    case openSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandPalette: "Command Palette…"
        case .askPage: "Ask About This Page…"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .reload: "Reload Page"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .focusAddress: "Open Location…"
        case .toggleSidebar: "Toggle Sidebar"
        case .togglePiP: "Toggle Picture in Picture"
        case .pinTab: "Pin / Unpin Tab"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .findInPage: "Find in Page…"
        case .undoCloseTab: "Undo Close Tab"
        case .copyURL: "Copy Page URL"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .zoomReset: "Actual Size"
        case .printPage: "Print…"
        case .showDownloads: "Downloads"
        case .toggleBlocking: "Block Content on This Site"
        case .toggleSplit: "Split View"
        case .togglePanel: "Show / Hide Panel"
        case .toggleReader: "Reader"
        case .saveSession: "Save Tabs as Session"
        case .newSpace: "New Space"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .muteTab: "Mute / Unmute Tab"
        case .newPrivateWindow: "New Private Window"
        case .openFinder: "Open Finder"
        case .saveMediaUnderCursor: "Save Image Under Cursor"
        case .collectFromPage: "Collect Images from Page…"
        case .capturePage: "Capture Page to Finder"
        case .openSettings: "Settings…"
        }
    }

    /// SF Symbol shown in the command palette.
    var icon: String {
        switch self {
        case .commandPalette: "command"
        case .askPage: "sparkles"
        case .newTab: "plus.square"
        case .closeTab: "xmark.square"
        case .reload: "arrow.clockwise"
        case .goBack: "chevron.left"
        case .goForward: "chevron.right"
        case .focusAddress: "magnifyingglass"
        case .toggleSidebar: "sidebar.left"
        case .togglePiP: "pip"
        case .pinTab: "pin"
        case .nextTab: "arrow.right.to.line"
        case .previousTab: "arrow.left.to.line"
        case .findInPage: "text.magnifyingglass"
        case .undoCloseTab: "arrow.uturn.backward.square"
        case .copyURL: "link"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .zoomReset: "1.magnifyingglass"
        case .printPage: "printer"
        case .showDownloads: "arrow.down.circle"
        case .toggleBlocking: "shield"
        case .toggleSplit: "rectangle.split.2x1"
        case .togglePanel: "sidebar.squares.right"
        case .toggleReader: "doc.plaintext"
        case .saveSession: "tray.and.arrow.down"
        case .newSpace: "square.stack.badge.plus"
        case .nextSpace: "square.stack"
        case .previousSpace: "square.stack"
        case .muteTab: "speaker.slash"
        case .newPrivateWindow: "eyeglasses.slash"
        case .openFinder: "sparkles.rectangle.stack"
        case .saveMediaUnderCursor: "photo.badge.arrow.down"
        case .collectFromPage: "square.grid.3x3.square"
        case .capturePage: "camera.viewfinder"
        case .openSettings: "gearshape"
        }
    }

    /// Which menu section it belongs under.
    var menu: MenuSection {
        switch self {
        case .newTab, .closeTab, .undoCloseTab, .newPrivateWindow, .copyURL, .printPage, .pinTab: .file
        case .reload, .findInPage, .zoomIn, .zoomOut, .zoomReset, .muteTab, .showDownloads, .toggleBlocking, .toggleSplit, .togglePanel, .toggleReader,
             .toggleSidebar, .togglePiP, .commandPalette, .askPage: .view
        case .goBack, .goForward: .history
        case .focusAddress, .nextTab, .previousTab, .newSpace, .nextSpace, .previousSpace, .saveSession: .navigate
        case .openFinder, .saveMediaUnderCursor, .collectFromPage, .capturePage: .finder
        case .openSettings: .app
        }
    }

    /// Default shortcut: (key equivalent, modifiers). Empty key = no default.
    var defaultShortcut: (key: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .commandPalette: ("k", .command)
        case .askPage: ("j", .command)
        case .newTab: ("t", .command)
        case .closeTab: ("w", .command)
        case .reload: ("r", .command)
        case .goBack: ("[", .command)
        case .goForward: ("]", .command)
        case .focusAddress: ("l", .command)
        case .toggleSidebar: ("s", [.command, .option])
        case .togglePiP: ("p", [.command, .option])
        case .pinTab: ("d", .command)
        case .nextTab: ("]", [.command, .shift])
        case .previousTab: ("[", [.command, .shift])
        case .findInPage: ("f", .command)
        case .undoCloseTab: ("t", [.command, .shift])
        case .copyURL: ("c", [.command, .shift])
        case .zoomIn: ("=", .command)
        case .zoomOut: ("-", .command)
        case .zoomReset: ("0", .command)
        case .printPage: ("p", .command)
        case .showDownloads: ("l", [.command, .option])
        case .toggleBlocking: ("", [])
        case .toggleSplit: ("\\", [.command, .option])
        case .togglePanel: ("e", [.command, .option])
        case .toggleReader: ("r", [.command, .shift])
        case .saveSession: ("", [])
        case .newSpace: ("", [])
        case .nextSpace: ("]", [.command, .control])
        case .previousSpace: ("[", [.command, .control])
        case .muteTab: ("m", [.command, .control])
        case .newPrivateWindow: ("n", [.command, .shift])
        case .openFinder: ("f", [.command, .option])
        case .saveMediaUnderCursor: ("s", .option)
        case .collectFromPage: ("s", [.command, .shift])
        case .capturePage: ("", [])
        case .openSettings: (",", .command)
        }
    }

    enum MenuSection: String, CaseIterable {
        case app = "Rune"
        case file = "File"
        case view = "View"
        case history = "History"
        case navigate = "Go"
        case finder = "Finder"
    }
}
