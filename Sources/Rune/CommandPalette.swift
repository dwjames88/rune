import SwiftUI

/// ⌘K overlay. Fuzzy-matches every command in the registry, plus browsing
/// history and a "go / search" action — one place to do anything by keyboard.
struct CommandPalette: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

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

    private var items: [Item] {
        var result: [Item] = []
        let q = query.trimmingCharacters(in: .whitespaces)

        let commands = q.isEmpty
            ? Command.allCases
            : Command.allCases.filter { fuzzy(q, $0.title) }
        result += commands.map(Item.command)

        if !q.isEmpty {
            result += model.history.search(q, limit: 5).map(Item.history)
            result.append(.navigate(q))
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command").foregroundStyle(.secondary)
                    TextField("Type a command, address, or search…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(activateSelected)
                        .onChange(of: query) { selection = 0 }
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func activateSelected() {
        let items = self.items
        guard items.indices.contains(selection) else { return }
        switch items[selection] {
        case .command(let c): close(); dispatch(c)
        case .history(let h): close(); model.navigate(h.url)
        case .navigate(let q): close(); model.navigate(q)
        }
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.accent : .clear))
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
