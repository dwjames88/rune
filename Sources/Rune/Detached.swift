import AppKit
import SwiftUI
import WebKit

/// A page in a window of its own: no sidebar, no shelf, no tabs — just the
/// thing you wanted to look at, and a way to keep it if it turns out to matter.
///
/// Two features, one window. **Glance** (⇧-click a link) floats it over what
/// you're doing so you can look without losing your place. **Segment** catches a
/// URL opened from another app while Rune is your default browser, so a link
/// from Slack doesn't barge into your tabs. They differ by whether it floats
/// and what it's called — nothing else, which is why there's one of them.
@MainActor
final class DetachedWindow: NSObject, NSWindowDelegate {
    let tab: Tab
    private let window: NSWindow
    private let onClose: (DetachedWindow) -> Void

    init(tab: Tab, floating: Bool, appearance: AppearanceStore,
         promote: @escaping (Tab) -> Void, onClose: @escaping (DetachedWindow) -> Void) {
        self.tab = tab
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false   // `detached` holds it; see main.swift
        // A glance sits over the browser you're reading; a segment is a window
        // in its own right and shouldn't hover over other apps.
        if floating { window.level = .floating }
        super.init()

        let hosting = NSHostingController(rootView: DetachedView(
            tab: tab,
            promote: { [weak self] in
                promote(tab)
                self?.close()
            },
            dismiss: { [weak self] in self?.close() }
        ).environmentObject(appearance))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.delegate = self
        // Assigning a contentViewController re-sizes the window to whatever the
        // view says it wants, throwing away the contentRect above — which for a
        // web view is nothing at all, so the window arrives invisibly small.
        // Size it after, exactly as the browser window does.
        window.setContentSize(NSSize(width: 860, height: 640))
        window.minSize = NSSize(width: 420, height: 320)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        // Nothing survives the window it was in.
        tab.retire()
        onClose(self)
    }
}

/// The whole chrome: where you are, and the one decision worth offering.
private struct DetachedView: View {
    @ObservedObject var tab: Tab
    let promote: () -> Void
    let dismiss: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Room for the traffic lights.
                Color.clear.frame(width: 56, height: 1)
                Favicon(image: tab.favicon, name: tab.displayName, size: 14, loading: tab.isLoading)
                Text(tab.displayName).lineLimit(1).font(appearance.font(12, weight: .medium))
                Text(tab.webView.url?.host ?? "").lineLimit(1)
                    .font(appearance.font(11))
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                Spacer(minLength: 8)
                Button(action: promote) {
                    Label("Open as Tab", systemImage: "arrow.up.forward.square")
                        .font(appearance.font(11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(appearance.accent)
                .help("Keep this — move it into your tabs (⌘↩)")
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(appearance.chrome)
            .foregroundStyle(appearance.chromeText)
            Divider()
            WebContainer(webView: tab.webView)
        }
        .background(appearance.windowBG)
        .font(appearance.uiFont)
        .dismissOnEscape { dismiss() }
    }
}
