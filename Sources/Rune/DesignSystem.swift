import AppKit
import SwiftUI

// MARK: - Space

/// The spacing scale. Ad-hoc point values had spread through every view — the
/// same 8 written ninety times, so nothing could be adjusted without finding
/// all ninety. These are the steps actually in use, named, and multiplied by
/// the density setting: at 1.0 they are exactly the numbers that were there
/// before, so adopting a token changes nothing on screen.
extension AppearanceStore {
    enum Space {
        case hair       // 2  — inside a chip, between stacked labels
        case tight      // 4
        case snug       // 6
        case base       // 8  — the default gap between siblings
        case gap        // 10
        case roomy      // 12 — inside a card or popover
        case wide       // 16
        case section    // 24 — between groups that aren't related
    }

    func space(_ step: Space) -> CGFloat {
        let unit: CGFloat
        switch step {
        case .hair: unit = 2
        case .tight: unit = 4
        case .snug: unit = 6
        case .base: unit = 8
        case .gap: unit = 10
        case .roomy: unit = 12
        case .wide: unit = 16
        case .section: unit = 24
        }
        // Whole points only: half a point of padding is a blurry edge.
        return (unit * appearance.density).rounded()
    }

    /// The tap target every icon button in the chrome shares.
    var controlSize: CGSize {
        CGSize(width: (26 * appearance.density).rounded(),
               height: (24 * appearance.density).rounded())
    }

    /// Glyph sizes. Symbols aren't text — they don't belong on the type ramp,
    /// which is tied to the reading-size setting — but they should still scale
    /// with density rather than being written out as a number each time.
    enum Glyph {
        case small      // 10 — badges, chevrons, the ✕ on a row
        case medium     // 11
        case chrome     // 13 — the toolbar and sidebar standard
        case large      // 14
    }

    func glyph(_ size: Glyph, weight: Font.Weight = .medium) -> Font {
        let base: CGFloat
        switch size {
        case .small: base = 10
        case .medium: base = 11
        case .chrome: base = 13
        case .large: base = 14
        }
        return .system(size: (base * appearance.density).rounded(), weight: weight)
    }
}

// MARK: - Components

/// An icon button in the chrome: one glyph, one shared tap target, no
/// decoration. Written out by hand in seven places before this existed, each
/// with its own idea of the size.
struct IconButton: View {
    let symbol: String
    var help: String? = nil
    var size: AppearanceStore.Glyph = .chrome
    var weight: Font.Weight = .medium
    let action: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(appearance.glyph(size, weight: weight))
                .frame(width: appearance.controlSize.width, height: appearance.controlSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(OptionalHelp(help))
    }
}

/// `.help()` takes a non-optional, and a button without a tooltip shouldn't
/// have to pretend it has one.
private struct OptionalHelp: ViewModifier {
    let text: String?
    init(_ text: String?) { self.text = text }
    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

/// The micro-label that names a group of things: small caps, tracked out,
/// quiet, with an optional count sitting at the trailing edge. The hierarchy is
/// the whitespace around it, not its weight.
struct SectionLabel: View {
    let title: String
    var trailing: String? = nil
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack {
            Text(title.uppercased()).font(appearance.type(.caption)).tracking(1.3)
            if let trailing {
                Spacer()
                Text(trailing).font(appearance.type(.caption)).monospacedDigit()
            }
        }
        .foregroundStyle(appearance.sidebarSecondary.opacity(0.85))
        .padding(.horizontal, appearance.space(.base))
    }
}
