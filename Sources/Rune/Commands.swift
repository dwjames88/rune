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
        case .openSettings: "gearshape"
        }
    }

    /// Which menu section it belongs under.
    var menu: MenuSection {
        switch self {
        case .newTab, .closeTab, .pinTab: .file
        case .reload, .toggleSidebar, .togglePiP, .commandPalette, .askPage: .view
        case .goBack, .goForward: .history
        case .focusAddress, .nextTab, .previousTab: .navigate
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
        case .openSettings: (",", .command)
        }
    }

    enum MenuSection: String, CaseIterable {
        case app = "Rune"
        case file = "File"
        case view = "View"
        case history = "History"
        case navigate = "Navigate"
    }
}
