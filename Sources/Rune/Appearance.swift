import AppKit
import SwiftUI

/// Every visual knob in one Codable value — so it can be edited in the UI,
/// persisted, and exported/imported as a shareable preset. "system" means
/// "follow the OS color" for that slot.
struct Appearance: Codable, Equatable {
    // Colors
    var accent = "#4ACB9E"
    var sidebarColor = "system"
    var chromeColor = "system"
    var backgroundColor = "system"

    // Typography
    var fontName = "system"        // "system" or a font family name
    var fontSize: Double = 13
    /// "auto" = pick black/white for best contrast against the background
    /// (WCAG), otherwise a hex the user chose.
    var textColor = "auto"

    // Layout
    var sidebarWidth: Double = 240
    var cornerRadius: Double = 8
    var sidebarOnRight = false

    // Toolbar
    /// Command rawValues shown as toolbar buttons, in order, before the
    /// address bar. Any command works — the button dispatches it. This is the
    /// master "enabled" list; `stripButtons` says which of them live in the
    /// minimal strip rather than the corner kit.
    var toolbarButtons: [String] = ["toggleSidebar", "goBack", "goForward", "reload", "showDownloads"]
    /// The strip carries two button clusters, one on each side of the address
    /// field; these are the command rawValues in each, in order. Everything
    /// else enabled (bar the sidebar toggle, which has a fixed home) waits in
    /// the corner kit. Wiggle mode drags between all three shelves.
    var stripLeadingButtons: [String] = ["goBack", "goForward", "reload"]
    var stripTrailingButtons: [String] = []
    /// Show just the site's host in the address bar until you click it.
    var compactAddressBar = true
    /// Where the address text sits in the strip's field: "left", "center",
    /// or "right".
    var addressAlignment = "center"
    /// "floating" — the minimal strip: back/forward and a quiet address pill
    /// on a thin band above the page, nothing else. "attached" — the classic
    /// toolbar with the full button set.
    var chromeStyle = "floating"
    /// Which side of the address bar the back/forward buttons sit on.
    var navPlacement = "left"

    // Start page
    var startPageGreeting = ""          // empty = the "Rune" wordmark
    var startPageShowFavorites = true
    var startPageShowRecents = false
    var startPageBackground = "system"  // color token; "system" follows the window background

    // Window
    var hideTrafficLights = false
    /// Container-fill opacity over the glass, percent (70–100).
    var windowOpacity: Double = 100
    /// How frosted the glass is, percent (0 = sharp see-through).
    var blur: Double = 100
    /// Film grain over the chrome, percent (0 = none).
    var grain: Double = 8

    // Glass — the floating surfaces (palette, panels, popovers, the corner
    // kit, the suggestion drop). On by default where the OS has real Liquid
    // Glass; off falls back to frosted material everywhere.
    var liquidGlass = true
    /// Pour the accent through the glass instead of leaving it clear.
    var glassTinted = false
    /// Glass that lifts and refracts under the pointer (native interactive).
    var glassInteractive = true

    // App icon: "default" = the bundled Icon Composer icon; a hex on either
    // token switches to a natively-rendered variant (see AppIconRenderer).
    var appIconBackground = "default"
    var appIconGlyph = "default"

    static let `default` = Appearance()

    // Decode with a default for every missing key, so adding a knob never
    // resets anyone's saved appearance.json / presets / .runetheme files.
    enum CodingKeys: String, CodingKey {
        case accent, sidebarColor, chromeColor, backgroundColor
        case fontName, fontSize, textColor
        case sidebarWidth, cornerRadius, sidebarOnRight
        case toolbarButtons, stripLeadingButtons, stripTrailingButtons
        case compactAddressBar, addressAlignment, chromeStyle, navPlacement
        case startPageGreeting, startPageShowFavorites, startPageShowRecents, startPageBackground
        case hideTrafficLights, windowOpacity, blur, grain
        case liquidGlass, glassTinted, glassInteractive
        case appIconBackground, appIconGlyph
    }

    /// Retired keys, decoded only to carry an older appearance.json forward.
    private enum LegacyKeys: String, CodingKey { case stripButtons }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance.default
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
        sidebarColor = try c.decodeIfPresent(String.self, forKey: .sidebarColor) ?? d.sidebarColor
        chromeColor = try c.decodeIfPresent(String.self, forKey: .chromeColor) ?? d.chromeColor
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor) ?? d.backgroundColor
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor) ?? d.textColor
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? d.sidebarWidth
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        sidebarOnRight = try c.decodeIfPresent(Bool.self, forKey: .sidebarOnRight) ?? d.sidebarOnRight
        toolbarButtons = try c.decodeIfPresent([String].self, forKey: .toolbarButtons) ?? d.toolbarButtons
        compactAddressBar = try c.decodeIfPresent(Bool.self, forKey: .compactAddressBar) ?? d.compactAddressBar
        addressAlignment = try c.decodeIfPresent(String.self, forKey: .addressAlignment) ?? d.addressAlignment
        chromeStyle = try c.decodeIfPresent(String.self, forKey: .chromeStyle) ?? d.chromeStyle
        navPlacement = try c.decodeIfPresent(String.self, forKey: .navPlacement) ?? d.navPlacement
        // Migration: a single `stripButtons` from before the two-cluster split
        // (a retired key, decoded from a side container) lands on whichever
        // side its old nav placement chose.
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        if let leading = try c.decodeIfPresent([String].self, forKey: .stripLeadingButtons) {
            stripLeadingButtons = leading
            stripTrailingButtons = try c.decodeIfPresent([String].self, forKey: .stripTrailingButtons) ?? d.stripTrailingButtons
        } else if let old = try legacy?.decodeIfPresent([String].self, forKey: .stripButtons) {
            if navPlacement == "right" { stripTrailingButtons = old; stripLeadingButtons = [] }
            else { stripLeadingButtons = old; stripTrailingButtons = [] }
        } else {
            stripLeadingButtons = d.stripLeadingButtons
            stripTrailingButtons = d.stripTrailingButtons
        }
        startPageGreeting = try c.decodeIfPresent(String.self, forKey: .startPageGreeting) ?? d.startPageGreeting
        startPageShowFavorites = try c.decodeIfPresent(Bool.self, forKey: .startPageShowFavorites) ?? d.startPageShowFavorites
        startPageShowRecents = try c.decodeIfPresent(Bool.self, forKey: .startPageShowRecents) ?? d.startPageShowRecents
        startPageBackground = try c.decodeIfPresent(String.self, forKey: .startPageBackground) ?? d.startPageBackground
        hideTrafficLights = try c.decodeIfPresent(Bool.self, forKey: .hideTrafficLights) ?? d.hideTrafficLights
        windowOpacity = try c.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? d.windowOpacity
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? d.grain
        liquidGlass = try c.decodeIfPresent(Bool.self, forKey: .liquidGlass) ?? d.liquidGlass
        glassTinted = try c.decodeIfPresent(Bool.self, forKey: .glassTinted) ?? d.glassTinted
        glassInteractive = try c.decodeIfPresent(Bool.self, forKey: .glassInteractive) ?? d.glassInteractive
        appIconBackground = try c.decodeIfPresent(String.self, forKey: .appIconBackground) ?? d.appIconBackground
        appIconGlyph = try c.decodeIfPresent(String.self, forKey: .appIconGlyph) ?? d.appIconGlyph
    }
}

struct ThemePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var appearance: Appearance
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var appearance: Appearance { didSet { persist() } }
    @Published var presets: [ThemePreset]

    init() {
        appearance = Storage.loadJSON(Appearance.self, from: "appearance.json") ?? .default
        presets = Storage.loadJSON([ThemePreset].self, from: "presets.json") ?? Self.builtIns
    }

    // The notification (window chrome, app icon) fires immediately; the disk
    // write waits, so dragging a slider doesn't write a file per tick.
    private lazy var writer = DebouncedWrite(after: .seconds(1)) { [weak self] in
        guard let self else { return }
        Storage.saveJSON(appearance, to: "appearance.json")
    }
    private func persist() {
        NotificationCenter.default.post(name: .appearanceChanged, object: nil)
        writer.schedule()
    }
    func flush() { writer.flush() }

    // MARK: Presets

    func saveCurrentAsPreset(named name: String) {
        presets.append(ThemePreset(name: name, appearance: appearance))
        Storage.saveJSON(presets, to: "presets.json")
    }
    func apply(_ preset: ThemePreset) { appearance = preset.appearance }
    func delete(_ preset: ThemePreset) {
        presets.removeAll { $0.id == preset.id }
        Storage.saveJSON(presets, to: "presets.json")
    }
    func resetToDefault() { appearance = .default }

    // MARK: Control placement (wiggle mode)

    /// The three shelves a control can live on: two clusters in the strip
    /// (either side of the address) and the corner kit. The sidebar toggle
    /// keeps its own fixed home and is never on any of them.
    enum ControlSlot: CaseIterable { case leading, trailing, corner }

    var stripLeadingCommands: [Command] {
        appearance.stripLeadingButtons.compactMap(Command.init(rawValue:))
    }
    var stripTrailingCommands: [Command] {
        appearance.stripTrailingButtons.compactMap(Command.init(rawValue:))
    }
    /// Everything enabled that isn't on a strip cluster (nor the fixed toggle).
    var cornerCommands: [Command] {
        appearance.toolbarButtons
            .filter { !appearance.stripLeadingButtons.contains($0)
                   && !appearance.stripTrailingButtons.contains($0)
                   && $0 != Command.toggleSidebar.rawValue }
            .compactMap(Command.init(rawValue:))
    }

    /// Which shelf a control currently sits on.
    func slot(of raw: String) -> ControlSlot {
        if appearance.stripLeadingButtons.contains(raw) { return .leading }
        if appearance.stripTrailingButtons.contains(raw) { return .trailing }
        return .corner
    }

    /// Move a control onto a shelf. Corner is "in the toolbar list, on neither
    /// strip cluster", so it's the absence of the other two.
    func move(_ raw: String, to slot: ControlSlot) {
        appearance.stripLeadingButtons.removeAll { $0 == raw }
        appearance.stripTrailingButtons.removeAll { $0 == raw }
        if !appearance.toolbarButtons.contains(raw) { appearance.toolbarButtons.append(raw) }
        switch slot {
        case .leading: appearance.stripLeadingButtons.append(raw)
        case .trailing: appearance.stripTrailingButtons.append(raw)
        case .corner: break
        }
    }

    /// Click-to-move cycles a wiggling button through the shelves, so a drag
    /// isn't the only way (the strip sits in the titlebar region, where drags
    /// are flaky). leading → trailing → corner → leading.
    func cycleSlot(_ raw: String) {
        let next: ControlSlot
        switch slot(of: raw) {
        case .leading: next = .trailing
        case .trailing: next = .corner
        case .corner: next = .leading
        }
        move(raw, to: next)
    }

    func disableControl(_ raw: String) {
        appearance.stripLeadingButtons.removeAll { $0 == raw }
        appearance.stripTrailingButtons.removeAll { $0 == raw }
        appearance.toolbarButtons.removeAll { $0 == raw }
    }

    /// Write the current look to a `.runetheme` file to share.
    func export(to url: URL, name: String) {
        let preset = ThemePreset(name: name, appearance: appearance)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(preset).write(to: url)
    }
    /// Import a shared `.runetheme` file: add it to the library and apply it.
    @discardableResult
    func importPreset(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let preset = try? JSONDecoder().decode(ThemePreset.self, from: data) else { return false }
        presets.append(preset)
        Storage.saveJSON(presets, to: "presets.json")
        apply(preset)
        return true
    }

    static let builtIns: [ThemePreset] = [
        ThemePreset(name: "Rune Mint", appearance: .default),
        ThemePreset(name: "Graphite", appearance: {
            var a = Appearance()
            a.accent = "#8E8E93"; a.sidebarColor = "#1C1C1E"; a.chromeColor = "#2C2C2E"
            a.backgroundColor = "#000000"; a.cornerRadius = 6
            return a
        }()),
        ThemePreset(name: "Paper", appearance: {
            var a = Appearance()
            a.accent = "#C0704B"; a.sidebarColor = "#F2EEE6"; a.chromeColor = "#FBF8F2"
            a.backgroundColor = "#FFFDF8"; a.fontName = "Georgia"; a.cornerRadius = 10
            return a
        }()),
    ]

    // MARK: Derived values used by the UI

    private func color(_ token: String, fallback: Color) -> Color {
        token == "system" ? fallback : (Color(hex: token) ?? fallback)
    }
    var accent: Color { Color(hex: appearance.accent) ?? Color(red: 0.29, green: 0.80, blue: 0.62) }
    var sidebarBG: Color { color(appearance.sidebarColor, fallback: Color(nsColor: .windowBackgroundColor)) }
    var chrome: Color { color(appearance.chromeColor, fallback: Color(nsColor: .textBackgroundColor)) }
    var windowBG: Color { color(appearance.backgroundColor, fallback: Color(nsColor: .windowBackgroundColor)) }
    var startPageBG: Color { color(appearance.startPageBackground, fallback: windowBG) }
    var hairline: Color { Color.primary.opacity(0.08) }
    var selection: Color { accent.opacity(0.16) }
    var hover: Color { Color.primary.opacity(0.05) }
    var cornerRadius: CGFloat { appearance.cornerRadius }
    var sidebarWidth: CGFloat { appearance.sidebarWidth }
    /// How solid the container fills are over the behind-window blur.
    /// Transparency belongs to the backgrounds, never to controls or content.
    var containerOpacity: Double { appearance.windowOpacity / 100 }

    // MARK: Contrast-aware text

    /// Text color to use on a given background: honors a user-chosen color,
    /// otherwise picks black or white for the better WCAG contrast ratio.
    func text(on background: Color) -> Color {
        if appearance.textColor != "auto", let c = Color(hex: appearance.textColor) { return c }
        return background.prefersLightText ? .white : .black
    }
    /// Softer secondary text that still clears contrast on the background.
    func secondaryText(on background: Color) -> Color {
        text(on: background).opacity(0.62)
    }
    var sidebarText: Color { text(on: sidebarBG) }
    var sidebarSecondary: Color { secondaryText(on: sidebarBG) }
    var chromeText: Color { text(on: chrome) }
    var contentText: Color { text(on: windowBG) }
    /// Ink for text sitting on a full-accent fill (selection highlights). The
    /// accent isn't always dark — a light accent needs black text — so this is
    /// contrast-picked, never a hardcoded white.
    var accentText: Color { text(on: accent) }
    var accentSecondaryText: Color { secondaryText(on: accent) }

    var uiFont: Font {
        appearance.fontName == "system"
            ? .system(size: appearance.fontSize)
            : .custom(appearance.fontName, size: appearance.fontSize)
    }
    func font(_ size: Double, weight: Font.Weight = .regular) -> Font {
        appearance.fontName == "system"
            ? .system(size: size, weight: weight)
            : .custom(appearance.fontName, size: size)
    }

    // MARK: Type ramp

    /// The five voices Rune speaks in. Ad-hoc point sizes had crept into every
    /// view; a role is a decision made once. Sizes hang off the one font-size
    /// setting, so turning that knob scales the whole app together.
    enum TypeRole {
        case caption    // counts, hints, URLs in trailing position
        case label      // section headers, chips, secondary rows
        case body       // rows, fields, controls — the setting itself
        case title      // panel and overlay titles
        case display    // the start page greeting
    }

    func type(_ role: TypeRole) -> Font {
        let base = appearance.fontSize
        switch role {
        case .caption: return font(base - 3)
        case .label: return font(base - 2, weight: .medium)
        case .body: return font(base)
        case .title: return font(base + 1, weight: .semibold)
        case .display: return font(base * 3, weight: .semibold)
        }
    }

    // MARK: Radius scale

    /// Three steps hung off the one radius knob, so the setting still means
    /// something and nested corners stay concentric.
    enum RadiusRole { case small, medium, large, pill }
    func radius(_ role: RadiusRole) -> CGFloat {
        switch role {
        case .small: max(3, appearance.cornerRadius - 3)
        case .medium: appearance.cornerRadius
        case .large: appearance.cornerRadius + 4
        case .pill: 999
        }
    }
}

// MARK: - Motion

/// Rune's two gestures: things that arrive, spring; things that update, ease.
/// One vocabulary instead of a scatter of durations.
enum Motion {
    static let arrive = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let update = Animation.easeOut(duration: 0.14)
}

// MARK: - Surface

/// The one floating surface. Palette, panels, bars, toasts — every overlay is
/// this material, this border, this shadow. Seven hand-rolled recipes had
/// grown here; a surface you can name is a surface you can keep consistent.
private struct RuneSurface: ViewModifier {
    let radius: CGFloat
    @EnvironmentObject var appearance: AppearanceStore

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26, *), appearance.appearance.liquidGlass {
            // Real Liquid Glass carries its own shadow, highlight and edge —
            // no hand-rolled hairline or drop shadow over the top.
            content.glassEffect(appearance.glass(interactive: true), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(appearance.hairline))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        }
    }
}

extension View {
    /// Wear the shared overlay surface at the given radius role.
    func runeSurface(_ appearance: AppearanceStore, _ role: AppearanceStore.RadiusRole = .large) -> some View {
        modifier(RuneSurface(radius: appearance.radius(role)))
    }

    /// Wear the overlay surface in an arbitrary shape (the corner kit's docked
    /// tab, the suggestion drop). Same glass-or-material choice as runeSurface.
    func runeSurface(_ appearance: AppearanceStore, in shape: some InsettableShape) -> some View {
        modifier(RuneSurfaceShape(shape: shape))
    }
}

private struct RuneSurfaceShape<S: InsettableShape>: ViewModifier {
    let shape: S
    @EnvironmentObject var appearance: AppearanceStore

    func body(content: Content) -> some View {
        if #available(macOS 26, *), appearance.appearance.liquidGlass {
            content.glassEffect(appearance.glass(interactive: false), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(appearance.hairline))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }
}

@available(macOS 26, *)
extension AppearanceStore {
    /// The app's one glass recipe, so every surface refracts alike: tinted
    /// with the accent when asked, interactive where the shape invites a press.
    func glass(interactive: Bool) -> Glass {
        var g = Glass.regular
        if appearance.glassTinted { g = g.tint(accent.opacity(0.5)) }
        if interactive && appearance.glassInteractive { g = g.interactive() }
        return g
    }
}

extension AppearanceStore {
    /// Installed font family names, for the picker.
    static let availableFonts: [String] =
        ["system"] + NSFontManager.shared.availableFontFamilies.sorted()
}

// MARK: - Color <-> hex

extension Color {
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 8 { s = String(s.suffix(6)) }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
    var hex: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

extension Color {
    /// WCAG relative luminance (0 = black, 1 = white).
    var luminance: Double {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 1 }
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    /// Contrast ratio against another color (WCAG: 1…21).
    func contrast(with other: Color) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// True when white text reads better on this background than black text.
    var prefersLightText: Bool {
        contrast(with: .white) >= contrast(with: .black)
    }
}

extension Notification.Name {
    static let appearanceChanged = Notification.Name("rune.appearanceChanged")
}
