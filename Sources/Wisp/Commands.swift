import AppKit

/// Every user-invokable command lives here exactly once. The menu bar, the
/// (future) command palette, and the (future) shortcut-remapping settings all
/// read from this one list — so "a keyboard shortcut for anything" and "a
/// setting for everything" are structural, not special-cased per feature.
enum Command: String, CaseIterable, Identifiable {
    case newTab
    case closeTab
    case reload
    case goBack
    case goForward
    case focusAddress
    case toggleSidebar
    case pinTab
    case nextTab
    case previousTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .reload: "Reload Page"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .focusAddress: "Open Location…"
        case .toggleSidebar: "Toggle Sidebar"
        case .pinTab: "Pin / Unpin Tab"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        }
    }

    /// Which menu section it belongs under.
    var menu: MenuSection {
        switch self {
        case .newTab, .closeTab, .pinTab: .file
        case .reload, .toggleSidebar: .view
        case .goBack, .goForward: .history
        case .focusAddress, .nextTab, .previousTab: .navigate
        }
    }

    /// Default shortcut: (key equivalent, modifiers). Empty key = no default.
    var defaultShortcut: (key: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .newTab: ("t", .command)
        case .closeTab: ("w", .command)
        case .reload: ("r", .command)
        case .goBack: ("[", .command)
        case .goForward: ("]", .command)
        case .focusAddress: ("l", .command)
        case .toggleSidebar: ("s", [.command, .option])
        case .pinTab: ("d", .command)
        case .nextTab: ("]", [.command, .shift])
        case .previousTab: ("[", [.command, .shift])
        }
    }

    enum MenuSection: String, CaseIterable {
        case file = "File"
        case view = "View"
        case history = "History"
        case navigate = "Navigate"
    }
}
