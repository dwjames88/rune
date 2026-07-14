import AppKit
import SwiftUI

/// Renders custom app-icon variants natively: the rune glyph (same polygon as
/// Assets/Rune.svg) on a rounded-rect gradient background, in any colors. Used
/// by the App Icon setting — the default icon stays the compiled Icon Composer
/// bundle; a custom one is applied at runtime via NSApp.applicationIconImage.
enum AppIconRenderer {

    /// The rune glyph from Assets/Rune.svg (viewBox 239×448), y-flipped for
    /// AppKit's bottom-left origin.
    private static let glyphSize = NSSize(width: 238.5, height: 448)
    private static var glyphPath: NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: 0))
        p.line(to: NSPoint(x: 0, y: 448))
        p.line(to: NSPoint(x: 238.5, y: 345.5))
        p.line(to: NSPoint(x: 238.5, y: 0))
        p.line(to: NSPoint(x: 187, y: 0))
        p.line(to: NSPoint(x: 187, y: 306))
        p.line(to: NSPoint(x: 56, y: 362))
        p.line(to: NSPoint(x: 56, y: 0))
        p.close()
        return p
    }

    static func image(background: NSColor, glyph: NSColor, size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        // Full-bleed rounded rect, same corner radius the system mask uses.
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)
        let shape = NSBezierPath(roundedRect: canvas, xRadius: size * 0.2266, yRadius: size * 0.2266)

        // Subtle vertical gradient: the color, lifting toward white at the bottom
        // (mirrors the Icon Composer design's bottom-lit look).
        let bottom = background.blended(withFraction: 0.45, of: .white) ?? background
        NSGradient(starting: background, ending: bottom)?.draw(in: shape, angle: -90)

        // Glyph: ~58% of the icon height, centered, soft drop shadow for depth.
        let scale = (size * 0.58) / glyphSize.height
        let path = glyphPath
        var transform = AffineTransform.identity
        transform.translate(x: (size - glyphSize.width * scale) / 2,
                            y: (size - glyphSize.height * scale) / 2)
        transform.scale(scale)
        path.transform(using: transform)

        NSGraphicsContext.current?.saveGraphicsState()
        shape.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.shadowBlurRadius = size * 0.02
        shadow.set()
        glyph.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        return image
    }

    /// The image for an appearance's icon tokens, or nil when both are
    /// "default" (meaning: use the bundle's Icon Composer icon).
    @MainActor
    static func custom(for appearance: Appearance, size: CGFloat = 1024) -> NSImage? {
        guard appearance.appIconBackground != "default" || appearance.appIconGlyph != "default" else {
            return nil
        }
        let bg = Color(hex: appearance.appIconBackground).map(NSColor.init)
            ?? NSColor(red: 0.28, green: 0.83, blue: 0.92, alpha: 1)   // the icon's cyan
        let fg = Color(hex: appearance.appIconGlyph).map(NSColor.init)
            ?? NSColor(red: 0, green: 0.15, blue: 0.47, alpha: 1)      // the glyph's navy
        return image(background: bg, glyph: fg, size: size)
    }
}
