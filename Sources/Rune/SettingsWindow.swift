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
    let claude: ClaudeService

    init(settings: SettingsStore, shortcuts: ShortcutStore, history: HistoryStore,
         appearance: AppearanceStore, claude: ClaudeService) {
        self.settings = settings; self.shortcuts = shortcuts; self.history = history
        self.appearance = appearance; self.claude = claude
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Rune Settings"
            w.center(); w.setFrameAutosaveName("RuneSettings"); w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: RuneSettingsView(
                settings: settings, shortcuts: shortcuts, history: history,
                appearance: appearance, claude: claude))
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
    @ObservedObject var claude: ClaudeService

    enum Tab: String, CaseIterable { case appearance = "Appearance", presets = "Presets", browsing = "Browsing", claude = "Claude", shortcuts = "Shortcuts" }
    @State private var tab: Tab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(12)
            Divider()
            switch tab {
            case .appearance: AppearancePane(appearance: appearance)
            case .presets: PresetsPane(appearance: appearance)
            case .browsing: BrowsingPane(settings: settings, history: history)
            case .claude: ClaudePane(claude: claude)
            case .shortcuts: ShortcutsPane(shortcuts: shortcuts)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}

// MARK: Appearance

private struct AppearancePane: View {
    @ObservedObject var appearance: AppearanceStore
    var a: Binding<Appearance> { $appearance.appearance }

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
            Section("Layout") {
                sliderRow("Sidebar width", value: a.sidebarWidth, range: 180...360, step: 5, suffix: "px")
                sliderRow("Corner radius", value: a.cornerRadius, range: 0...16, step: 1, suffix: "px")
                Toggle("Sidebar on the right", isOn: a.sidebarOnRight)
            }
            Section {
                Toggle("Compact address bar", isOn: a.compactAddressBar)
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
                Text("Checked commands appear as buttons before the address bar. Compact address bar shows just the site until you click it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Start Page") {
                TextField("Greeting", text: a.startPageGreeting, prompt: Text("Rune"))
                Toggle("Show favorites", isOn: a.startPageShowFavorites)
                Toggle("Show recent history", isOn: a.startPageShowRecents)
                ColorTokenRow(label: "Background", token: a.startPageBackground)
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

    /// Membership toggle for a command in the toolbar button list — checking
    /// appends it after the existing buttons, unchecking removes it.
    private func toolbarBinding(_ command: Command) -> Binding<Bool> {
        Binding(
            get: { appearance.appearance.toolbarButtons.contains(command.rawValue) },
            set: { on in
                var buttons = appearance.appearance.toolbarButtons
                buttons.removeAll { $0 == command.rawValue }
                if on { buttons.append(command.rawValue) }
                appearance.appearance.toolbarButtons = buttons
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
            } header: {
                Text("New Tabs")
            } footer: {
                Text("⌘T never stacks empty tabs — if a start page is already open, it's focused instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Auto Picture in Picture", selection: $settings.autoPiP) {
                    ForEach(AutoPiPMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Return video to the page when you come back", isOn: $settings.autoPiPReturnInline)
            } header: {
                Text("Media")
            } footer: {
                Text("A playing video pops into a floating window when you leave its tab. \"\(Command.togglePiP.title)\" in the View menu toggles it manually.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browsing Data") {
                LabeledContent("History") {
                    HStack { Text("\(history.entries.count) entries").foregroundStyle(.secondary)
                        Button("Clear") { history.clear() } }
                }
                Text("You stay signed in across launches — cookies and site data persist automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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


// MARK: Claude

private struct ClaudePane: View {
    @ObservedObject var claude: ClaudeService
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        Form {
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
                Text("Stored in the macOS Keychain — never in Rune's settings files, and never sent anywhere but api.anthropic.com. Get a key at console.anthropic.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Label("Hover any link for a summary of where it goes", systemImage: "link")
                Label("Select text for Explain / Summarize / Translate", systemImage: "text.cursor")
                Label("Press ⌘J to ask about the page you're on", systemImage: "sparkles")
                Label("Type a question in the address bar to find a page from memory", systemImage: "magnifyingglass")
            } header: {
                Text("What Claude Does Here")
            } footer: {
                Text("Model: \(ClaudeService.model). Page text is only sent when you invoke one of these.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        claude.setKey(key)
        key = ""
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
