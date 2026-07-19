import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let settings: SettingsStore
    let shortcuts: ShortcutStore
    let history: HistoryStore
    let appearance: AppearanceStore
    let ai: AIService
    let sites: SiteSettings
    /// Resolved lazily: the browser model is built after this controller.
    let model: () -> BrowserModel

    init(settings: SettingsStore, shortcuts: ShortcutStore, history: HistoryStore,
         appearance: AppearanceStore, ai: AIService, sites: SiteSettings,
         model: @escaping () -> BrowserModel) {
        self.settings = settings; self.shortcuts = shortcuts; self.history = history
        self.appearance = appearance; self.ai = ai
        self.sites = sites; self.model = model
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Rune Settings"
            w.titlebarAppearsTransparent = true
            w.center(); w.setFrameAutosaveName("RuneSettings"); w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: RuneSettingsView(
                settings: settings, shortcuts: shortcuts, history: history,
                appearance: appearance, ai: ai, sites: sites, model: model))
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct RuneSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var appearance: AppearanceStore
    @ObservedObject var ai: AIService
    @ObservedObject var sites: SiteSettings
    let model: () -> BrowserModel

    enum Tab: String, CaseIterable, Identifiable {
        case appearance = "Appearance", presets = "Presets", spaces = "Spaces",
             browsing = "Browsing", ai = "AI", shortcuts = "Shortcuts"
        var id: String { rawValue }

        /// The System Settings vocabulary: a white glyph on a tinted chip.
        var icon: String {
            switch self {
            case .appearance: "paintbrush.fill"
            case .presets: "swatchpalette.fill"
            case .spaces: "square.stack.fill"
            case .browsing: "globe"
            case .ai: "sparkles"
            case .shortcuts: "keyboard.fill"
            }
        }
        var chip: Color {
            switch self {
            case .appearance: .blue
            case .presets: .purple
            case .spaces: .indigo
            case .browsing: .green
            case .ai: .pink
            case .shortcuts: .gray
            }
        }
    }
    @State private var tab: Tab = .appearance

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Tab.allCases) { row($0) }
                Spacer(minLength: 0)
            }
            .padding(10)
            .padding(.top, 28)   // under the window's traffic lights
            .frame(width: 185)
            .background(.ultraThinMaterial)

            Divider()

            Group {
                switch tab {
                case .appearance: AppearancePane(appearance: appearance)
                case .presets: PresetsPane(appearance: appearance)
                case .spaces: SpacesPane(model: model(), appearance: appearance)
                case .browsing: BrowsingPane(settings: settings, history: history,
                                             sites: sites, model: model)
                case .ai: AIPane(ai: ai, settings: settings)
                case .shortcuts: ShortcutsPane(shortcuts: shortcuts)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, minHeight: 560)
    }

    private func row(_ t: Tab) -> some View {
        Button { tab = t } label: {
            HStack(spacing: 8) {
                Image(systemName: t.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(t.chip.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(t.rawValue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(tab == t ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: Appearance

private struct AppearancePane: View {
    @ObservedObject var appearance: AppearanceStore
    var a: Binding<Appearance> { $appearance.appearance }

    private var glassAvailable: Bool { if #available(macOS 26, *) { true } else { false } }

    var body: some View {
        Form {
            Section("Colors") {
                ColorTokenRow(label: "Accent", token: a.accent, allowSystem: false)
                ColorTokenRow(label: "Sidebar", token: a.sidebarColor)
                ColorTokenRow(label: "Toolbar", token: a.chromeColor)
                ColorTokenRow(label: "Background", token: a.backgroundColor)
            }
            Section {
                Picker("Font", selection: a.fontName) {
                    ForEach(AppearanceStore.availableFonts, id: \.self) {
                        Text($0 == "system" ? "System" : $0).tag($0)
                    }
                }
                sliderRow("Font size", value: a.fontSize, range: 10...20, step: 1, suffix: "pt")
                HStack {
                    Text("Text color")
                    Spacer()
                    Toggle("Auto contrast", isOn: Binding(
                        get: { appearance.appearance.textColor == "auto" },
                        set: { appearance.appearance.textColor = $0 ? "auto" : "#FFFFFF" }))
                        .toggleStyle(.checkbox)
                    if appearance.appearance.textColor != "auto" {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: appearance.appearance.textColor) ?? .primary },
                            set: { appearance.appearance.textColor = $0.hex ?? "#FFFFFF" }),
                            supportsOpacity: false).labelsHidden()
                    }
                }
            } header: {
                Text("Typography")
            } footer: {
                Text("Auto contrast picks black or white text for the best WCAG contrast against each background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                sliderRow("Corner radius", value: a.cornerRadius, range: 0...16, step: 1, suffix: "px")
                Toggle("Sidebar on the right", isOn: a.sidebarOnRight)
                sliderRow("Transparency", value: a.windowOpacity, range: 70...100, step: 1, suffix: "%")
                sliderRow("Blur", value: a.blur, range: 0...100, step: 5, suffix: "%")
                sliderRow("Grain", value: a.grain, range: 0...20, step: 1, suffix: "%")
            } header: {
                Text("Layout")
            } footer: {
                Text("Resize the sidebar by dragging its inner edge. Transparency thins the container fills over the glass; blur is how frosted the glass is.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Liquid Glass", isOn: a.liquidGlass)
                if appearance.appearance.liquidGlass {
                    Toggle("Tint the glass with the accent", isOn: a.glassTinted)
                    Toggle("Lift under the pointer", isOn: a.glassInteractive)
                }
            } header: {
                Text("Glass")
            } footer: {
                Text("The floating surfaces — command palette, panels, popovers, the corner kit and its grab tab — wear native Liquid Glass on macOS 26 and later. Off falls back to frosted material everywhere. \(glassAvailable ? "" : "This Mac renders the material fallback.")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Chrome", selection: a.chromeStyle) {
                    Text("Minimal — navigation and the address").tag("floating")
                    Text("Classic — the full toolbar").tag("attached")
                }
                Toggle("Compact address bar", isOn: a.compactAddressBar)
                Picker("Align the address", selection: a.addressAlignment) {
                    Text("Left").tag("left")
                    Text("Centered").tag("center")
                    Text("Right").tag("right")
                }
                ForEach(Command.allCases) { command in
                    Toggle(isOn: toolbarBinding(command)) {
                        HStack(spacing: 8) {
                            Image(systemName: command.icon).frame(width: 20).foregroundStyle(.secondary)
                            Text(command.title)
                        }
                    }
                }
            } header: {
                Text("Toolbar")
            } footer: {
                Text("Checked commands are placed on one of three shelves: a cluster on either side of the address, or behind the grab tab at the page's bottom right. View → Customize Controls starts wiggle mode, where you drag a button between them (or click it to cycle) — back, forward and reload included. The sidebar toggle keeps its home by the traffic lights. Classic chrome shows everything as one toolbar instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Start Page") {
                TextField("Greeting", text: a.startPageGreeting, prompt: Text("Rune"))
                Toggle("Show favorites", isOn: a.startPageShowFavorites)
                Toggle("Show recent history", isOn: a.startPageShowRecents)
                ColorTokenRow(label: "Background", token: a.startPageBackground)
            }
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: appIconPreview)
                        .resizable().scaledToFit().frame(width: 56, height: 56)
                    Toggle("Custom app icon", isOn: customIconOn)
                    Spacer()
                }
                if appearance.appearance.appIconBackground != "default" {
                    ColorTokenRow(label: "Background", token: a.appIconBackground, allowSystem: false)
                    ColorTokenRow(label: "Rune", token: a.appIconGlyph, allowSystem: false)
                }
            } header: {
                Text("App Icon")
            } footer: {
                Text("Custom icons are drawn from the rune glyph in your colors and apply to the Dock while Rune runs. Off = the bundled icon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Window") {
                Toggle("Hide traffic lights", isOn: a.hideTrafficLights)
                Text("Hides the red/yellow/green buttons. Drag the toolbar to move the window; ⌘W / ⌘M still work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset to Default", role: .destructive) { appearance.resetToDefault() }
            }
        }
        .formStyle(.grouped)
    }

    private var customIconOn: Binding<Bool> {
        Binding(
            get: { appearance.appearance.appIconBackground != "default" },
            set: { on in
                appearance.appearance.appIconBackground = on ? "#48D4EA" : "default"
                appearance.appearance.appIconGlyph = on ? "#002678" : "default"
            })
    }

    private var appIconPreview: NSImage {
        AppIconRenderer.custom(for: appearance.appearance, size: 256)
            ?? (NSImage(named: NSImage.applicationIconName) ?? NSImage())
    }

    /// Membership toggle for a command in the toolbar button list — checking
    /// appends it after the existing buttons, unchecking removes it.
    private func toolbarBinding(_ command: Command) -> Binding<Bool> {
        Binding(
            get: { appearance.appearance.toolbarButtons.contains(command.rawValue) },
            set: { on in
                // The store's verbs, so the strip list stays consistent —
                // unchecking here is the same act as wiggle mode's minus.
                if on { appearance.move(command.rawValue, to: .corner) }
                else { appearance.disableControl(command.rawValue) }
            })
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range, step: step).tint(appearance.accent)
            Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct ColorTokenRow: View {
    let label: String
    @Binding var token: String
    var allowSystem = true

    private var color: Binding<Color> {
        Binding(get: { Color(hex: token) ?? .gray }, set: { token = $0.hex ?? token })
    }
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if allowSystem {
                Toggle("System", isOn: Binding(
                    get: { token == "system" },
                    set: { token = $0 ? "system" : (Color(nsColor: .windowBackgroundColor).hex ?? "#888888") }))
                    .toggleStyle(.checkbox)
            }
            if token != "system" {
                ColorPicker("", selection: color, supportsOpacity: false).labelsHidden()
            }
        }
    }
}

// MARK: Presets

private struct PresetsPane: View {
    @ObservedObject var appearance: AppearanceStore
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Your Presets") {
                ForEach(appearance.presets) { preset in
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: preset.appearance.accent) ?? .gray).frame(width: 14, height: 14)
                        Text(preset.name)
                        Spacer()
                        Button("Apply") { appearance.apply(preset) }
                        Button {
                            exportPreset(preset)
                        } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                        Button(role: .destructive) { appearance.delete(preset) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Save Current Look") {
                HStack {
                    TextField("Preset name", text: $newName)
                    Button("Save") {
                        appearance.saveCurrentAsPreset(named: newName.isEmpty ? "My Preset" : newName)
                        newName = ""
                    }
                }
            }
            Section {
                Button("Import Preset…") { importPreset() }
            } footer: {
                Text("Presets are shareable .runetheme files — export one and send it to a friend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportPreset(_ preset: ThemePreset) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).runetheme"
        panel.allowedContentTypes = [UTType(filenameExtension: "runetheme") ?? .json]
        if panel.runModal() == .OK, let url = panel.url {
            appearance.apply(preset)   // export exports current; make preset current first
            appearance.export(to: url, name: preset.name)
        }
    }
    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "runetheme") ?? .json, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { _ = appearance.importPreset(from: url) }
    }
}

// MARK: Browsing (search + data)

private struct BrowsingPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var sites: SiteSettings
    let model: () -> BrowserModel

    @State private var importing = false
    @State private var importResult: String?

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search engine", selection: $settings.searchEngine) {
                    ForEach(settings.allEngines) { Text($0.name).tag($0) }
                }
            }
            Section {
                Picker("New tabs open with", selection: $settings.newTabBehavior) {
                    ForEach(NewTabBehavior.allCases) { Text($0.label).tag($0) }
                }
                if settings.newTabBehavior == .homePage {
                    TextField("Home page", text: $settings.homePageURL,
                              prompt: Text("example.com"))
                }
                Picker("Place new tabs", selection: $settings.newTabPlacement) {
                    ForEach(NewTabPlacement.allCases) { Text($0.label).tag($0) }
                }
                Picker("Links from other apps open in", selection: $settings.externalLinks) {
                    ForEach(ExternalLinkBehavior.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("New Tabs")
            } footer: {
                Text("⌘T never stacks empty tabs — if a start page is already open, it's focused instead. A Segment is a window holding just that page, with one button to keep it; ⇧-click any link to peek at it the same way.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Block ads and trackers", isOn: $settings.blockContent)
                if settings.blockContent {
                    Toggle("Hide cookie banners", isOn: $settings.hideCookieBanners)
                }
                LabeledContent("Sites you've excepted") {
                    HStack {
                        Text("\(sites.blockingExceptions.count)").foregroundStyle(.secondary)
                        Button("Clear") {
                            for host in sites.blockingExceptions { sites.setBlocking(nil, for: host) }
                            model().reloadBlocking()
                        }
                        .disabled(sites.blockingExceptions.isEmpty)
                    }
                }
            } header: {
                Text("Content Blocking")
            } footer: {
                Text("WebKit compiles the rules once and enforces them itself, so a blocked request is never made and the page pays nothing for it. \"\(Command.toggleBlocking.title)\" in the View menu makes an exception for wherever you are. Cookie banners are hidden rather than answered — a wall that locks scrolling may still lock it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Unload a saved tab after", selection: $settings.hibernateAfter) {
                    Text("Never").tag(0.0)
                    Text("15 minutes").tag(15.0)
                    Text("1 hour").tag(60.0)
                    Text("4 hours").tag(240.0)
                }
                Picker("Close an untouched tab after", selection: $settings.archiveAfter) {
                    Text("Never").tag(0.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("3 days").tag(72.0)
                }
            } header: {
                Text("Tidying Up")
            } footer: {
                Text("Both off by default — this is Rune deciding to put something away that you opened, which should be your call. An unloaded saved tab keeps its row and comes back when you click it; a closed tab is still in history. Neither ever touches what's on screen or what's making noise.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Reopen last session's tabs on launch", isOn: $settings.restoreSession)
            } header: {
                Text("Session")
            } footer: {
                Text("Off by default: session tabs are meant to be disposable. Pinned tabs and favorites always come back either way.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Save downloads to", selection: $settings.downloadLocation) {
                    ForEach(DownloadLocation.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("⌥⌘L lists what you've fetched this launch. Turn “\(Command.showDownloads.title)” on under Appearance ▸ Toolbar for a button with live progress.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Zoomed sites") {
                    HStack {
                        Text("\(sites.zoomedHosts)").foregroundStyle(.secondary)
                        Button("Reset All") { sites.clearZoom() }
                            .disabled(sites.zoomedHosts == 0)
                    }
                }
            } header: {
                Text("Zoom")
            } footer: {
                Text("⌘+ and ⌘− set the zoom for the whole site, remembered for next time. ⌘0 forgets it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    ForEach(BookmarkImport.Source.allCases) { source in
                        Button("Import from \(source.label)") { runImport(source) }
                            .disabled(importing)
                    }
                    if importing { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if let importResult {
                    Text(importResult).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Bookmarks")
            } footer: {
                Text("Bookmarks land in your pinned shelf, keeping their folders. Anything you already have is skipped, so importing twice is safe.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Auto Picture in Picture", selection: $settings.autoPiP) {
                    ForEach(AutoPiPMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Return video to the page when you come back", isOn: $settings.autoPiPReturnInline)
                Toggle("Only videos playing sound", isOn: $settings.autoPiPAudibleOnly)
            } header: {
                Text("Media")
            } footer: {
                Text("A playing video pops into a floating window when you leave its tab. \"\(Command.togglePiP.title)\" in the View menu toggles it manually. Sound-only keeps muted autoplay videos — hero banners, hover previews — from popping up uninvited.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Auto-tag saves with AI", isOn: $settings.finderAutoTag)
                HStack {
                    Text("Batch collect: skip images smaller than")
                    TextField("", value: $settings.finderMinCollectSize, format: .number)
                        .frame(width: 50).multilineTextAlignment(.trailing)
                    Text("px")
                }
            } header: {
                Text("Finder")
            } footer: {
                Text("The Finder saves inspiration from the web — right-click any image, press ⌥S for the image under your cursor, or ⇧⌘S to collect a whole page. Open it with ⌥⌘F.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browsing Data") {
                LabeledContent("History") {
                    HStack { Text("\(history.entries.count) entries").foregroundStyle(.secondary)
                        Button("Clear") { history.clear() } }
                }
                Text("You stay signed in across launches — cookies and site data persist automatically. A private window (⇧⌘N) keeps none of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func runImport(_ source: BookmarkImport.Source) {
        importing = true
        importResult = nil
        Task {
            defer { importing = false }
            do {
                let added = model().importBookmarks(try await BookmarkImport.load(from: source))
                importResult = added == 0
                    ? "Nothing new — those \(source.label) bookmarks are already pinned."
                    : "Added \(added) bookmark\(added == 1 ? "" : "s") from \(source.label)."
            } catch BookmarkImport.Failure.cancelled {
                importResult = nil
            } catch {
                importResult = error.localizedDescription
            }
        }
    }
}

// MARK: Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var shortcuts: ShortcutStore
    var body: some View {
        Form {
            Section {
                ForEach(Command.allCases) { command in
                    HStack {
                        Image(systemName: command.icon).frame(width: 20).foregroundStyle(.secondary)
                        Text(command.title)
                        Spacer()
                        KeyRecorderView(current: shortcuts.shortcut(for: command)) {
                            shortcuts.set($0, for: command)
                        }
                    }
                }
            } header: {
                HStack { Text("Keyboard Shortcuts"); Spacer()
                    Button("Reset All") { shortcuts.resetAll() }.font(.caption) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Key recorder

private struct KeyRecorderView: View {
    let current: Shortcut
    let onRecord: (Shortcut?) -> Void
    @State private var recording = false

    var body: some View {
        HStack(spacing: 6) {
            Button { recording.toggle() } label: {
                Text(recording ? "Press keys…" : current.display).frame(minWidth: 76).monospaced()
            }
            .buttonStyle(.bordered)
            .background(KeyCapture(recording: $recording) { onRecord($0); recording = false }.frame(width: 0, height: 0))
            Button { onRecord(nil) } label: { Image(systemName: "arrow.uturn.backward").font(.caption) }
                .buttonStyle(.borderless).help("Reset to default")
        }
    }
}

private struct KeyCapture: NSViewRepresentable {
    @Binding var recording: Bool
    let onCapture: (Shortcut?) -> Void
    func makeNSView(context: Context) -> RecorderNSView { let v = RecorderNSView(); v.onCapture = onCapture; return v }
    func updateNSView(_ view: RecorderNSView, context: Context) {
        view.onCapture = onCapture
        if recording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }
}

private final class RecorderNSView: NSView {
    var onCapture: ((Shortcut?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let key = chars.first, !mods.isEmpty else { NSSound.beep(); return }
        onCapture?(Shortcut(key: String(key), modifiers: mods.rawValue))
        window?.makeFirstResponder(nil)
    }
}


// MARK: AI

private struct AIPane: View {
    @ObservedObject var ai: AIService
    @ObservedObject var settings: SettingsStore
    @State private var key = ""
    @State private var saved = false

    private var claude: ClaudeService { ai.claude }

    var body: some View {
        Form {
            Section {
                // The picker is only a choice when there's something to choose
                // between: without the local model, Claude is simply what runs.
                if ai.localAvailable {
                    Picker("Run AI with", selection: $settings.aiModel) {
                        ForEach(AIModel.allCases) { Text($0.label).tag($0) }
                    }
                    Text(settings.aiModel.detail).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: ai.localAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ai.localAvailable ? .green : .orange)
                    Text(ai.localAvailable
                         ? "On-device model ready."
                         : (ai.localUnavailableReason ?? "On-device model unavailable."))
                    Spacer()
                }
            } header: {
                Text("Model")
            } footer: {
                Text(ai.localAvailable
                     ? "On-device runs on Apple Intelligence: free, offline, and the page never leaves this Mac. Claude is sharper on hard questions, and costs per request."
                     : "Rune prefers Apple's on-device model. Without it, AI features run on Claude — and with neither, Rune hides them rather than dangling something you can't use.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: claude.hasKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(claude.hasKey ? .green : .orange)
                    Text(claude.hasKey ? "API key saved in your Keychain." : "No API key yet.")
                    Spacer()
                    if claude.hasKey {
                        Button("Remove", role: .destructive) { claude.setKey(""); key = "" }
                    }
                }
                SecureField("sk-ant-…", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Save Key", action: save).disabled(key.isEmpty)
                    if saved { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("Optional — only needed to run AI on Claude. Stored in the macOS Keychain, never in Rune's settings files, and never sent anywhere but api.anthropic.com. Get a key at console.anthropic.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Summarize links on hover", isOn: $settings.linkHoverEnabled)
                if settings.linkHoverEnabled {
                    HStack {
                        Text("Hover delay")
                        Slider(value: $settings.linkHoverDelay, in: 0.1...10.0, step: 0.05)
                        Text(String(format: "%.2f s", settings.linkHoverDelay))
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text("Link Previews")
            } footer: {
                Text("How long a link must sit under your cursor before Rune summarizes it. Applies immediately, even to open pages.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Label("Hover any link for a summary of where it goes", systemImage: "link")
                Label("Select text for Explain / Summarize / Translate", systemImage: "text.cursor")
                Label("Press ⌘J to ask about the page you're on", systemImage: "sparkles")
                Label("Type a question in the address bar to find a page from memory", systemImage: "magnifyingglass")
            } header: {
                Text("What AI Does Here")
            } footer: {
                Text(privacyNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Where your page text actually goes depends on which model is answering,
    /// and that difference is the entire argument for running locally — so say
    /// which one it is rather than something vague that covers both.
    private var privacyNote: String {
        switch ai.active {
        case .onDevice:
            "Running on Apple's on-device model — page text never leaves this Mac."
        case .claude:
            "Running on \(ClaudeService.model) — page text goes to Anthropic when you invoke one of these, and at no other time."
        case nil:
            "No model available, so Rune hides these rather than showing you something that can't run."
        }
    }

    private func save() {
        claude.setKey(key)
        key = ""
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
