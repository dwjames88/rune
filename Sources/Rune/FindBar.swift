import SwiftUI
import WebKit

/// ⌘F. WebKit does the finding, highlighting and scrolling; this is only the
/// bar.
struct FindBar: View {
    @ObservedObject var model: BrowserModel
    @Binding var isPresented: Bool
    @EnvironmentObject var appearance: AppearanceStore

    @State private var query = ""
    @State private var missing = false
    /// "3/17". `WKFindResult` only reports whether it hit, never how many, so
    /// the total is counted separately and the position is tracked here — we
    /// know it, because we're the one deciding where each search starts.
    @State private var matches = 0
    @State private var current = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            TextField("Find on page", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 170)
                .focused($focused)
                .foregroundStyle(missing ? Color.red : appearance.chromeText)
                .onSubmit { find(forward: true) }
                .onChange(of: query) { find(forward: true, fromTop: true) }

            if !query.isEmpty {
                // Monospaced so the bar doesn't twitch as the numbers change.
                Text(matches == 0 ? "0" : "\(current)/\(matches)")
                    .font(appearance.font(11)).monospacedDigit()
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            }
            step("chevron.up", "Previous match") { find(forward: false) }
            step("chevron.down", "Next match (↩)") { find(forward: true) }
            Divider().frame(height: 14)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                .buttonStyle(.plain).help("Done (esc)")
                .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(missing ? Color.red.opacity(0.5) : appearance.hairline))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .dismissOnEscape { close() }
        .onAppear { focused = true }
        // ⌘F while the bar is already up re-focuses and selects, as everywhere else.
        .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) { _ in focused = true }
    }

    private func step(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
            .buttonStyle(.plain)
            .disabled(query.isEmpty)
            .help(help)
            .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
    }

    /// WebKit searches onward from the current selection, and its own last hit
    /// counts as one. That's what you want for next/previous, but not while
    /// you're still typing — each new keystroke has to start from the top of
    /// the page, or the search runs away down it. Clearing the selection is how
    /// you rewind, since `find` takes no starting point.
    private func find(forward: Bool, fromTop: Bool = false) {
        guard let webView = model.activeTab?.webView else { return }
        guard !query.isEmpty else {
            missing = false; matches = 0; current = 0; clearSelection(); return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        // Typing outruns the page: every keystroke starts a search, and they
        // don't come back in order. A keystroke that's already been superseded
        // must not report its answer over a newer one's.
        let searched = query
        Task {
            if fromTop {
                await recount(searched, in: webView)
                guard searched == query else { return }
                _ = try? await webView.evaluateJavaScript(Self.clearSelectionJS)
            }
            let found = (try? await webView.find(searched, configuration: configuration))?.matchFound ?? false
            guard searched == query else { return }
            missing = !found
            guard found, matches > 0 else { current = 0; return }
            // We control where every search starts, so the position follows
            // from the direction — no need to ask the page where we landed.
            if fromTop {
                current = 1
            } else if forward {
                current = current % matches + 1
            } else {
                current = (current - 2 + matches) % matches + 1
            }
        }
    }

    /// Count the hits ourselves, since WebKit won't. `innerText` rather than
    /// the DOM: it joins text across inline tags, so "do<b>main</b>" counts the
    /// once WebKit's find also sees, and it leaves out what the page hides.
    /// The total can still drift from WebKit's own idea on exotic pages (text
    /// inside subframes); it only decides where the counter wraps.
    private func recount(_ needle: String, in webView: WKWebView) async {
        let count = try? await webView.callAsyncJavaScript(
            Self.countJS, arguments: ["q": needle], in: nil, contentWorld: .page)
        guard needle == query else { return }
        matches = (count as? Int) ?? Int((count as? Double) ?? 0)
    }

    /// Takes `q` as a real argument, so a query full of quotes and backslashes
    /// needs no escaping on the way in.
    private static let countJS = """
    const body = document.body;
    const needle = q.toLowerCase();
    if (!body || !needle) { return 0; }
    const text = (body.innerText || '').toLowerCase();
    let n = 0, i = text.indexOf(needle);
    while (i !== -1) { n++; i = text.indexOf(needle, i + needle.length); }
    return n;
    """

    /// WebKit's find leaves its hit selected, and dropping the selection is
    /// what clears the highlight — there's no public API to clear it directly.
    /// The trailing `true` gives evaluateJavaScript a value it can bridge back.
    private static let clearSelectionJS = "window.getSelection().removeAllRanges(); true"

    private func clearSelection() {
        model.activeTab?.webView.evaluateJavaScript(Self.clearSelectionJS)
    }

    private func close() {
        clearSelection()
        isPresented = false
    }
}
