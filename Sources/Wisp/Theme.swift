import SwiftUI

/// Soft, native design tokens. Light and theme-aware.
enum Theme {
    static let accent = Color(red: 0.29, green: 0.80, blue: 0.62)   // mint

    static var windowBG: Color { Color(nsColor: .windowBackgroundColor) }
    static var sidebarBG: Color { Color(nsColor: .windowBackgroundColor) }
    static var chrome: Color { Color(nsColor: .textBackgroundColor) }
    static var hairline: Color { Color.primary.opacity(0.08) }
    static var selection: Color { Color.primary.opacity(0.09) }
    static var hover: Color { Color.primary.opacity(0.05) }

    static let rowRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 240
}
