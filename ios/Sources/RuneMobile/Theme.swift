import SwiftUI
import UIKit

/// Rune's visual voice, carried to the phone: the same accent, the same
/// radius, ink that picks its own contrast. Hex values mirror the macOS
/// `Appearance` defaults — when sync arrives, the Mac's saved appearance
/// will ride the same wire as the folders and tabs.
enum RuneTheme {
    /// The macOS default accent (#4ACB9E).
    static let accent = Color(hex: "#4ACB9E") ?? .green
    /// The macOS default corner radius.
    static let radius: CGFloat = 8
    /// Pills are just the radius grown to the control's height.
    static let pillRadius: CGFloat = 22
    static let fontSize: CGFloat = 15

    /// Black-or-white ink for a surface — the WCAG auto-contrast rule the Mac
    /// app applies everywhere, reduced to its luminance test.
    static func ink(on color: UIColor) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return luminance > 0.5 ? .black : .white
    }
}

extension View {
    /// Native Liquid Glass (iOS 26+) with an optional tint poured through it —
    /// the Mac app's "tint the glass with the accent" idea, applied to the
    /// page's own colour. Older iOS gets the frosted-material fallback, same
    /// contract as the Mac's pre-26 path.
    @ViewBuilder
    func runeGlass(tint: Color? = nil, in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.55)).interactive() }
                             ?? Glass.regular.interactive(),
                             in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(tint?.opacity(0.35) ?? .clear, in: shape)
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color, nil for anything else. Same contract as the Mac app.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
