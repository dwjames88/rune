import SwiftUI

/// The sidebar and the tab strip, folded into one room: saved sites and
/// folders up top (the Mac sidebar's cargo, and what sync will mirror),
/// open tabs as snapshot cards below. Tap a card to enter it, ✕ to close,
/// tap a saved site to go there — it focuses the tab that already has it.
struct TabSwitcher: View {
    @ObservedObject var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !store.favorites.isEmpty {
                        savedSection("Favorites", items: store.favorites, removable: true)
                    }
                    ForEach(store.folders) { folder in
                        savedSection(folder.name, items: folder.items, removable: false)
                    }

                    Text("Tabs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.tabs) { tab in
                            TabCard(tab: tab, select: {
                                store.select(tab)
                                dismiss()
                            }, close: {
                                withAnimation(.easeOut(duration: 0.18)) { store.close(tab) }
                            })
                        }
                    }
                }
                .padding(16)
                .padding(.top, 54)
                .padding(.bottom, 96)
            }

            Button {
                store.newTab()
                dismiss()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .font(.system(size: RuneTheme.fontSize, weight: .semibold))
                    .padding(.horizontal, 22)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
            .runeGlass(tint: RuneTheme.accent, in: Capsule())
            .padding(.bottom, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .runeGlass(in: Circle())
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
    }

    /// One shelf of saved sites: a micro-label and chips that wrap — every
    /// saved site visible, nothing hiding past an edge.
    private func savedSection(_ title: String, items: [Favorite], removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SavedChip(item: item, isOpen: store.isOpen(item.url)) {
                        store.open(item.url)
                        dismiss()
                    }
                    .contextMenu {
                        if removable {
                            Button(role: .destructive) {
                                store.removeFavorite(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A saved site as a chip: glyph, name, and a quiet dot when it's already
/// open somewhere.
private struct SavedChip: View {
    let item: Favorite
    let isOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                SiteGlyph(name: item.name)
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if isOpen {
                    Circle().fill(RuneTheme.accent).frame(width: 5, height: 5)
                }
            }
            .padding(.leading, 6).padding(.trailing, 12)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .runeGlass(in: Capsule())
    }
}

/// One open tab: its snapshot as a card, the ✕ riding the card's corner,
/// the name beneath — the reference deck's grammar in Rune's radius.
private struct TabCard: View {
    @ObservedObject var tab: MobileTab
    let select: () -> Void
    let close: () -> Void

    private var label: String {
        if !tab.title.isEmpty { return tab.title }
        return tab.compactHost.isEmpty ? "New Tab" : tab.compactHost
    }

    var body: some View {
        VStack(spacing: 7) {
            Button(action: select) {
                Group {
                    if let snapshot = tab.snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color(uiColor: .systemBackground)
                            VStack(spacing: 6) {
                                Text("Rune").font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                if !tab.compactHost.isEmpty {
                                    Text(tab.compactHost).font(.system(size: 11))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                        }
                    }
                }
                .frame(height: 214)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        // The visible circle is 30pt; the finger gets 44.
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .runeGlass(in: Circle().inset(by: 7))
            }

            HStack(spacing: 6) {
                SiteGlyph(name: label, size: 18)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
    }
}
