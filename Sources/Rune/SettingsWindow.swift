import AppKit
import SwiftUI

/// Owns the Settings window (search engine + shortcut remapping + history).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let settings: SettingsStore
    let shortcuts: ShortcutStore
    let history: HistoryStore

    init(settings: SettingsStore, shortcuts: ShortcutStore, history: HistoryStore) {
        self.settings = settings
        self.shortcuts = shortcuts
        self.history = history
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Rune Settings"
            w.center()
            w.setFrameAutosaveName("RuneSettings")
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: RuneSettingsView(settings: settings, shortcuts: shortcuts, history: history))
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

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search engine", selection: $settings.searchEngine) {
                    ForEach(settings.allEngines) { engine in
                        Text(engine.name).tag(engine)
                    }
                }
            }

            Section("Browsing Data") {
                LabeledContent("History") {
                    HStack(spacing: 10) {
                        Text("\(history.entries.count) entries").foregroundStyle(.secondary)
                        Button("Clear") { history.clear() }
                    }
                }
                Text("You stay signed in across launches — cookies and site data persist automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Command.allCases) { command in
                    HStack {
                        Image(systemName: command.icon).frame(width: 20).foregroundStyle(.secondary)
                        Text(command.title)
                        Spacer()
                        KeyRecorderView(current: shortcuts.shortcut(for: command)) { newShortcut in
                            shortcuts.set(newShortcut, for: command)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Keyboard Shortcuts")
                    Spacer()
                    Button("Reset All") { shortcuts.resetAll() }.font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 480)
    }
}

// MARK: - Key recorder

private struct KeyRecorderView: View {
    let current: Shortcut
    let onRecord: (Shortcut?) -> Void
    @State private var recording = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording.toggle()
            } label: {
                Text(recording ? "Press keys…" : current.display)
                    .frame(minWidth: 76)
                    .monospaced()
            }
            .buttonStyle(.bordered)
            .background(
                KeyCapture(recording: $recording) { shortcut in
                    onRecord(shortcut)
                    recording = false
                }
                .frame(width: 0, height: 0)
            )

            Button {
                onRecord(nil)   // reset this one to default
            } label: {
                Image(systemName: "arrow.uturn.backward").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
        }
    }
}

private struct KeyCapture: NSViewRepresentable {
    @Binding var recording: Bool
    let onCapture: (Shortcut?) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderNSView, context: Context) {
        view.onCapture = onCapture
        if recording {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
}

private final class RecorderNSView: NSView {
    var onCapture: ((Shortcut?) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let key = chars.first, !mods.isEmpty else {
            NSSound.beep()   // require at least one modifier for a global shortcut
            return
        }
        onCapture?(Shortcut(key: String(key), modifiers: mods.rawValue))
        window?.makeFirstResponder(nil)
    }
}
