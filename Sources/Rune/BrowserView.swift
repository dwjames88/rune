import Combine
import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    let dispatch: (Command) -> Void

    @State private var showPalette = false
    @State private var paletteMode = CommandPalette.Mode.everything
    @State private var showAsk = false

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                if model.sidebarVisible && !appearance.appearance.sidebarOnRight { sidebar; Divider() }
                ContentArea(model: model, dispatch: dispatch)
                if model.sidebarVisible && appearance.appearance.sidebarOnRight { Divider(); sidebar }
            }
            .animation(.easeInOut(duration: 0.18), value: model.sidebarVisible)
            .background(appearance.windowBG)

            if showAsk {
                AskBar(model: model, ai: model.ai, isPresented: $showAsk)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showPalette {
                CommandPalette(model: model, dispatch: dispatch,
                               isPresented: $showPalette, mode: paletteMode)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showAsk)
        .font(appearance.uiFont)
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) {
            guard $0.aimed(at: model) else { return }
            paletteMode = .everything
            showPalette = true
        }
        // ⌘T, when you've set it to bring up an address bar: the same overlay,
        // asking for a destination instead of a command.
        .onReceive(NotificationCenter.default.publisher(for: .showNewTabOverlay)) {
            guard $0.aimed(at: model) else { return }
            paletteMode = .newTab
            showPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAskBar)) {
            if $0.aimed(at: model) { showAsk = true }
        }
    }

    private var sidebar: some View {
        Sidebar(model: model, dispatch: dispatch)
            .frame(width: appearance.sidebarWidth).transition(.move(edge: .leading))
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: appearance.appearance.hideTrafficLights ? 8 : 28)

            if model.isPrivate { privateBanner } else { SpaceBar(model: model, dispatch: dispatch) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FavoritesSection(model: model)
                    // No header for an empty shelf — the section appears once
                    // something is pinned (⌘D or the tab's context menu).
                    if !model.pinned.isEmpty || !model.folders.isEmpty {
                        PinnedSection(model: model)
                    }
                    SessionSection(model: model)
                }
                .padding(.horizontal, 8).padding(.top, 4)
            }

            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { model.newTab() } label: {
                    Label("New Tab", systemImage: "plus").font(appearance.font(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Button { dispatch(.openFinder) } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .help("Finder — saved inspiration (⌥⌘F)")
            }
            .foregroundStyle(appearance.sidebarSecondary).padding(8)
        }
        .background(appearance.sidebarBG)
        .foregroundStyle(appearance.sidebarText)
    }

    /// Says plainly what this window is and what it doesn't keep. A private
    /// window has no favorites and no pinned rows, so there's room for it.
    private var privateBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eyeglasses").font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("Private").font(appearance.font(12, weight: .semibold))
                Text("No history, no cookies kept.").font(appearance.font(10))
                    .foregroundStyle(appearance.sidebarSecondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(appearance.accent.opacity(0.16)))
        .padding(.horizontal, 8).padding(.bottom, 6)
    }
}

// MARK: Spaces

/// The space switcher. Only earns its row once there's more than one space —
/// a single space is just "your tabs", and a switcher for it is furniture.
///
/// This is for *switching*. Editing lives in Settings ▸ Spaces, which can show
/// every space at once; duplicating the theme and icon pickers here bought a
/// right-click and cost two of everything.
private struct SpaceBar: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @EnvironmentObject var appearance: AppearanceStore
    @State private var renaming: UUID?

    var body: some View {
        if model.spaces.count > 1 {
            HStack(spacing: 4) {
                ForEach(model.spaces) { space in
                    SpaceChip(space: space, current: space.id == model.currentSpaceID)
                        .onTapGesture { model.switchTo(space: space.id) }
                        .contextMenu {
                            Button("Rename…") { renaming = space.id }
                            Button("Edit Spaces…") { dispatch(.openSettings) }
                            if model.spaces.count > 1 {
                                Divider()
                                Button("Delete Space", role: .destructive) { model.deleteSpace(space.id) }
                            }
                        }
                        .popover(isPresented: Binding(
                            get: { renaming == space.id },
                            set: { if !$0 { renaming = nil } })) {
                            RenamePopover(title: "Rename Space", name: space.name) { name in
                                model.updateSpace(space.id) { $0.name = name }
                                renaming = nil
                            }
                        }
                }
                Button { model.switchTo(space: model.addSpace().id) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).help("New Space")
                Spacer(minLength: 0)
            }
            .foregroundStyle(appearance.sidebarSecondary)
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }
}

private struct SpaceChip: View {
    let space: Space
    let current: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Image(systemName: space.icon)
            .font(.system(size: 11))
            .foregroundStyle(current ? appearance.accent : appearance.sidebarSecondary)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(current ? appearance.selection : .clear))
            .contentShape(Rectangle())
            .help(space.name)
    }
}

// MARK: Favorites (≤6, favicon tiles, drop target)

private struct FavoritesSection: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Favorites", trailing: "\(model.favorites.count)/6")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(Array(model.favorites.enumerated()), id: \.element.id) { index, fav in
                    FaviconTile(saved: fav, selected: model.pane(showing: .saved(fav.id)) != nil)
                        .onTapGesture { model.select(.saved(fav.id)) }
                        .draggable(TabDrag(id: fav.id, origin: .favorite))
                        .dropDestination(for: TabDrag.self) { items, _ in
                            guard let drag = items.first else { return false }
                            model.handleDrop(drag, to: .favorites(index)); return true
                        }
                        .contextMenu { TabMenu(model: model, selection: .saved(fav.id), isFavorite: true) }
                }
                if model.favorites.isEmpty {
                    Text("Drag here").font(appearance.font(10))
                        .foregroundStyle(appearance.sidebarSecondary)
                        .frame(height: 34).gridCellColumns(6)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(targeted ? appearance.accent.opacity(0.18) : .clear))
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let drag = items.first else { return false }
                model.handleDrop(drag, to: .favorites(nil)); return true
            } isTargeted: { targeted = $0 }
        }
    }
}

private struct FaviconTile: View {
    let saved: SavedTab
    let selected: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Favicon(png: saved.faviconPNG, name: saved.name, size: 20)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(selected ? appearance.selection : appearance.hover))
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(selected ? appearance.accent : .clear, lineWidth: 1.5))
            .help(saved.name)
    }
}

// MARK: Pinned (+ folders)

private struct PinnedSection: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionHeader(title: "Pinned")
                Spacer()
                Button { _ = model.addFolder() } label: { Image(systemName: "folder.badge.plus").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(appearance.sidebarSecondary).help("New Folder")
            }
            ForEach(model.folders) { folder in FolderView(model: model, folder: folder) }
            ForEach(Array(model.pinned(in: nil).enumerated()), id: \.element.id) { index, saved in
                SavedRow(model: model, saved: saved, origin: .pinned, dropIndex: index, folderID: nil)
            }
            if model.pinned.isEmpty && model.folders.isEmpty {
                Text("Drag a tab here to pin it.").font(appearance.font(11))
                    .foregroundStyle(appearance.sidebarSecondary).padding(.leading, 8).padding(.vertical, 4)
            }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(targeted ? appearance.accent.opacity(0.12) : .clear))
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let drag = items.first else { return false }
            model.handleDrop(drag, to: .pinned(folderID: nil, index: nil)); return true
        } isTargeted: { targeted = $0 }
    }
}

private struct FolderView: View {
    @ObservedObject var model: BrowserModel
    let folder: Folder
    @EnvironmentObject var appearance: AppearanceStore
    @State private var targeted = false
    @State private var pickingIcon = false
    @State private var pickingColor = false
    @State private var renaming = false

    /// A folder is the one thing in the sidebar that carries a colour; without
    /// one it simply wears the appearance accent.
    private var tint: Color { folder.colorHex.flatMap(Color.init(hex:)) ?? appearance.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9)).foregroundStyle(appearance.sidebarSecondary).frame(width: 10)
                Image(systemName: folder.icon).font(.system(size: 11)).foregroundStyle(tint)
                Text(folder.name).font(appearance.font(12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(targeted ? tint.opacity(0.22) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleFolder(folder.id) }
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let drag = items.first else { return false }
                model.handleDrop(drag, to: .pinned(folderID: folder.id, index: nil)); return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                Button("Rename…") { renaming = true }
                Button("Change Icon…") { pickingIcon = true }
                Button("Change Color…") { pickingColor = true }
                Divider()
                Button("Delete Folder", role: .destructive) { model.deleteFolder(folder.id) }
            }
            .popover(isPresented: $pickingIcon) {
                SymbolPicker(symbol: .constant(folder.icon), tint: tint) { icon in
                    model.setFolderIcon(folder.id, icon); pickingIcon = false
                }
            }
            .popover(isPresented: $pickingColor) {
                FolderColorPopover(current: tint, hasColor: folder.colorHex != nil) { hex in
                    model.setFolderColor(folder.id, hex)
                }
            }
            .popover(isPresented: $renaming) {
                RenamePopover(title: "Rename Folder", name: folder.name) {
                    model.renameFolder(folder.id, to: $0); renaming = false
                }
            }

            if !folder.collapsed {
                ForEach(Array(model.pinned(in: folder.id).enumerated()), id: \.element.id) { index, saved in
                    SavedRow(model: model, saved: saved, origin: .pinned, dropIndex: index, folderID: folder.id)
                        .padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: Session tabs

private struct SessionSection: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var targeted = false

    /// The tab list with a split folded into a single row. Two tabs sharing one
    /// window are one thing you're looking at, and the sidebar should say so
    /// once — two rows both claiming to be selected is the same fact told twice.
    /// Only session tabs fold: a pinned tab lives on its shelf whatever else
    /// it's doing.
    private var rows: [TabRow] {
        let pair: (Tab, Tab)? = {
            guard model.isSplit,
                  let p = model.tab(for: .primary), let s = model.tab(for: .secondary), p !== s,
                  model.sessionTabs.contains(where: { $0 === p }),
                  model.sessionTabs.contains(where: { $0 === s }) else { return nil }
            return (p, s)
        }()
        var folded = false
        return model.sessionTabs.enumerated().compactMap { index, tab in
            guard let pair, tab === pair.0 || tab === pair.1 else { return .single(tab, index: index) }
            guard !folded else { return nil }
            folded = true
            return .split(primary: pair.0, secondary: pair.1, index: index)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Tabs")
            ForEach(rows) { row in
                switch row {
                case .single(let tab, let index):
                    SessionRow(model: model, tab: tab, dropIndex: index)
                case .split(let primary, let secondary, _):
                    SplitRow(model: model, primary: primary, secondary: secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(targeted ? appearance.accent.opacity(0.12) : .clear))
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let drag = items.first else { return false }
            model.handleDrop(drag, to: .session(nil)); return true
        } isTargeted: { targeted = $0 }
    }
}

// MARK: Rows

private struct SavedRow: View {
    @ObservedObject var model: BrowserModel
    let saved: SavedTab
    let origin: TabDrag.Origin
    let dropIndex: Int
    let folderID: UUID?
    @State private var hovering = false
    @State private var renaming = false

    private var pane: BrowserModel.Pane? { model.pane(showing: .saved(saved.id)) }

    var body: some View {
        RowBody(icon: { Favicon(png: saved.faviconPNG, name: saved.name, size: 15) },
                name: saved.name,
                selected: pane != nil, hovering: hovering,
                paneMark: model.isSplit ? pane : nil) {
            if let live = model.openTabs[saved.id] { AudioBadge(tab: live) }
        }
            .onTapGesture { model.select(.saved(saved.id)) }
            .onHover { hovering = $0 }
            .draggable(TabDrag(id: saved.id, origin: origin))
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let drag = items.first else { return false }
                model.handleDrop(drag, to: .pinned(folderID: folderID, index: dropIndex)); return true
            }
            .contextMenu {
                TabMenu(model: model, selection: .saved(saved.id), isFavorite: origin == .favorite,
                        rename: { renaming = true })
            }
            .popover(isPresented: $renaming) {
                RenamePopover(title: "Rename Tab", name: saved.name) {
                    model.setName($0, for: .saved(saved.id)); renaming = false
                }
            }
    }
}

private struct SessionRow: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: Tab
    let dropIndex: Int
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false
    @State private var renaming = false

    private var pane: BrowserModel.Pane? { model.pane(showing: .session(tab.id)) }

    var body: some View {
        RowBody(icon: { Favicon(image: tab.favicon, name: tab.displayName,
                                size: 15, loading: tab.isLoading) },
                name: tab.displayName,
                selected: pane != nil, hovering: hovering,
                paneMark: model.isSplit ? pane : nil) {
            AudioBadge(tab: tab)
            if hovering {
                Button { model.close(session: tab) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(appearance.sidebarSecondary)
                        .padding(3).background(appearance.hover, in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .onTapGesture { model.select(.session(tab.id)) }
        .onHover { hovering = $0 }
        .draggable(TabDrag(id: tab.id, origin: .session))
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let drag = items.first else { return false }
            model.handleDrop(drag, to: .session(dropIndex)); return true
        }
        .contextMenu {
            TabMenu(model: model, selection: .session(tab.id), isFavorite: false,
                    rename: { renaming = true })
        }
        .popover(isPresented: $renaming) {
            RenamePopover(title: "Rename Tab", name: tab.displayName) {
                model.setName($0, for: .session(tab.id)); renaming = false
            }
        }
    }
}

/// A row in the tab list: one tab, or the two that are sharing the window.
private enum TabRow: Identifiable {
    case single(Tab, index: Int)
    case split(primary: Tab, secondary: Tab, index: Int)

    var id: UUID {
        switch self {
        case .single(let tab, _): tab.id
        case .split(let primary, _, _): primary.id
        }
    }
}

/// Two tabs in one row, sharing it the way they share the window. The half you
/// last touched is filled — that's where the next ⌘L or ⌘W lands, and guessing
/// is how you close the wrong page.
private struct SplitRow: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var primary: Tab
    @ObservedObject var secondary: Tab
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering: BrowserModel.Pane?

    var body: some View {
        HStack(spacing: 1) {
            half(primary, pane: .primary)
            Rectangle().fill(appearance.hairline).frame(width: 1, height: 16)
            half(secondary, pane: .secondary)
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius).fill(appearance.selection))
    }

    @ViewBuilder
    private func half(_ tab: Tab, pane: BrowserModel.Pane) -> some View {
        HStack(spacing: 5) {
            Favicon(image: tab.favicon, name: tab.displayName, size: 13, loading: tab.isLoading)
            Text(tab.displayName).lineLimit(1).font(appearance.font(11))
            Spacer(minLength: 0)
            AudioBadge(tab: tab)
            if hovering == pane {
                Button { model.close(session: tab) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        .foregroundStyle(appearance.sidebarSecondary)
                        .padding(2).background(appearance.hover, in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius - 1)
            .fill(model.focusedPane == pane ? appearance.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 ? pane : nil }
        .onTapGesture { model.focusedPane = pane }
        .help(tab.displayName)
    }
}

/// A tab row: favicon, name, trailing affordances. Selection reads as one fill
/// — a tab carries no colour of its own, so there is no dot and no edge bar.
private struct RowBody<Icon: View, Trailing: View>: View {
    @ViewBuilder var icon: () -> Icon
    let name: String
    let selected: Bool
    let hovering: Bool
    /// Which half of a split this row is showing in, if any. Without it a split
    /// reads as one tab open and one tab mysteriously gone.
    var paneMark: BrowserModel.Pane? = nil
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text(name).lineLimit(1).font(appearance.font(13))
            Spacer(minLength: 4)
            if let paneMark {
                Image(systemName: paneMark == .primary ? "rectangle.lefthalf.filled"
                                                       : "rectangle.righthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(appearance.sidebarSecondary)
                    .help(paneMark == .primary ? "Showing in the left pane" : "Showing in the right pane")
            }
            trailing()
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(selected ? appearance.selection : (hovering ? appearance.hover : .clear)))
        .contentShape(Rectangle())
    }
}

/// Speaker badge on a row that is making noise (or has been silenced). Its own
/// view so it can observe the live Tab — the rows around it observe the model.
private struct AudioBadge: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        if tab.isPlayingAudio || tab.muted {
            Button { tab.toggleMute() } label: {
                Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(appearance.sidebarSecondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.muted ? "Unmute this tab" : "Mute this tab")
        }
    }
}

// MARK: Favicon

/// Decoded-favicon cache: SwiftUI re-evaluates row bodies on every hover, and
/// decoding PNG data each time is the single hottest thing the sidebar does.
@MainActor
enum FaviconCache {
    private static let cache = NSCache<NSData, NSImage>()
    static func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

struct Favicon: View {
    var png: Data? = nil
    var image: NSImage? = nil
    let name: String
    let size: CGFloat
    var loading = false

    private var nsImage: NSImage? { image ?? png.flatMap(FaviconCache.image(for:)) }

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.small).scaleEffect(0.55)
            } else if let img = nsImage {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.85))
                    .overlay(Text(String(name.first ?? "•").uppercased())
                        .font(.system(size: size * 0.6, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    @EnvironmentObject var appearance: AppearanceStore
    var body: some View {
        HStack {
            Text(title).font(appearance.font(11, weight: .semibold))
            if let trailing { Spacer(); Text(trailing).font(appearance.font(10)) }
        }
        .foregroundStyle(appearance.sidebarSecondary)
        .padding(.horizontal, 8)
    }
}

// MARK: - Escape

/// Escape, reliably. Every overlay Rune puts up — the palette, the find bar,
/// the ask bar — holds focus in a text field, and a focused field takes Escape
/// as `cancelOperation` and stops there: it quietly drops focus and nothing
/// downstream runs. So `onKeyPress(.escape)` never fires precisely when it's
/// wanted, whether it's attached to the field or to an ancestor. Watching the
/// key itself is what actually works.
private struct DismissOnEscape: ViewModifier {
    let action: () -> Void
    /// `Any?` is what NSEvent's monitor API hands back and takes.
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53 else { return event }
                    action()
                    return nil   // swallow it, so the field doesn't also cancel
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// Close this overlay on Escape. Only listens while it's on screen.
    func dismissOnEscape(perform action: @escaping () -> Void) -> some View {
        modifier(DismissOnEscape(action: action))
    }
}

// MARK: - Folder colour

/// Colour is a folder's only decoration, so it gets one small picker: a live
/// swatch plus a way back to the appearance accent.
private struct FolderColorPopover: View {
    @State private var color: Color
    @State private var hasColor: Bool
    let apply: (String?) -> Void

    init(current: Color, hasColor: Bool, apply: @escaping (String?) -> Void) {
        _color = State(initialValue: current)
        _hasColor = State(initialValue: hasColor)
        self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folder Color").font(.headline)
            HStack {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .disabled(!hasColor)
                    .onChange(of: color) { if hasColor { apply(color.hex) } }
            }
            Toggle("Use the accent color", isOn: Binding(
                get: { !hasColor },
                set: { useAccent in
                    hasColor = !useAccent
                    apply(useAccent ? nil : color.hex)
                }))
        }
        .padding(12).frame(width: 230)
    }
}

// MARK: - Rename

/// One rename popover for everything Rune lets you name — sidebar tabs,
/// folders, spaces, profiles. There is exactly one of these on purpose: the
/// second copy showed up the moment Settings needed one, which is how you end
/// up with two that drift.
struct RenamePopover: View {
    let title: String
    @State private var draft: String
    let apply: (String) -> Void

    init(title: String, name: String, apply: @escaping (String) -> Void) {
        self.title = title
        self.apply = apply
        _draft = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { apply(draft) }
            HStack {
                Spacer()
                Button("Save") { apply(draft) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

// MARK: - Context menu

private struct TabMenu: View {
    @ObservedObject var model: BrowserModel
    let selection: Selection
    let isFavorite: Bool
    var rename: (() -> Void)? = nil

    var body: some View {
        if let rename { Button("Rename…", action: rename) }
        if let url = model.url(for: selection) {
            Button("Copy Link") { model.copy(url) }
            Button("Open as Panel") {
                if let real = URL(string: url) { model.openPanel(url: real) }
            }
        }
        if let live = model.tab(for: selection), live.isPlayingAudio || live.muted {
            Button(live.muted ? "Unmute Tab" : "Mute Tab") { live.toggleMute() }
        }
        Divider()
        if case .session(let id) = selection, let tab = model.sessionTabs.first(where: { $0.id == id }) {
            Button("Pin") { model.pin(tab) }
            if model.canAddFavorite { Button("Add to Favorites") { model.addFavorite(from: tab) } }
            Divider()
            Button("Close") { model.close(session: tab) }
        }
        if case .saved(let id) = selection {
            if isFavorite {
                Button("Remove from Favorites") { model.removeFavorite(id) }
            } else {
                Menu("Move to Folder") {
                    Button("None") { model.move(id, toFolder: nil) }
                    ForEach(model.folders) { f in Button(f.name) { model.move(id, toFolder: f.id) } }
                }
                Button("Unpin") { model.unpin(id) }
            }
        }
    }
}

// MARK: - Content area

/// Every overlay that opens wanting to be typed into. Address bars subscribe
/// to drop focus when one appears — see the note on the toolbar's bar.
@MainActor private let overlayOpened = Publishers.Merge3(
    NotificationCenter.default.publisher(for: .showNewTabOverlay),
    NotificationCenter.default.publisher(for: .showCommandPalette),
    NotificationCenter.default.publisher(for: .showAskBar)
).eraseToAnyPublisher()

private struct ContentArea: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @State private var highlighted = 0
    // Memoized: recomputed once per keystroke/focus change, not on every body
    // evaluation (predict scans the whole history).
    @State private var suggestions: [Suggestion] = []
    @State private var toast: String?
    @State private var toastDismiss: Task<Void, Never>?
    @State private var showFind = false
    @State private var showDownloads = false

    private func updateSuggestions() {
        suggestions = addressFocused ? addressSuggestions(for: address, model: model) : []
    }

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model, dispatch: dispatch, address: $address, addressFocused: $addressFocused,
                    highlighted: $highlighted, suggestionCount: suggestions.count,
                    showDownloads: $showDownloads, activate: activate)
            Divider()
            HStack(spacing: 0) {
            ZStack(alignment: .top) {
                appearance.windowBG
                // There is always a first pane; splitting only adds a second.
                // Rebuilding the first one to split would hand the same live web
                // view to two containers at once, and the one on its way out
                // re-parents the page into itself and takes it down as it goes —
                // which is why closing a split used to leave an empty window
                // until you switched tabs and back.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Pane(model: model, pane: .primary)
                            .frame(width: model.isSplit
                                   ? max(0, (geo.size.width - SplitHandle.width) * model.splitRatio)
                                   : geo.size.width)
                        if model.isSplit {
                            SplitHandle(model: model, total: geo.size.width)
                            Pane(model: model, pane: .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if showFind {
                    FindBar(model: model, isPresented: $showFind)
                        .padding(.top, 8).padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showDownloads {
                    DownloadsPanel(downloads: model.downloads, showing: $showDownloads)
                        .dismissOnEscape { showDownloads = false }
                        .padding(.top, 8).padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let candidates = model.collectCandidates {
                    CollectSheet(model: model, candidates: candidates)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !suggestions.isEmpty, !model.isSplit {
                    SuggestionList(model: model, suggestions: suggestions, highlighted: highlighted) { index in
                        highlighted = index; activate()
                    }
                    .padding(.horizontal, 44).padding(.top, 4)
                }
                if let toast {
                    Text(toast)
                        .font(appearance.font(12, weight: .medium))
                        .foregroundStyle(appearance.chromeText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(appearance.hairline))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Beside the content, never over it: a panel is a column, and the
            // page keeps whatever room is left.
            if let panel = model.panel {
                Divider()
                WebContainer(webView: panel.webView).id(panel.id)
                    .frame(width: 340)
            }
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
        .animation(.easeOut(duration: 0.15), value: showFind)
        .animation(.easeOut(duration: 0.15), value: showDownloads)
        // Both panels hang off the same corner, so only one is ever up — and
        // opening the list is what counts as having seen it, however you opened
        // it (the toolbar button or ⌥⌘L).
        .onChange(of: showDownloads) {
            guard showDownloads else { return }
            showFind = false
            model.downloads.hasUnseen = false
        }
        .onChange(of: showFind) { if showFind { showDownloads = false } }
        .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) {
            if $0.aimed(at: model) { showFind = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloads)) {
            if $0.aimed(at: model) { showDownloads.toggle() }
        }
        .onChange(of: model.selection) { sync() }
        // Live URL updates from the active tab: ContentArea doesn't observe the
        // Tab object, so navigations that never touch the toolbar (start-page
        // search, link clicks) must push the new URL in via its publisher.
        .onReceive(activeURLPublisher) { if !addressFocused, address != $0 { address = $0 } }
        .onChange(of: address) { updateSuggestions() }
        .onChange(of: addressFocused) { updateSuggestions() }
        .onAppear { sync() }
        // In a split, ⌘L belongs to the pane you're in — its bar handles it.
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) {
            if $0.aimed(at: model), !model.isSplit { addressFocused = true }
        }
        // ⌘T/⌘K/⌘E over a focused bar: the overlay asks for the keyboard, but
        // an NSTextField that already holds first responder doesn't yield to a
        // FocusState request — so the bar keeps every keystroke, selection and
        // suggestions up, behind the overlay. It has to let go first.
        .onReceive(overlayOpened) { if $0.aimed(at: model) { addressFocused = false } }
        .onReceive(NotificationCenter.default.publisher(for: .finderToast)) { note in
            toast = note.object as? String
            toastDismiss?.cancel()
            toastDismiss = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled { toast = nil }
            }
        }
    }

    private func sync() { address = model.activeTab?.urlString ?? "" }

    private var activeURLPublisher: AnyPublisher<String, Never> {
        model.activeTab?.$urlString.eraseToAnyPublisher() ?? Just("").eraseToAnyPublisher()
    }

    private func activate() {
        activateAddress(address, suggestions: suggestions, highlighted: highlighted, model: model)
        addressFocused = false
        highlighted = 0
    }
}

/// The address field itself. There is one of these because there is one of
/// it: the toolbar wears it when a window shows a single page, and each pane
/// wears its own in a split. Two copies would drift the day one gained a
/// feature.
struct AddressField: View {
    @Binding var address: String
    var focused: FocusState<Bool>.Binding
    @Binding var highlighted: Int
    let suggestionCount: Int
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    /// Host-only display ("pinkbike.com") while the field isn't focused.
    private var compactHost: String {
        guard let host = URL(string: address)?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    private var showCompact: Bool {
        appearance.appearance.compactAddressBar && !focused.wrappedValue && !address.isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            ZStack(alignment: .leading) {
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .foregroundStyle(appearance.chromeText)
                    .focused(focused)
                    .onSubmit(activate)
                    .onChange(of: address) { highlighted = 0 }
                    .onKeyPress(.downArrow) {
                        guard suggestionCount > 0 else { return .ignored }
                        highlighted = (highlighted + 1) % suggestionCount; return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard suggestionCount > 0 else { return .ignored }
                        highlighted = (highlighted - 1 + suggestionCount) % suggestionCount; return .handled
                    }
                    .onKeyPress(.escape) { focused.wrappedValue = false; return .handled }
                    .opacity(showCompact ? 0 : 1)
                if showCompact {
                    Text(compactHost).lineLimit(1)
                        .foregroundStyle(appearance.chromeText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(appearance.windowBG)   // hide the field underneath
                        .contentShape(Rectangle())
                        .onTapGesture { focused.wrappedValue = true }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(appearance.windowBG, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .strokeBorder(focused.wrappedValue ? appearance.accent : appearance.hairline, lineWidth: 1))
    }
}

/// What to offer for what's been typed. Shared by every address bar there is,
/// because they must all offer the same things.
@MainActor
func addressSuggestions(for address: String, model: BrowserModel) -> [Suggestion] {
    guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let predictions = model.history.predict(address)
    var out: [Suggestion]
    // If you've clearly started typing a host you visit, that's the answer —
    // lead with it so Return just goes there.
    if let top = predictions.first, model.history.isConfident(address, top) {
        out = [.history(top), .navigate(address)] + predictions.dropFirst().map(Suggestion.history)
    } else {
        out = [.navigate(address)] + predictions.map(Suggestion.history)
    }
    // Sounds like a description, not a destination — offer Claude.
    if model.ai.isAvailable, address.split(separator: " ").count >= 3 { out.append(.askAI(address)) }
    return out
}

/// Act on what's typed, likewise shared.
@MainActor
func activateAddress(_ address: String, suggestions: [Suggestion], highlighted: Int, model: BrowserModel) {
    guard !suggestions.isEmpty else { model.navigate(address); return }
    switch suggestions[min(highlighted, suggestions.count - 1)] {
    case .navigate(let q): model.navigate(q)
    case .history(let e): model.navigate(e.url)
    case .askAI(let q):
        Task {
            if let url = try? await model.findInHistory(q) { model.navigate(url.absoluteString) }
            else { model.navigate(q) }   // nothing matched — fall back to a search
        }
    }
}

enum Suggestion: Identifiable {
    case navigate(String)
    case history(HistoryEntry)
    case askAI(String)
    var id: String {
        switch self {
        case .navigate(let q): "go:\(q)"
        case .history(let e): "h:\(e.url)"
        case .askAI(let q): "ai:\(q)"
        }
    }
}

private struct SuggestionList: View {
    @ObservedObject var model: BrowserModel
    let suggestions: [Suggestion]
    let highlighted: Int
    let pick: (Int) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                let on = index == highlighted
                HStack(spacing: 9) {
                    Image(systemName: icon(item)).frame(width: 16)
                        .foregroundStyle(on ? .white : appearance.secondaryText(on: appearance.chrome))
                    Text(title(item)).lineLimit(1)
                        .foregroundStyle(on ? .white : appearance.chromeText)
                    Spacer()
                    if case .history(let e) = item {
                        Text(e.url).font(appearance.font(11)).lineLimit(1)
                            .foregroundStyle(on ? .white.opacity(0.8) : appearance.secondaryText(on: appearance.chrome))
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? appearance.accent : .clear))
                .contentShape(Rectangle())
                .onTapGesture { pick(index) }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appearance.cornerRadius + 2))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius + 2).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func icon(_ s: Suggestion) -> String {
        switch s {
        case .navigate(let q): return model.resolve(q).map { _ in q.contains(".") ? "arrow.up.forward" : "magnifyingglass" } ?? "magnifyingglass"
        case .history: return "clock"
        case .askAI: return "sparkles"
        }
    }
    private func title(_ s: Suggestion) -> String {
        switch s {
        case .navigate(let q):
            if q.contains(".") && !q.contains(" ") { return "Go to \(q)" }
            return "Search \(model.settings.searchEngine.name) for “\(q)”"
        case .history(let e): return e.title.isEmpty ? e.url : e.title
        case .askAI: return "Find this in your history"
        }
    }
}

/// The grab strip between two panes. A split fixed at half and half is a
/// guess about what you're doing; this is how you tell it otherwise. The
/// hairline still reads as a 1pt divider — the rest is invisible room to grab,
/// because a 1pt drag target is a dare, not a control.
private struct SplitHandle: View {
    @ObservedObject var model: BrowserModel
    let total: Double
    @EnvironmentObject var appearance: AppearanceStore
    @State private var startRatio: Double?

    static let width: Double = 14

    var body: some View {
        ZStack {
            Rectangle().fill(appearance.windowBG)
            // A grip you can actually see, so the gutter reads as a control
            // rather than a gap the two pages happen to leave.
            RoundedRectangle(cornerRadius: 1.5).fill(appearance.hairline)
                .frame(width: 3, height: 26)
        }
            .frame(width: Self.width)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
            .gesture(
                // Global, not local: the handle moves as you drag it, so in its
                // own coordinate space the origin runs away underneath the
                // gesture and the drag measures itself short.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        guard total > 0 else { return }
                        let base = startRatio ?? model.splitRatio
                        if startRatio == nil { startRatio = base }
                        // Clamped: a pane you can't see is a pane you can't get back.
                        model.splitRatio = min(max(base + value.translation.width / total, 0.15), 0.85)
                    }
                    .onEnded { _ in startRatio = nil }
            )
    }
}

/// One side of a Split View. Marked only when it isn't the focused one — a
/// border around the pane you're already using is noise, but knowing where the
/// next ⌘L or ⌘W will land is not.
private struct Pane: View {
    @ObservedObject var model: BrowserModel
    let pane: BrowserModel.Pane
    @EnvironmentObject var appearance: AppearanceStore

    // This pane's own address bar, and everything behind it. Two panes, two of
    // these, both live at once — an address bar that rewrites itself when you
    // glance at the other half is a bar for the window, not for the page.
    @State private var address = ""
    @FocusState private var focused: Bool
    @State private var highlighted = 0
    @State private var suggestions: [Suggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            // Only in a split. On its own, a pane is the window, and the window
            // already has an address bar up top.
            if model.isSplit {
                AddressField(address: $address, focused: $focused, highlighted: $highlighted,
                             suggestionCount: suggestions.count, activate: activate)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(appearance.chrome)
                Divider()
            }
            ZStack(alignment: .top) {
                Group {
                    if let tab = model.tab(for: pane) {
                        TabContent(tab: tab, model: model, onClick: { focus() })
                    } else {
                        StartPage(model: model)
                    }
                }
                // Inside the pane's stack, so it lands over this page and not
                // over the neighbour's.
                if !suggestions.isEmpty {
                    SuggestionList(model: model, suggestions: suggestions, highlighted: highlighted) { index in
                        highlighted = index; activate()
                    }
                    .padding(.horizontal, 12).padding(.top, 4)
                }
            }
        }
        .overlay {
            if model.focusedPane != pane {
                Rectangle().fill(.black.opacity(0.06)).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus() }
        .onChange(of: model.selection(for: pane)) { sync() }
        // The tab pushes URL changes that never touched this bar — link clicks,
        // start-page searches, redirects.
        .onReceive(urlPublisher) { if !focused, address != $0 { address = $0 } }
        .onChange(of: address) { updateSuggestions() }
        .onChange(of: focused) { if focused { focus() }; updateSuggestions() }
        .onAppear { sync() }
        // ⌘L aims at the window; only the pane you're in should answer.
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) {
            if $0.aimed(at: model), model.isSplit, model.focusedPane == pane { focused = true }
        }
        // Same as the toolbar bar: an opening overlay takes the keyboard.
        .onReceive(overlayOpened) { if $0.aimed(at: model) { focused = false } }
    }

    /// Typing in a pane's bar is a way of being in that pane, so commands and
    /// `navigate` — which both aim at the focused pane — land where you're looking.
    private func focus() { model.focusedPane = pane }

    private func sync() { address = model.tab(for: pane)?.urlString ?? "" }

    private var urlPublisher: AnyPublisher<String, Never> {
        model.tab(for: pane)?.$urlString.eraseToAnyPublisher() ?? Just("").eraseToAnyPublisher()
    }

    private func updateSuggestions() {
        suggestions = focused ? addressSuggestions(for: address, model: model) : []
    }

    private func activate() {
        focus()
        activateAddress(address, suggestions: suggestions, highlighted: highlighted, model: model)
        focused = false
        highlighted = 0
    }
}

private struct TabContent: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: BrowserModel
    var onClick: (() -> Void)?
    var body: some View {
        if tab.urlString.isEmpty && !tab.isLoading {
            StartPage(model: model)
        } else if let article = tab.reader {
            // The web view isn't gone, just not on screen — it keeps running,
            // and closing the reader puts it straight back.
            ReaderView(article: article)
        } else {
            WebContainer(webView: tab.webView, onClick: onClick).id(tab.id)
                // Claude, anchored to the page: hover a link for a summary,
                // select text for actions.
                // Bottom corner, not at the cursor. A page draws its own hover
                // popups right next to its links — Wikipedia's previews, every
                // tooltip — so anchoring here means two boxes over each other.
                // The corner is where a browser has always put what it wants to
                // tell you about a link, and nothing of the page's is there.
                .overlay(alignment: .bottomLeading) {
                    if let hover = tab.hoveredLink {
                        LinkSummaryPopover(target: hover, ai: model.ai)
                            .padding(12)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                // Clamped to the pane it's actually in. This used to stop at a
                // hardcoded 860, which is a bet that the view is a whole window
                // — in half of one it walked straight off the edge.
                .overlay(alignment: .topLeading) {
                    if let selection = tab.selection {
                        GeometryReader { geo in
                            SelectionActions(target: selection, ai: model.ai)
                                .offset(x: min(max(8, selection.x), max(8, geo.size.width - 368)),
                                        y: selection.y + 8)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: tab.hoveredLink)
                .animation(.easeOut(duration: 0.12), value: tab.selection)
        }
    }
}

private struct StartPage: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var query = ""
    @FocusState private var focused: Bool

    private var a: Appearance { appearance.appearance }
    private var greeting: String { a.startPageGreeting.isEmpty ? "Rune" : a.startPageGreeting }
    // Memoized on appear: a full history sort per keystroke in the search
    // field is work the page can't even show.
    @State private var recents: [HistoryEntry] = []

    private func refreshRecents() {
        guard a.startPageShowRecents else { return }
        recents = Array(model.history.entries
            .sorted { $0.lastVisited > $1.lastVisited }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(greeting).font(appearance.font(40, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.4)
                .foregroundStyle(appearance.text(on: appearance.startPageBG).opacity(0.85))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                TextField("Search \(model.settings.searchEngine.name) or enter address", text: $query)
                    .textFieldStyle(.plain).font(appearance.font(17)).focused($focused)
                    .foregroundStyle(appearance.chromeText)
                    .onSubmit { model.navigate(query); query = "" }
            }
            .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: 560)
            .background(appearance.chrome, in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? appearance.accent : appearance.hairline, lineWidth: 1))

            if a.startPageShowFavorites && !model.favorites.isEmpty {
                // One centred row for as long as one fits, and a wrapping grid
                // when it doesn't. Neither works alone: an HStack can't wrap, it
                // just runs off the side; a grid fills its frame, so a row of
                // six in seven columns' worth of space sits visibly off-centre.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        ForEach(model.favorites) { fav in
                            StartPageTile(saved: fav) { model.select(.saved(fav.id)) }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 84), spacing: 14)],
                              spacing: 12) {
                        ForEach(model.favorites) { fav in
                            StartPageTile(saved: fav) { model.select(.saved(fav.id)) }
                        }
                    }
                }
                .frame(maxWidth: 560)
                .padding(.top, 8)
            }
            if a.startPageShowRecents && !recents.isEmpty {
                VStack(spacing: 2) {
                    ForEach(recents) { entry in
                        Button { model.navigate(entry.url) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock").font(.system(size: 11))
                                    .foregroundStyle(appearance.secondaryText(on: appearance.startPageBG))
                                Text(entry.title.isEmpty ? entry.url : entry.title).lineLimit(1)
                                    .foregroundStyle(appearance.text(on: appearance.startPageBG).opacity(0.8))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.top, 4)
            }
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.startPageBG)
        .onAppear { focused = true; refreshRecents() }
        // ⌘T landing on a start page that's already open: same freshness as a
        // new one.
        .onReceive(NotificationCenter.default.publisher(for: .focusStartPage)) {
            if $0.aimed(at: model) { focused = true; refreshRecents() }
        }
    }
}

/// A favorite on the start page: favicon tile + name, like the sidebar tiles
/// but larger and labeled.
private struct StartPageTile: View {
    let saved: SavedTab
    let open: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                Group {
                    if let png = saved.faviconPNG, let image = FaviconCache.image(for: png) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "globe").font(.system(size: 18))
                            .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                    }
                }
                .frame(width: 52, height: 52)
                .background(appearance.chrome, in: RoundedRectangle(cornerRadius: appearance.cornerRadius + 2))
                .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius + 2)
                    .strokeBorder(appearance.hairline))
                Text(saved.name).font(appearance.font(11)).lineLimit(1)
                    .foregroundStyle(appearance.secondaryText(on: appearance.startPageBG))
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Toolbar: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @Binding var address: String
    var addressFocused: FocusState<Bool>.Binding
    @Binding var highlighted: Int
    let suggestionCount: Int
    @Binding var showDownloads: Bool
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    /// Buttons come from the appearance's list of command rawValues, so the
    /// toolbar is fully user-composable (and round-trips through presets).
    private var commands: [Command] {
        appearance.appearance.toolbarButtons.compactMap(Command.init(rawValue:))
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(commands) { commandButton($0) }

            if !model.isSplit {
                AddressField(address: $address, focused: addressFocused, highlighted: $highlighted,
                             suggestionCount: suggestionCount, activate: activate)
            } else {
                // In a split the bars live in the panes, one each. A third one up
                // here would have to pick a pane to speak for, which is the whole
                // thing we just stopped doing.
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(appearance.chrome)
        .foregroundStyle(appearance.chromeText)
    }

    /// Any command renders as a toolbar button; a few keep live state (disabled
    /// arrows, reload-becomes-stop, download progress).
    @ViewBuilder
    private func commandButton(_ command: Command) -> some View {
        switch command {
        case .showDownloads:
            DownloadsButton(downloads: model.downloads, showing: $showDownloads)
        case .goBack:
            button(command.icon) { dispatch(command) }
                .disabled(!(model.activeTab?.canGoBack ?? false)).help(command.title)
        case .goForward:
            button(command.icon) { dispatch(command) }
                .disabled(!(model.activeTab?.canGoForward ?? false)).help(command.title)
        case .reload:
            button(model.activeTab?.isLoading == true ? "xmark" : command.icon) { dispatch(command) }
                .help(command.title)
        default:
            button(command.icon) { dispatch(command) }.help(command.title)
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
    }
}
