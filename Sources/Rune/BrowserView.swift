import Combine
import Security
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
                if model.sidebarVisible && !model.zenActive && !appearance.appearance.sidebarOnRight { sidebar; Divider() }
                ContentArea(model: model, dispatch: dispatch)
                if model.sidebarVisible && !model.zenActive && appearance.appearance.sidebarOnRight { Divider(); sidebar }
            }
            .animation(.easeInOut(duration: 0.18), value: model.sidebarVisible)
            .animation(Motion.arrive, value: model.zenActive)
            .background(appearance.windowBG.opacity(appearance.containerOpacity))
            // Fading the frost reveals the sharp glass beneath it — that's
            // the whole blur dial.
            .background(WindowBlur().opacity(appearance.appearance.blur / 100))
            // Zen: the sidebar steps out of the layout and waits at the window's
            // edge, sliding back in over the page when the pointer finds it.
            .overlay(alignment: appearance.appearance.sidebarOnRight ? .trailing : .leading) {
                if model.zenActive {
                    ZenSidebarReveal(onRight: appearance.appearance.sidebarOnRight) {
                        Sidebar(model: model, dispatch: dispatch)
                    }
                }
            }

            if showAsk {
                AskBar(model: model, ai: model.ai, isPresented: $showAsk)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showPalette {
                CommandPalette(model: model, dispatch: dispatch,
                               isPresented: $showPalette, mode: paletteMode)
            }
        }
        .animation(Motion.arrive, value: showPalette)
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
        // The titlebar is gone (TitlebarRemover), but the window still
        // advertises its old inset as safe area. Nothing is there — lay out
        // from the true top edge.
        .ignoresSafeArea(edges: .top)
    }

    private var sidebar: some View {
        Sidebar(model: model, dispatch: dispatch)
            .frame(width: appearance.sidebarWidth)
            .overlay(alignment: appearance.appearance.sidebarOnRight ? .leading : .trailing) {
                SidebarResizeHandle()
            }
            .transition(.move(edge: .leading))
    }
}

/// The sidebar's width is a drag, not a slider: grab its inner edge. The
/// setting persists exactly as before — this is just the honest control for it.
private struct SidebarResizeHandle: View {
    @EnvironmentObject var appearance: AppearanceStore
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle().fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? appearance.sidebarWidth
                        if startWidth == nil { startWidth = base }
                        let delta = appearance.appearance.sidebarOnRight
                            ? -value.translation.width : value.translation.width
                        // Clamped: a sidebar you can't find again is a bug,
                        // not a preference.
                        appearance.appearance.sidebarWidth = min(max(base + delta, 180), 420)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's top-left verbs: Rune's own lights, and the sidebar
            // toggle beside them — always present, because it's also the way
            // back once the sidebar is gone.
            HStack(spacing: 8) {
                if !appearance.appearance.hideTrafficLights { TrafficLights() }
                CommandButton(model: model, command: .toggleSidebar, dispatch: dispatch)
            }
            .padding(.leading, appearance.appearance.hideTrafficLights ? 6 : 12)
            .padding(.top, 8).padding(.bottom, 4)

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
        .background {
            ZStack {
                WindowDragArea()
                appearance.sidebarBG.opacity(appearance.containerOpacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(Grain(percent: appearance.appearance.grain))
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
            // A fixed row, not a flexible grid: the tiles and their gaps stay
            // the same size at every sidebar width, and a sidebar too narrow
            // for them truncates the row rather than squeezing it.
            HStack(spacing: 6) {
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
                    Text("Drag here").font(appearance.type(.caption))
                        .foregroundStyle(appearance.sidebarSecondary)
                        .frame(height: 34)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
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

    /// A legibility chip that reads off the sidebar it sits on: light enough
    /// to lift a dark favicon on a dark sidebar, a hair darker than a light
    /// one. Without it a black favicon on a dark sidebar simply vanished.
    private var plate: Color {
        if selected { return appearance.selection }
        return appearance.sidebarBG.prefersLightText
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        Favicon(png: saved.faviconPNG, name: saved.name, size: 20)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius).fill(plate))
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
    @State private var customizing = false

    /// A folder is the one thing in the sidebar that carries a colour; without
    /// one it simply wears the appearance accent.
    private var tint: Color { folder.colorHex.flatMap(Color.init(hex:)) ?? appearance.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9)).foregroundStyle(appearance.sidebarSecondary).frame(width: 10)
                FolderGlyph(icon: folder.icon, tint: tint, size: 12)
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
                Button("Customize Folder…") { customizing = true }
                Divider()
                Button("Delete Folder", role: .destructive) { model.deleteFolder(folder.id) }
            }
            .popover(isPresented: $customizing) {
                CustomizeFolderPopover(model: model, folderID: folder.id)
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
            Text(name).lineLimit(1).font(appearance.type(.body))
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
        // Micro-labels, fieldframes-style: tiny, tracked wide, all caps, with
        // the count sitting quietly at the trailing edge. The hierarchy is the
        // whitespace around them, not their weight.
        HStack {
            Text(title.uppercased()).font(appearance.type(.caption)).tracking(1.3)
            if let trailing { Spacer(); Text(trailing).font(appearance.type(.caption)).monospacedDigit() }
        }
        .foregroundStyle(appearance.sidebarSecondary.opacity(0.85))
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

// MARK: - Folder customization

/// The sidebar's folder mark, Finder-style: a folder shape wearing the
/// folder's colour, with the chosen symbol set into it. A folder that has
/// picked a folder symbol is just a folder — no badge inside a badge.
struct FolderGlyph: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 12
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        ZStack {
            Image(systemName: "folder.fill").font(.system(size: size)).foregroundStyle(tint)
            if !icon.hasPrefix("folder") {
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(appearance.text(on: tint).opacity(0.85))
                    // The folder's body sits below its tab; the badge sits in
                    // the body.
                    .offset(y: size * 0.1)
            }
        }
        .frame(width: size + 2)
    }
}

/// Rename, colour, and icon in one sheet of glass — a folder's whole
/// wardrobe behind a single "Customize Folder" instead of three menu trips.
/// Everything applies live; the popover is the preview.
private struct CustomizeFolderPopover: View {
    @ObservedObject var model: BrowserModel
    let folderID: UUID
    @State private var name: String
    @State private var color: Color
    @State private var hasColor: Bool
    @EnvironmentObject var appearance: AppearanceStore

    @MainActor
    init(model: BrowserModel, folderID: UUID) {
        self.model = model
        self.folderID = folderID
        let folder = model.folders.first { $0.id == folderID }
        _name = State(initialValue: folder?.name ?? "")
        _hasColor = State(initialValue: folder?.colorHex != nil)
        _color = State(initialValue: folder?.colorHex.flatMap(Color.init(hex:)) ?? .accentColor)
    }

    private var folder: Folder? { model.folders.first { $0.id == folderID } }
    private var tint: Color { folder?.colorHex.flatMap(Color.init(hex:)) ?? appearance.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FolderGlyph(icon: folder?.icon ?? "folder.fill", tint: tint, size: 16)
                Text("Customize Folder").font(.headline)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { model.renameFolder(folderID, to: name) }
            HStack {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .disabled(!hasColor)
                    .onChange(of: color) { if hasColor { model.setFolderColor(folderID, color.hex) } }
                Spacer()
                Toggle("Accent", isOn: Binding(
                    get: { !hasColor },
                    set: { useAccent in
                        hasColor = !useAccent
                        model.setFolderColor(folderID, useAccent ? nil : color.hex)
                    }))
                .toggleStyle(.checkbox)
            }
            Divider()
            SymbolPicker(symbol: .constant(folder?.icon ?? "folder.fill"), tint: tint) { icon in
                model.setFolderIcon(folderID, icon)
            }
        }
        .padding(12)
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
    /// Wiggle mode: the strip and corner kit take edits instead of clicks.
    @State private var controlEdit = false
    /// The active page's color, mirrored here so the suggestion dropdown can
    /// wear the same surface the strip does.
    @State private var tint: NSColor?

    private func updateSuggestions() {
        suggestions = addressFocused ? addressSuggestions(for: address, model: model) : []
    }

    /// The structural fork: the minimal strip carries only navigation and a
    /// quiet address pill on a thin band above the page; attached keeps the
    /// classic full-button bar.
    private var floatingChrome: Bool { appearance.appearance.chromeStyle == "floating" }

    var body: some View {
        VStack(spacing: 0) {
            // In a floating split the strip stands down — each pane carries
            // its own chrome, Arc-style, and a third bar would speak for
            // nobody. In zen the strip leaves the layout entirely; the overlay
            // below reveals it on a top-edge hover.
            if model.zenActive {
                // Subtle zen keeps a slim band in the layout: it pushes the page
                // down and wears the site's own top colour, so it reads as the
                // page carried up rather than a bar laid over it. Full zen keeps
                // nothing here — its strip is purely the top-edge reveal.
                if appearance.appearance.zenStyle == "subtle" {
                    ZenSubtleBand(hint: zenHint, tint: tint)
                }
            } else if floatingChrome && !model.isSplit {
                MinimalChrome(model: model, dispatch: dispatch, address: $address,
                              addressFocused: $addressFocused, highlighted: $highlighted,
                              suggestionCount: suggestions.count, editing: $controlEdit,
                              activate: activate)
                Divider()
            } else if !floatingChrome {
                Toolbar(model: model, dispatch: dispatch, address: $address, addressFocused: $addressFocused,
                        highlighted: $highlighted, suggestionCount: suggestions.count,
                        activate: activate)
                Divider()
            }
            HStack(spacing: 0) {
            ZStack(alignment: .top) {
                appearance.windowBG.opacity(appearance.containerOpacity)
                // There is always a first pane; splitting only adds a second.
                // Rebuilding the first one to split would hand the same live web
                // view to two containers at once, and the one on its way out
                // re-parents the page into itself and takes it down as it goes —
                // which is why closing a split used to leave an empty window
                // until you switched tabs and back.
                GeometryReader { geo in
                    // The card margins come out of the width the panes share —
                    // otherwise the layout overflows and the window scrolls
                    // sideways.
                    let inset: CGFloat = floatingChrome && model.isSplit ? 16 : 0
                    HStack(spacing: 0) {
                        Pane(model: model, pane: .primary)
                            .frame(width: model.isSplit
                                   ? max(0, (geo.size.width - SplitHandle.width - inset) * model.splitRatio)
                                   : geo.size.width)
                        if model.isSplit {
                            SplitHandle(model: model, total: geo.size.width)
                            Pane(model: model, pane: .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // The cards float on the window background with a margin
                    // all round; the handle is the gap between them.
                    .padding(floatingChrome && model.isSplit ? 8 : 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if showFind {
                    FindBar(model: model, isPresented: $showFind)
                        .padding(.top, 8).padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let candidates = model.collectCandidates {
                    CollectSheet(model: model, candidates: candidates)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // The dropdown is the bar grown taller: full width, wearing
                // the strip's surface, seam to seam with the chrome above.
                if !suggestions.isEmpty, !model.isSplit {
                    SuggestionList(model: model, suggestions: suggestions, highlighted: highlighted,
                                   surface: floatingChrome ? tint.map(Color.init(nsColor:)) : nil) { index in
                        highlighted = index; activate()
                    }
                    // In zen the chrome floats over the page, so the dropdown
                    // has to start below the revealed strip, not behind it. Full
                    // zen bleeds to the top edge; subtle zen already sits below
                    // its in-flow band, so it needs only the strip's overhang.
                    .padding(.top, model.zenActive ? (appearance.appearance.zenStyle == "subtle" ? 12 : 38) : 0)
                }
                if let toast {
                    Text(toast)
                        .font(appearance.type(.label))
                        .foregroundStyle(appearance.chromeText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .runeSurface(appearance, .pill)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if floatingChrome {
                    CornerToolbar(model: model, downloads: model.downloads,
                                  dispatch: dispatch, editing: $controlEdit)
                        .padding(.trailing, 12).padding(.bottom, 12)
                }
            }
            // The quiet corner opposite: download progress while bytes land.
            .overlay(alignment: .bottomLeading) {
                DownloadCorner(downloads: model.downloads)
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
        // Zen: the strip waits just above the page. In "full" it's an invisible
        // lip you brush; in "subtle" it's a quiet band that names the page and
        // blooms to the whole strip on hover (or whenever the address is being
        // typed into).
        .overlay(alignment: .top) {
            if model.zenActive {
                ZenChromeReveal(collapsedHeight: appearance.appearance.zenStyle == "subtle" ? 26 : 8,
                                keepOpen: addressFocused) {
                    MinimalChrome(model: model, dispatch: dispatch, address: $address,
                                  addressFocused: $addressFocused, highlighted: $highlighted,
                                  suggestionCount: suggestions.count, editing: $controlEdit,
                                  activate: activate)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
        .animation(.easeOut(duration: 0.15), value: showFind)
        .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) {
            if $0.aimed(at: model) { showFind = true }
        }
        // Wiggle mode, from the command or the palette.
        .onReceive(NotificationCenter.default.publisher(for: .toggleControlEdit)) {
            if $0.aimed(at: model) { withAnimation(Motion.arrive) { controlEdit.toggle() } }
        }
        // While the shelves take drags, the window doesn't: the strip sits in
        // the titlebar region, whose frame-level dragging outranks a SwiftUI
        // drag source and was carrying the whole window along with the button.
        .onChange(of: controlEdit) { NSApp.keyWindow?.isMovable = !controlEdit }
        .onChange(of: model.selection) { sync(); tint = model.activeTab?.themeColor }
        .onReceive(activeThemePublisher) { tint = $0 }
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

    /// The quiet label the subtle zen band wears: the current host, or the
    /// wordmark on an empty page.
    private var zenHint: String {
        guard let host = URL(string: address)?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var activeURLPublisher: AnyPublisher<String, Never> {
        model.activeTab?.$urlString.eraseToAnyPublisher() ?? Just("").eraseToAnyPublisher()
    }

    private var activeThemePublisher: AnyPublisher<NSColor?, Never> {
        model.activeTab?.$themeColor.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()
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
    /// `.bar` draws its own box (the attached toolbar, a split pane's bar);
    /// `.pill` is naked — the floating chrome's surface dresses it.
    var style: Style = .bar
    /// What the field sits on (the strip's page tint); ink keeps contrast.
    var surface: Color? = nil
    /// The active tab's trust, fetched when the padlock is clicked — a
    /// closure so this dumb view never has to observe a tab.
    var trust: () -> SecTrust? = { nil }
    @EnvironmentObject var appearance: AppearanceStore
    @State private var showingSecurity = false

    enum Style { case bar, pill }

    private var base: Color { surface ?? appearance.chrome }

    /// Host-only display ("pinkbike.com") while the field isn't focused.
    private var compactHost: String {
        guard let host = URL(string: address)?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    private var showCompact: Bool {
        appearance.appearance.compactAddressBar && !focused.wrappedValue && !address.isEmpty
    }

    /// Where the address sits in its field — a setting, like everything.
    private var textAlignment: TextAlignment {
        switch appearance.appearance.addressAlignment {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }
    private var frameAlignment: Alignment {
        switch appearance.appearance.addressAlignment {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    /// The padlock: what the connection is, said quietly. Only meaningful when
    /// an address is loaded and the field is at rest.
    private var leadingSymbol: String {
        guard !address.isEmpty, !focused.wrappedValue else { return "magnifyingglass" }
        if address.hasPrefix("https://") { return "lock.fill" }
        if address.hasPrefix("http://") { return "lock.open" }
        return "magnifyingglass"
    }

    var body: some View {
        HStack(spacing: 6) {
            // The padlock answers questions when there's a connection to ask
            // about; otherwise it's just the glyph.
            if !address.isEmpty, !focused.wrappedValue, address.hasPrefix("http") {
                Button { showingSecurity = true } label: {
                    Image(systemName: leadingSymbol).font(.system(size: 11))
                        .foregroundStyle(appearance.secondaryText(on: base))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Connection details")
                .popover(isPresented: $showingSecurity, arrowEdge: .bottom) {
                    SecurityPopover(host: compactHost,
                                    secure: address.hasPrefix("https://"), trust: trust())
                }
            } else {
                Image(systemName: leadingSymbol).font(.system(size: 11))
                    .foregroundStyle(appearance.secondaryText(on: base))
            }
            ZStack(alignment: .leading) {
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(textAlignment)
                    .foregroundStyle(appearance.text(on: base))
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
                    // A Button, not a tapped Text: the strip lives in the
                    // window's titlebar region, where passive views belong to
                    // window-dragging and only real controls get the click.
                    Button { focused.wrappedValue = true } label: {
                        Text(compactHost).lineLimit(1)
                            .font(style == .pill ? appearance.type(.label) : appearance.type(.body))
                            .tracking(style == .pill ? 0.6 : 0)
                            // Primary ink on the tint — the host is the one
                            // legible statement on the strip, Arc-style.
                            .foregroundStyle(appearance.text(on: base))
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                            .background(style == .pill ? Color.clear : appearance.windowBG)   // hide the field underneath
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, style == .pill ? 14 : 10).padding(.vertical, style == .pill ? 8 : 6)
        // No stroke, focused or not — focus shows as the caret and the
        // suggestions; a ring around the field was one box too many.
        .background(style == .pill ? Color.clear : appearance.windowBG,
                    in: RoundedRectangle(cornerRadius: appearance.radius(style == .pill ? .pill : .medium)))
        // A click that lands on the page takes the keyboard with it — the
        // field lets go instead of keeping a dead caret.
        .onReceive(NotificationCenter.default.publisher(for: .pageClicked)) { _ in
            focused.wrappedValue = false
        }
    }
}

/// The padlock, opened: what this connection is, in words — and the
/// certificate chain macOS accepted for it. Read-only on purpose; Rune
/// reports the system's verdict and never overrides it.
struct SecurityPopover: View {
    let host: String
    let secure: Bool
    let trust: SecTrust?
    @EnvironmentObject var appearance: AppearanceStore

    private var chain: [String] {
        guard let trust,
              let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return [] }
        return certs.compactMap { SecCertificateCopySubjectSummary($0) as String? }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: secure ? "lock.fill" : "lock.open")
                    .foregroundStyle(secure ? appearance.accent : .orange)
                Text(host).font(appearance.type(.title)).lineLimit(1)
            }
            if secure {
                Text("Encrypted connection. macOS validated the certificate against the system trust store.")
                    .font(appearance.type(.body)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !chain.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CERTIFICATE CHAIN").font(appearance.type(.caption)).tracking(1.2)
                            .foregroundStyle(.secondary)
                        ForEach(Array(chain.enumerated()), id: \.offset) { i, name in
                            HStack(spacing: 5) {
                                Image(systemName: i == 0 ? "checkmark.seal.fill" : "seal")
                                    .font(.system(size: 9))
                                    .foregroundStyle(i == 0 ? appearance.accent : .secondary)
                                Text(name).font(appearance.type(.label)).lineLimit(1)
                            }
                            .padding(.leading, CGFloat(i) * 12)
                        }
                    }
                }
            } else {
                Text("Not encrypted. Anything sent to this site can be read or changed in transit.")
                    .font(appearance.type(.body)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

/// TLS refused the connection; this is the refusal, readable. The only exit
/// is back — there is no "proceed anyway", because Rune never asks you to
/// overrule a failed certificate check.
struct SecurityInterstitial: View {
    let failure: Tab.SecurityFailure
    let goBack: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("This connection isn't private")
                .font(appearance.font(22, weight: .semibold))
                .foregroundStyle(appearance.contentText)
            Text(failure.host.uppercased()).font(appearance.type(.caption)).tracking(1.4)
                .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
            Text(failure.message)
                .font(appearance.type(.body))
                .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Go Back", action: goBack)
                .buttonStyle(.borderedProminent).tint(appearance.accent)
                .padding(.top, 6)
            Text("macOS couldn't verify this site's certificate. Rune never proceeds past a failed check.")
                .font(appearance.type(.caption))
                .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appearance.windowBG.opacity(appearance.containerOpacity))
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

/// The download progress card's perch, bottom-left over the page. Its own
/// view so only this corner re-renders per progress tick, not the window.
private struct DownloadCorner: View {
    @ObservedObject var downloads: DownloadStore

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if downloads.activeCount > 0 {
                DownloadProgressCard(downloads: downloads)
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.arrive, value: downloads.activeCount > 0)
    }
}

/// The bar, grown taller: suggestions run the full width of whatever bar
/// asked, on that bar's own surface, seam to seam — an expansion of the
/// field rather than a card floating near it.
private struct SuggestionList: View {
    @ObservedObject var model: BrowserModel
    let suggestions: [Suggestion]
    let highlighted: Int
    /// The surface the bar above is wearing (the strip's page tint); nil
    /// falls back to the chrome color.
    var surface: Color? = nil
    let pick: (Int) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    private var base: Color { surface ?? appearance.chrome }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                let on = index == highlighted
                HStack(spacing: 9) {
                    Image(systemName: icon(item)).frame(width: 16)
                        .foregroundStyle(on ? appearance.accentSecondaryText : appearance.secondaryText(on: base))
                    Text(title(item)).lineLimit(1)
                        .foregroundStyle(on ? appearance.accentText : appearance.text(on: base))
                    Spacer()
                    if case .history(let e) = item {
                        Text(e.url).font(appearance.font(11)).lineLimit(1)
                            .foregroundStyle(on ? appearance.accentSecondaryText : appearance.secondaryText(on: base))
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: appearance.radius(.small))
                    .fill(on ? appearance.accent : .clear))
                .contentShape(Rectangle())
                .onTapGesture { pick(index) }
            }
        }
        .padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                base.opacity(appearance.containerOpacity * 0.9).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
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
            // Clear on purpose: the window background (and its blur) is the
            // gap between the cards.
            Rectangle().fill(Color.clear)
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

    private var floating: Bool { appearance.appearance.chromeStyle == "floating" }

    var body: some View {
        VStack(spacing: 0) {
            // Only in a split. On its own, a pane is the window, and the window
            // already has an address bar up top.
            if model.isSplit {
                if floating, let tab = model.tab(for: pane) {
                    // The pane is a card, and the card wears its page.
                    PaneBar(model: model, tab: tab, pane: pane, address: $address,
                            focused: $focused, highlighted: $highlighted,
                            suggestionCount: suggestions.count, activate: activate)
                } else {
                    HStack(spacing: 6) {
                        AddressField(address: $address, focused: $focused, highlighted: $highlighted,
                                     suggestionCount: suggestions.count, activate: activate,
                                     trust: { model.tab(for: pane)?.serverTrust })
                        // A start-page pane has no PaneBar, but it still needs
                        // a way out of the split.
                        if floating {
                            Button { model.closePane(pane) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                                    .frame(width: 22, height: 22).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background {
                        ZStack {
                            WindowDragArea()
                            appearance.chrome.opacity(appearance.containerOpacity)
                                .allowsHitTesting(false)
                        }
                    }
                    if !floating { Divider() }
                }
            }
            ZStack(alignment: .top) {
                Group {
                    if let tab = model.tab(for: pane) {
                        TabContent(tab: tab, model: model, downloads: model.downloads,
                                   onClick: { focus() })
                    } else {
                        StartPage(model: model)
                    }
                }
                // Inside the pane's stack, so it lands over this page and not
                // over the neighbour's — the pane bar's own dropdown.
                if !suggestions.isEmpty {
                    SuggestionList(model: model, suggestions: suggestions, highlighted: highlighted,
                                   surface: model.tab(for: pane)?.themeColor.map(Color.init(nsColor:))) { index in
                        highlighted = index; activate()
                    }
                }
            }
        }
        .overlay {
            if model.focusedPane != pane {
                Rectangle().fill(.black.opacity(0.06)).allowsHitTesting(false)
            }
        }
        // In a floating split each pane is a card — rounded, discrete,
        // sitting on the window background.
        .clipShape(RoundedRectangle(
            cornerRadius: floating && model.isSplit ? appearance.radius(.large) : 0,
            style: .continuous))
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

/// One pane's header in a floating split — the page's own mini-chrome, the
/// way Arc dresses each half: the pane's tint, its navigation, its address
/// centered, and a close on the trailing edge. Observes its tab directly, so
/// back/forward enable and the tint arrive live.
private struct PaneBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: Tab
    let pane: BrowserModel.Pane
    @Binding var address: String
    var focused: FocusState<Bool>.Binding
    @Binding var highlighted: Int
    let suggestionCount: Int
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    private var surface: Color { tab.themeColor.map(Color.init(nsColor:)) ?? appearance.chrome }

    var body: some View {
        HStack(spacing: 4) {
            button("chevron.left", enabled: tab.canGoBack) { tab.webView.goBack() }
            button("chevron.right", enabled: tab.canGoForward) { tab.webView.goForward() }
            button("arrow.clockwise", enabled: true) { tab.webView.reload() }
            Spacer(minLength: 0)
            button("xmark", enabled: true) { model.closePane(pane) }
        }
        .overlay {
            AddressField(address: $address, focused: focused, highlighted: $highlighted,
                         suggestionCount: suggestionCount, activate: activate,
                         style: .pill, surface: surface,
                         trust: { tab.serverTrust })
                .frame(maxWidth: 360)
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background {
            ZStack {
                WindowDragArea()
                surface.opacity(appearance.containerOpacity).allowsHitTesting(false)
            }
        }
        .overlay(Grain(percent: appearance.appearance.grain))
        .animation(Motion.update, value: tab.themeColor)
        .foregroundStyle(appearance.text(on: surface))
    }

    /// Acting on a pane is being in it — every button focuses it first.
    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            model.focusedPane = pane
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(appearance.secondaryText(on: surface))
    }
}

private struct TabContent: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: BrowserModel
    /// Observed here so the link summary makes room the moment a download
    /// card lands in its corner.
    @ObservedObject var downloads: DownloadStore
    var onClick: (() -> Void)?
    var body: some View {
        if let failure = tab.securityFailure {
            SecurityInterstitial(failure: failure) {
                // A provisional failure never committed, so the page you were
                // on is still right here — clearing the verdict reveals it.
                // Navigating would walk history one entry too far back.
                tab.securityFailure = nil
            }
        } else if tab.urlString.isEmpty && !tab.isLoading {
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
                            // The download card holds this corner while bytes
                            // land; the summary steps up over it.
                            .padding(.bottom, downloads.activeCount > 0 ? 58 : 0)
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
            // The first sixty seconds: two hints for a profile that has never
            // browsed. History's first entry retires them for good.
            if model.history.entries.isEmpty && !model.isPrivate {
                Text("⌘K runs any command · ⌘T opens the address bar · drag a tab onto the shelf to pin it")
                    .font(appearance.type(.caption)).tracking(0.4)
                    .foregroundStyle(appearance.secondaryText(on: appearance.startPageBG))
                    .padding(.top, 2)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appearance.startPageBG.opacity(appearance.containerOpacity))
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
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    /// Buttons come from the appearance's list of command rawValues, so the
    /// toolbar is fully user-composable (and round-trips through presets).
    private var commands: [Command] {
        appearance.appearance.toolbarButtons.compactMap(Command.init(rawValue:))
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(commands) { CommandButton(model: model, command: $0, dispatch: dispatch) }

            if !model.isSplit {
                AddressField(address: $address, focused: addressFocused, highlighted: $highlighted,
                             suggestionCount: suggestionCount, activate: activate,
                             trust: { model.activeTab?.serverTrust })
            } else {
                // In a split the bars live in the panes, one each. A third one up
                // here would have to pick a pane to speak for, which is the whole
                // thing we just stopped doing.
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background {
            ZStack {
                WindowDragArea()
                appearance.chrome.opacity(appearance.containerOpacity)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(appearance.chromeText)
    }
}

/// Any command renders as a chrome button; a few keep live state (disabled
/// arrows, reload-becomes-stop, download progress). One implementation for
/// both chromes — the attached bar and the floating cluster.
private struct CommandButton: View {
    @ObservedObject var model: BrowserModel
    let command: Command
    let dispatch: (Command) -> Void
    /// What the button sits on; its ink keeps contrast against it.
    var surface: Color? = nil
    /// Sitting on glass (or the material fallback), not a solid chrome colour —
    /// ink with the semantic label colour so it adapts to the appearance the
    /// glass is showing, not a chrome tint it no longer touches.
    var onGlass = false
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        switch command {
        case .showDownloads:
            DownloadsButton(downloads: model.downloads, onGlass: onGlass) { dispatch(command) }
        case .goBack, .goForward, .reload:
            // These read the active tab's live state, so they must OBSERVE it:
            // back/forward-cache restores don't fire `didCommit`, and this
            // view watches the model, not the tab, so nothing here would
            // otherwise re-render when canGoForward/isLoading changed.
            if let tab = model.activeTab {
                NavButton(tab: tab, command: command, dispatch: dispatch,
                          surface: surface, onGlass: onGlass)
            } else if command != .goForward {
                button(command.icon) { dispatch(command) }.disabled(true).help(command.title)
            }
        default:
            button(command.icon) { dispatch(command) }.help(command.title)
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(onGlass ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(appearance.secondaryText(on: surface ?? appearance.chrome)))
    }
}

/// Back, forward and reload — the three buttons whose look depends on the
/// active tab's live navigation state. It observes the tab, so it re-renders
/// the moment canGoBack/canGoForward/isLoading move, even on a bfcache
/// restore that fires no navigation delegate. Forward hides itself when
/// there's nothing ahead; the strip closes the gap.
private struct NavButton: View {
    @ObservedObject var tab: Tab
    let command: Command
    let dispatch: (Command) -> Void
    var surface: Color? = nil
    var onGlass = false
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        switch command {
        case .goBack:
            button(command.icon).disabled(!tab.canGoBack).help(command.title)
        case .goForward:
            if tab.canGoForward { button(command.icon).help(command.title) }
        case .reload:
            button(tab.isLoading ? "xmark" : command.icon).help(command.title)
        default:
            button(command.icon).help(command.title)
        }
    }

    private func button(_ symbol: String) -> some View {
        Button { dispatch(command) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(onGlass ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(appearance.secondaryText(on: surface ?? appearance.chrome)))
    }
}

/// The minimal strip: a thin band above the page carrying exactly two things —
/// back/forward, and a quiet address pill. Nothing overlaps the page, nothing
/// else asks for room. The hierarchy is fieldframes': one legible statement
/// (the address), micro-scale ghost controls beside it, whitespace doing the
/// rest. Which side the navigation sits on is yours to choose.
/// The rest of the toolbar, out of the way: your corner commands live behind
/// a grab tab peeking from the page's bottom-right edge. Hover slides the kit
/// out; reading down the page slides the tab away entirely (the bridge
/// reports scroll direction). A finished download pins a dot to the tab and
/// keeps it on stage until you've looked. In wiggle mode this is one of the
/// two shelves buttons drag between — still data-driven, still remappable.
private struct CornerToolbar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var downloads: DownloadStore
    let dispatch: (Command) -> Void
    @Binding var editing: Bool
    @EnvironmentObject var appearance: AppearanceStore
    @State private var open = false
    @State private var pageScrolledDown = false
    @State private var dropTargeted = false

    private var commands: [Command] { appearance.cornerCommands }

    private var expanded: Bool { open || editing }
    /// Off stage entirely — unless you're hovering it, editing it, or a
    /// finished download is waiting to be seen.
    private var ducked: Bool { pageScrolledDown && !expanded && !downloads.hasUnseen }

    private var scrollPublisher: AnyPublisher<Bool, Never> {
        model.activeTab?.$scrolledDown.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()
    }

    /// The tab's outline: a handle hanging off the window's right edge —
    /// left corners rounded 8, right edge square against the edge it's pulled
    /// from. Fixed in both states (the glitch was the left corners morphing
    /// from 8 to a pill radius as it opened); expanding is purely a width
    /// change now.
    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                               bottomTrailingRadius: 0, topTrailingRadius: 0,
                               style: .continuous)
    }

    var body: some View {
        if !commands.isEmpty || editing || downloads.hasUnseen {
            HStack(spacing: 2) {
                if expanded {
                    ForEach(commands) { command in
                        EditableControl(model: model, command: command, dispatch: dispatch,
                                        editing: editing, onGlass: true,
                                        swap: { appearance.cycleSlot(command.rawValue) },
                                        remove: { appearance.disableControl(command.rawValue) })
                    }
                    if editing {
                        addMenu
                        Button { withAnimation(Motion.arrive) { editing = false } } label: {
                            // The circle checkmark, but inked with the primary
                            // label colour like the + beside it — not the
                            // accent, which washed the circle out whenever it
                            // sat close to the glass colour.
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 26, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Done")
                    }
                }
                // The grab handle is always the rightmost thing — so there's
                // always something to grab, and the buttons open out to its
                // left. A slim grip the height of the icon glyphs; when the
                // kit is open it sits in a button-width cell so it keeps the
                // row's spacing instead of jamming against the last icon.
                // `.primary` so it inks itself against the glass in either
                // appearance, rather than tracking a chrome colour it no
                // longer sits on.
                Capsule()
                    .fill(Color.primary.opacity(0.7))
                    .frame(width: 6, height: 15)
                    .frame(width: expanded ? 18 : 6, height: 24)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        if downloads.hasUnseen {
                            Circle().fill(appearance.accent).frame(width: 6, height: 6)
                                .offset(x: -4, y: -1)
                        }
                    }
            }
            // One padding for both states: the grip and the buttons wear the
            // same frame, so the surface never changes height on hover.
            .padding(.horizontal, 6).padding(.vertical, 2)
            // The shared overlay surface — Liquid Glass where the OS has it,
            // frosted material otherwise — in the tab's own shape (pill open,
            // docked tab closed).
            .runeSurface(appearance, in: tabShape)
            // Drop-target ring rides on top; a stroke only catches the edge,
            // and it's clear until a control is actually over it.
            .overlay {
                tabShape.strokeBorder(dropTargeted ? appearance.accent : .clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            // Docked flush against the window's right edge in both states —
            // the +12 cancels the container's trailing inset. It used to jump
            // to inset-0 when it opened, which slid its bounds out from under
            // a stationary cursor and made the hover flicker; holding it flush
            // keeps the grip under the cursor as the kit pulls out leftward.
            // Only ducking slides the whole tab off the edge.
            .offset(x: ducked ? 72 : 12)
            .onHover { inside in
                guard !editing else { return }
                withAnimation(Motion.arrive) { open = inside }
            }
            .animation(Motion.arrive, value: expanded)
            .animation(Motion.arrive, value: ducked)
            .dropDestination(for: ControlDrag.self) { items, _ in
                guard editing, let drag = items.first else { return false }
                withAnimation(Motion.update) { appearance.move(drag.command, to: .corner) }
                return true
            } isTargeted: { dropTargeted = editing && $0 }
            .onReceive(scrollPublisher) { pageScrolledDown = $0 }
            .onChange(of: model.selection) { pageScrolledDown = model.activeTab?.scrolledDown ?? false }
        }
    }

    /// Everything not yet on either shelf, one pick away from the corner.
    private var addMenu: some View {
        Menu {
            ForEach(Command.allCases.filter { !appearance.appearance.toolbarButtons.contains($0.rawValue) }) { command in
                Button {
                    withAnimation(Motion.update) { appearance.move(command.rawValue, to: .corner) }
                } label: {
                    Label(command.title, systemImage: command.icon)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 26)
        .foregroundStyle(.secondary)
        .help("Add a control")
    }
}

/// One button on a shelf, wearing wiggle mode when it's on: the jiggle, a
/// remove badge, and a drag payload. At rest it's just the button.
///
/// In edit mode this is deliberately NOT a disabled Button — a disabled
/// control also declines to start drags. It's the bare glyph, drawn the same,
/// with the drag and the badge attached to it directly.
private struct EditableControl: View {
    @ObservedObject var model: BrowserModel
    let command: Command
    let dispatch: (Command) -> Void
    let editing: Bool
    var surface: Color? = nil
    var onGlass = false
    /// Send this button to the other shelf. Clicking a wiggling button does
    /// the same thing as dragging it across — the strip lives in the
    /// titlebar region, where the window frame outranks drag gestures often
    /// enough that the click needs to be a full way, not a shortcut.
    let swap: () -> Void
    let remove: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    private var ink: AnyShapeStyle {
        onGlass ? AnyShapeStyle(.secondary)
                : AnyShapeStyle(appearance.secondaryText(on: surface ?? appearance.chrome))
    }

    var body: some View {
        if editing {
            // A bare glyph, NOT a Button: a Button's press gesture wins over
            // `.draggable` and the drag never starts. A tap gesture and a drag
            // gesture coexist (tap = no travel, drag = travel), so a click
            // still cycles the shelf and a drag still lifts the control.
            Image(systemName: command.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
                .foregroundStyle(ink)
                .contentShape(Rectangle())
                .modifier(Wiggle())
                .draggable(ControlDrag(command: command.rawValue)) {
                    // The drag preview: the same glyph on a small chip.
                    Image(systemName: command.icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 24)
                }
                .onTapGesture { withAnimation(Motion.update) { swap() } }
                .overlay(alignment: .topLeading) {
                    Button(action: remove) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(red: 0.85, green: 0.3, blue: 0.25))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -2, y: -3)
                    .help("Remove")
                }
        } else {
            CommandButton(model: model, command: command, dispatch: dispatch,
                          surface: surface, onGlass: onGlass)
        }
    }
}

/// The iOS home-screen tremble, small enough for chrome buttons: a couple of
/// degrees each way, forever, until edit mode ends and the modifier leaves.
private struct Wiggle: ViewModifier {
    @State private var tilted = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilted ? 2.4 : -2.4))
            .animation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true), value: tilted)
            .onAppear { tilted = true }
    }
}

/// The strip, wearing the page: it tints itself with the site's theme color,
/// the way Arc's bar does. Navigation cluster on one side, shield and split
/// on the other (swappable), the host centered between them. On the start
/// page it wears the chrome color.
private struct MinimalChrome: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void
    @Binding var address: String
    var addressFocused: FocusState<Bool>.Binding
    @Binding var highlighted: Int
    let suggestionCount: Int
    @Binding var editing: Bool
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    /// The active page's color, pushed as WebKit discovers it.
    @State private var tint: NSColor?
    /// Which strip cluster a drag is hovering, if any.
    @State private var dropTarget: AppearanceStore.ControlSlot?

    private var surface: Color { tint.map(Color.init(nsColor:)) ?? appearance.chrome }

    /// The lights live in the sidebar; when it's away (or on the right), the
    /// strip carries them so the window keeps its verbs.
    private var stripCarriesLights: Bool {
        !appearance.appearance.hideTrafficLights
            && (model.zenActive || !model.sidebarVisible || appearance.appearance.sidebarOnRight)
    }

    private var themePublisher: AnyPublisher<NSColor?, Never> {
        model.activeTab?.$themeColor.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()
    }

    /// One of the strip's two button clusters — either side of the address —
    /// as a wiggle-mode drop target. An empty one still shows a landing spot
    /// while editing so you can drop the first button into it.
    private func cluster(_ slot: AppearanceStore.ControlSlot, _ commands: [Command]) -> some View {
        HStack(spacing: 2) {
            ForEach(commands) { command in
                EditableControl(model: model, command: command, dispatch: dispatch,
                                editing: editing, surface: surface,
                                swap: { appearance.cycleSlot(command.rawValue) },
                                remove: { appearance.disableControl(command.rawValue) })
            }
            if editing && commands.isEmpty {
                RoundedRectangle(cornerRadius: appearance.radius(.small))
                    .strokeBorder(appearance.secondaryText(on: surface).opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .frame(width: 26, height: 22)
            }
        }
        .padding(.vertical, editing ? 1 : 0).padding(.horizontal, editing ? 3 : 0)
        .background(RoundedRectangle(cornerRadius: appearance.radius(.small))
            .fill(dropTarget == slot ? appearance.accent.opacity(0.18) : .clear))
        .dropDestination(for: ControlDrag.self) { items, _ in
            guard editing, let drag = items.first else { return false }
            withAnimation(Motion.update) { appearance.move(drag.command, to: slot) }
            dropTarget = nil
            return true
        } isTargeted: { inside in
            if inside && editing { dropTarget = slot }
            else if dropTarget == slot { dropTarget = nil }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if stripCarriesLights { TrafficLights() }
            // The way back: with the sidebar away, its toggle moves up here. In
            // zen the sidebar answers to an edge hover instead, so no toggle.
            if !model.zenActive && !model.sidebarVisible {
                CommandButton(model: model, command: .toggleSidebar, dispatch: dispatch,
                              surface: surface)
            }
            // Two button clusters, one on each side of the address; drop a
            // control into either. The field runs the whole way between them.
            cluster(.leading, appearance.stripLeadingCommands)
            if !model.isSplit {
                AddressField(address: $address, focused: addressFocused, highlighted: $highlighted,
                             suggestionCount: suggestionCount, activate: activate,
                             style: .pill, surface: surface,
                             trust: { model.activeTab?.serverTrust })
                    .background((addressFocused.wrappedValue ? appearance.hover : .clear),
                                in: RoundedRectangle(cornerRadius: appearance.radius(.pill)))
                    .animation(Motion.arrive, value: addressFocused.wrappedValue)
            } else {
                Spacer(minLength: 0)
            }
            cluster(.trailing, appearance.stripTrailingCommands)
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
        .frame(height: 36)
        .background {
            ZStack {
                // Not while editing: the drag surface answers mouse-downs
                // before SwiftUI's drag can, and a button dragged toward the
                // corner kit took the whole window with it.
                if !editing { WindowDragArea() }
                surface.opacity(appearance.containerOpacity).allowsHitTesting(false)
            }
        }
        .overlay(Grain(percent: appearance.appearance.grain))
        .animation(Motion.update, value: tint)
        .foregroundStyle(appearance.text(on: surface))
        .onReceive(themePublisher) { tint = $0 }
        .onChange(of: model.selection) { tint = model.activeTab?.themeColor }
        .onChange(of: model.focusedPane) { tint = model.activeTab?.themeColor }
    }
}

// MARK: - Zen reveals

/// The sidebar, in zen: a thin lip hugging the window edge at rest, blooming
/// to the full sidebar (over the page, not beside it) while the pointer is on
/// it. One hover region for both states, so the pointer never falls out of the
/// zone as the panel grows — no flicker.
private struct ZenSidebarReveal<Content: View>: View {
    let onRight: Bool
    @ViewBuilder var content: () -> Content
    @EnvironmentObject var appearance: AppearanceStore
    @State private var revealed = false

    var body: some View {
        ZStack(alignment: onRight ? .topTrailing : .topLeading) {
            if revealed {
                content()
                    .frame(width: appearance.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: onRight ? .leading : .trailing) { SidebarResizeHandle() }
                    .shadow(color: .black.opacity(0.28), radius: 22, x: onRight ? -10 : 10)
                    .transition(.move(edge: onRight ? .trailing : .leading))
            } else {
                // The invisible edge you brush to call it back.
                Color.clear.frame(width: 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
        .frame(width: revealed ? appearance.sidebarWidth : 8,
               alignment: onRight ? .trailing : .leading)
        .frame(maxHeight: .infinity)
        .onHover { hovering in withAnimation(Motion.arrive) { revealed = hovering } }
    }
}

/// The strip, in zen: an invisible hover lip at rest that blooms to the whole
/// chrome on hover (or whenever the address is being typed into). In full zen
/// the lip is a thin 8pt edge; in subtle zen it's the height of the in-flow
/// band below, so the reveal sits exactly over it. One growing hover region, so
/// the pointer never falls out of the zone as the strip blooms.
private struct ZenChromeReveal<Full: View>: View {
    let collapsedHeight: CGFloat
    let keepOpen: Bool
    @ViewBuilder var full: () -> Full
    @State private var hover = false
    private var open: Bool { hover || keepOpen }

    var body: some View {
        ZStack(alignment: .top) {
            if open {
                full().transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Color.clear.frame(height: collapsedHeight).contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onHover { hovering in withAnimation(Motion.arrive) { hover = hovering } }
    }
}

/// The subtle band: a hair-high echo of the address that stays in the layout
/// (pushing the page down) and wears the site's own top colour, so it reads as
/// the page carried up rather than a bar laid over it. Hovering the strip above
/// hands you back the whole chrome.
private struct ZenSubtleBand: View {
    let hint: String
    /// The site's own top colour — its declared theme-color, or the header
    /// Rune sampled when none was declared.
    let tint: NSColor?
    @EnvironmentObject var appearance: AppearanceStore

    private var surface: Color { tint.map(Color.init(nsColor:)) ?? appearance.chrome }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .semibold))
            Text(hint.isEmpty ? "Rune" : hint).font(appearance.font(11)).lineLimit(1)
        }
        .foregroundStyle(appearance.secondaryText(on: surface))
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(surface.opacity(appearance.containerOpacity))
        .animation(Motion.update, value: tint)
    }
}

/// A surface you can drag the window by — granted deliberately, never by
/// blanket `isMovableByWindowBackground` (which turned the split handle into
/// a window drag). AppKit-native: the view simply asks the window to move.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { false }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// The desktop, behind frosted glass: a behind-window material that the
/// container fills sit on. Transparency lives in the fills, not the window —
/// buttons, icons and text never fade.
struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Rune's own traffic lights. The system's lived in the titlebar, and the
/// titlebar is gone — these are the same three verbs drawn by us: honest
/// circles that glyph on hover, and they sit wherever the chrome wants them.
struct TrafficLights: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            light("#FF5F57", "xmark") { NSApp.keyWindow?.performClose(nil) }
            light("#FEBC2E", "minus") { NSApp.keyWindow?.miniaturize(nil) }
            light("#28C840", "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.zoom(nil) }
        }
        .onHover { hovering = $0 }
    }

    private func light(_ hex: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(hex: hex) ?? .gray)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                if hovering {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Film grain over the chrome, Arc-style: one tiled noise image at whisper
/// opacity. Texture, not information — it never intercepts a click.
struct Grain: View {
    let percent: Double

    nonisolated static let tile: NSImage = {
        let size = 128
        var bytes = [UInt8](repeating: 0, count: size * size)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent)
        else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }()

    var body: some View {
        if percent > 0 {
            Image(nsImage: Self.tile)
                .resizable(resizingMode: .tile)
                .opacity(percent / 100)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}
