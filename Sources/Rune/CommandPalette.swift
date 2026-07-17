import SwiftUI

/// ⌘K overlay. Fuzzy-matches every command in the registry, plus browsing
/// history and a "go / search" action — one place to do anything by keyboard.
///
/// ⌘T's address overlay is this, in `.newTab` mode: an address bar is already
/// most of a palette, so it's a mode rather than a second overlay that would
/// have to be kept in step with this one forever.
struct CommandPalette: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @Binding var isPresented: Bool
    var mode: Mode = .everything
    @EnvironmentObject var appearance: AppearanceStore

    enum Mode {
        /// ⌘K: commands, history, and a go/search action.
        case everything
        /// ⌘T: just a destination, opened in a new tab. No commands — you asked
        /// for an address bar, not a menu.
        case newTab
    }

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    // Memoized, same rationale as the address bar: recomputed once per
    // keystroke, not on every body evaluation — arrow keys shouldn't
    // re-search history.
    @State private var items: [Item] = []

    enum Item: Identifiable {
        case command(Command)
        case history(HistoryEntry)
        case navigate(String)   // typed URL or search

        var id: String {
            switch self {
            case .command(let c): "cmd:\(c.rawValue)"
            case .history(let h): "his:\(h.url)"
            case .navigate(let q): "nav:\(q)"
            }
        }
    }

    private func computeItems() -> [Item] {
        var result: [Item] = []
        let q = query.trimmingCharacters(in: .whitespaces)

        if mode == .everything {
            let commands = q.isEmpty
                ? Command.allCases
                : Command.allCases.filter { fuzzy(q, $0.title) }
            result += commands.map(Item.command)
        }

        if !q.isEmpty {
            if mode == .newTab {
                // The same offers in the same order as the address bar — this
                // IS one, in a different coat. Ranked history used to lead
                // here, which sent "webkit.org" ⏎ to a blog post on it.
                result += addressSuggestions(for: q, model: model).compactMap { s in
                    switch s {
                    case .navigate(let q): .navigate(q)
                    case .history(let e): .history(e)
                    case .askAI: nil   // the palette has no row for it
                    }
                }
            } else {
                result += model.history.predict(q, limit: 5).map(Item.history)
                result.append(.navigate(q))
            }
        } else if mode == .newTab {
            // An empty address bar still has somewhere to go.
            result += model.history.search("", limit: 8).map(Item.history)
        }
        return result
    }

    private var prompt: String {
        mode == .newTab ? "Open in a new tab…" : "Type a command, address, or search…"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: mode == .newTab ? "plus.magnifyingglass" : "command")
                        .foregroundStyle(.secondary)
                    TextField(prompt, text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(activateSelected)
                        .onChange(of: query) { selection = 0; items = computeItems() }
                }
                .padding(.horizontal, 18).padding(.vertical, 15)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                PaletteRow(item: item, model: model, selected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = index; activateSelected() }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(appearance.hairline))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            .padding(.top, 90)
        }
        .onAppear { focused = true; items = computeItems() }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .dismissOnEscape { close() }
    }

    private func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func activateSelected() {
        guard items.indices.contains(selection) else { return }
        close()
        switch items[selection] {
        case .command(let c): dispatch(c)
        case .history(let h): open(h.url)
        case .navigate(let q): open(q)
        }
    }

    /// ⌘K navigates where you are; ⌘T was a request for a new tab.
    private func open(_ input: String) {
        guard mode == .newTab else { model.navigate(input); return }
        guard let url = model.resolve(input) else { return }
        model.newTab(url: url)
    }

    private func close() { isPresented = false }

    /// Simple subsequence fuzzy match.
    private func fuzzy(_ needle: String, _ haystack: String) -> Bool {
        let n = Array(needle.lowercased()), h = Array(haystack.lowercased())
        var i = 0
        for ch in h where i < n.count && ch == n[i] { i += 1 }
        return i == n.count
    }
}

private struct PaletteRow: View {
    let item: CommandPalette.Item
    @ObservedObject var model: BrowserModel
    let selected: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(selected ? .white : .primary).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(selected ? .white.opacity(0.8) : .secondary).lineLimit(1) }
            }
            Spacer()
            if let trailing { Text(trailing).font(.callout).foregroundStyle(selected ? .white.opacity(0.9) : .secondary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? appearance.accent : .clear))
    }

    private var icon: String {
        switch item {
        case .command(let c): c.icon
        case .history: "clock"
        case .navigate(let q): model.resolve(q).map { _ in "arrow.up.forward" } ?? "magnifyingglass"
        }
    }
    private var title: String {
        switch item {
        case .command(let c): return c.title
        case .history(let h): return h.title.isEmpty ? h.url : h.title
        case .navigate(let q):
            if let url = model.resolve(q), url.host != nil, q.contains(".") { return "Go to \(q)" }
            return "Search for “\(q)”"
        }
    }
    private var subtitle: String? {
        switch item {
        case .history(let h): h.url
        default: nil
        }
    }
    private var trailing: String? {
        switch item {
        case .command(let c): model.shortcuts.shortcut(for: c).display
        default: nil
        }
    }
}
