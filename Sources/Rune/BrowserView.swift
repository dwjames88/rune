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

            if model.isPrivate { privateBanner }

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
                    FaviconTile(saved: fav, selected: model.selection == .saved(fav.id))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Tabs")
            ForEach(Array(model.sessionTabs.enumerated()), id: \.element.id) { index, tab in
                SessionRow(model: model, tab: tab, dropIndex: index)
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

    var body: some View {
        RowBody(icon: { Favicon(png: saved.faviconPNG, name: saved.name, size: 15) },
                name: saved.name,
                selected: model.selection == .saved(saved.id), hovering: hovering) {
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

    var body: some View {
        RowBody(icon: { Favicon(image: tab.favicon, name: tab.displayName,
                                size: 15, loading: tab.isLoading) },
                name: tab.displayName,
                selected: model.selection == .session(tab.id), hovering: hovering) {
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

/// A tab row: favicon, name, trailing affordances. Selection reads as one fill
/// — a tab carries no colour of its own, so there is no dot and no edge bar.
private struct RowBody<Icon: View, Trailing: View>: View {
    @ViewBuilder var icon: () -> Icon
    let name: String
    let selected: Bool
    let hovering: Bool
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text(name).lineLimit(1).font(appearance.font(13))
            Spacer(minLength: 4)
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

/// One rename popover for everything in the sidebar — tabs and folders alike.
private struct RenamePopover: View {
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
        guard addressFocused, !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            suggestions = []; return
        }
        let predictions = model.history.predict(address)
        var out: [Suggestion] = []
        // If you've clearly started typing a host you visit, that's the answer —
        // lead with it so Return just goes there.
        if let top = predictions.first, model.history.isConfident(address, top) {
            out = [.history(top), .navigate(address)] + predictions.dropFirst().map(Suggestion.history)
        } else {
            out = [.navigate(address)] + predictions.map(Suggestion.history)
        }
        // Sounds like a description, not a destination — offer Claude.
        let words = address.split(separator: " ").count
        if model.ai.isAvailable, words >= 3 { out.append(.askAI(address)) }
        suggestions = out
    }

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model, dispatch: dispatch, address: $address, addressFocused: $addressFocused,
                    highlighted: $highlighted, suggestionCount: suggestions.count,
                    showDownloads: $showDownloads, activate: activate)
            Divider()
            ZStack(alignment: .top) {
                appearance.windowBG
                if model.isSplit {
                    HStack(spacing: 0) {
                        Pane(model: model, pane: .primary)
                        Divider()
                        Pane(model: model, pane: .secondary)
                    }
                } else if let tab = model.activeTab {
                    TabContent(tab: tab, model: model)
                } else {
                    StartPage(model: model)
                }
                if showFind {
                    FindBar(model: model, isPresented: $showFind)
                        .padding(.top, 8).padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showDownloads {
                    DownloadsPanel(downloads: model.downloads, showing: $showDownloads)
                        .padding(.top, 8).padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let candidates = model.collectCandidates {
                    CollectSheet(model: model, candidates: candidates)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !suggestions.isEmpty {
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
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) {
            if $0.aimed(at: model) { addressFocused = true }
        }
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
        let list = suggestions
        guard !list.isEmpty else { model.navigate(address); addressFocused = false; return }
        switch list[min(highlighted, list.count - 1)] {
        case .navigate(let q): model.navigate(q)
        case .history(let e): model.navigate(e.url)
        case .askAI(let q):
            Task {
                if let url = try? await model.findInHistory(q) { model.navigate(url.absoluteString) }
                else { model.navigate(q) }   // nothing matched — fall back to a search
            }
        }
        addressFocused = false
        highlighted = 0
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

/// One side of a Split View. Marked only when it isn't the focused one — a
/// border around the pane you're already using is noise, but knowing where the
/// next ⌘L or ⌘W will land is not.
private struct Pane: View {
    @ObservedObject var model: BrowserModel
    let pane: BrowserModel.Pane
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Group {
            if let tab = model.tab(for: pane) {
                TabContent(tab: tab, model: model, onClick: { model.focusedPane = pane })
            } else {
                StartPage(model: model)
            }
        }
        .overlay {
            if model.focusedPane != pane {
                Rectangle().fill(.black.opacity(0.06)).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.focusedPane = pane }
    }
}

private struct TabContent: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: BrowserModel
    var onClick: (() -> Void)?
    var body: some View {
        if tab.urlString.isEmpty && !tab.isLoading {
            StartPage(model: model)
        } else {
            WebContainer(webView: tab.webView, onClick: onClick).id(tab.id)
                // Claude, anchored to the page: hover a link for a summary,
                // select text for actions.
                .overlay(alignment: .topLeading) {
                    if let hover = tab.hoveredLink {
                        LinkSummaryPopover(target: hover, ai: model.ai)
                            .offset(x: min(max(8, hover.x), 900), y: hover.y + 6)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let selection = tab.selection {
                        SelectionActions(target: selection, ai: model.ai)
                            .offset(x: min(max(8, selection.x), 860), y: selection.y + 8)
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
    private var recents: [HistoryEntry] {
        Array(model.history.entries.sorted { $0.lastVisited > $1.lastVisited }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(greeting).font(appearance.font(40, weight: .semibold))
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
                HStack(spacing: 14) {
                    ForEach(model.favorites) { fav in
                        StartPageTile(saved: fav) { model.select(.saved(fav.id)) }
                    }
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.startPageBG)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusStartPage)) {
            if $0.aimed(at: model) { focused = true }
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

    /// Host-only address display ("pinkbike.com") while the field isn't focused.
    private var compactHost: String {
        guard let host = URL(string: address)?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    private var showCompact: Bool {
        appearance.appearance.compactAddressBar && !addressFocused.wrappedValue && !address.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(commands) { commandButton($0) }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                ZStack(alignment: .leading) {
                    TextField("Search or enter address", text: $address)
                        .textFieldStyle(.plain)
                        .foregroundStyle(appearance.chromeText)
                        .focused(addressFocused)
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
                        .onKeyPress(.escape) { addressFocused.wrappedValue = false; return .handled }
                        .opacity(showCompact ? 0 : 1)
                    if showCompact {
                        Text(compactHost).lineLimit(1)
                            .foregroundStyle(appearance.chromeText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(appearance.windowBG)   // hide the field underneath
                            .contentShape(Rectangle())
                            .onTapGesture { addressFocused.wrappedValue = true }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(appearance.windowBG, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(addressFocused.wrappedValue ? appearance.accent : appearance.hairline, lineWidth: 1))
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
