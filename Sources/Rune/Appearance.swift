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
    /// address bar. Any command works — the button dispatches it.
    var toolbarButtons: [String] = ["toggleSidebar", "goBack", "goForward", "reload", "showDownloads"]
    /// Show just the site's host in the address bar until you click it.
    var compactAddressBar = true

    // Start page
    var startPageGreeting = ""          // empty = the "Rune" wordmark
    var startPageShowFavorites = true
    var startPageShowRecents = false
    var startPageBackground = "system"  // color token; "system" follows the window background

    // Window
    var hideTrafficLights = false

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
        case toolbarButtons, compactAddressBar
        case startPageGreeting, startPageShowFavorites, startPageShowRecents, startPageBackground
        case hideTrafficLights
        case appIconBackground, appIconGlyph
    }

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
        startPageGreeting = try c.decodeIfPresent(String.self, forKey: .startPageGreeting) ?? d.startPageGreeting
        startPageShowFavorites = try c.decodeIfPresent(Bool.self, forKey: .startPageShowFavorites) ?? d.startPageShowFavorites
        startPageShowRecents = try c.decodeIfPresent(Bool.self, forKey: .startPageShowRecents) ?? d.startPageShowRecents
        startPageBackground = try c.decodeIfPresent(String.self, forKey: .startPageBackground) ?? d.startPageBackground
        hideTrafficLights = try c.decodeIfPresent(Bool.self, forKey: .hideTrafficLights) ?? d.hideTrafficLights
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
