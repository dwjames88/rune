import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    let dispatch: (Command) -> Void

    @State private var showPalette = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.sidebarVisible && appearance.appearance.sidebarOnRight == false {
                    sidebar; Divider()
                }
                ContentArea(model: model)
                if model.sidebarVisible && appearance.appearance.sidebarOnRight {
                    Divider(); sidebar
                }
            }
            .animation(.easeInOut(duration: 0.18), value: model.sidebarVisible)
            .background(appearance.windowBG)

            if showPalette {
                CommandPalette(model: model, dispatch: dispatch, isPresented: $showPalette)
            }
        }
        .font(appearance.uiFont)
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in showPalette = true }
    }

    private var sidebar: some View {
        Sidebar(model: model).frame(width: appearance.sidebarWidth).transition(.move(edge: .leading))
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: appearance.appearance.hideTrafficLights ? 8 : 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.favorites.isEmpty { FavoritesRow(model: model) }
                    PinnedSection(model: model)
                    SessionSection(model: model)
                }
                .padding(.horizontal, 8).padding(.top, 4)
            }

            Spacer(minLength: 0)
            Button { model.newTab() } label: {
                Label("New Tab", systemImage: "plus").font(appearance.font(13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 7)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(8)
        }
        .background(appearance.sidebarBG)
    }
}

// MARK: Favorites (max 6, favicons only)

private struct FavoritesRow: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Favorites")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(model.favorites) { fav in
                    FaviconTile(saved: fav, selected: model.selection == .saved(fav.id))
                        .onTapGesture { model.select(.saved(fav.id)) }
                        .contextMenu { EditMenu(model: model, selection: .saved(fav.id), isFavorite: true) }
                }
            }
        }
    }
}

private struct FaviconTile: View {
    let saved: SavedTab
    let selected: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Favicon(png: saved.faviconPNG, name: saved.name, color: saved.colorHex, size: 20)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionHeader(title: "Pinned")
                Spacer()
                Button { _ = model.addFolder() } label: { Image(systemName: "folder.badge.plus").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("New Folder")
            }
            ForEach(model.folders) { folder in FolderView(model: model, folder: folder) }
            ForEach(model.pinned(in: nil)) { saved in
                SavedRow(model: model, saved: saved)
            }
            if model.pinned.isEmpty && model.folders.isEmpty {
                Text("Pin a tab to keep it here.").font(appearance.font(11)).foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
        }
    }
}

private struct FolderView: View {
    @ObservedObject var model: BrowserModel
    let folder: Folder
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 10)
                Image(systemName: folder.icon).font(.system(size: 11)).foregroundStyle(appearance.accent)
                Text(folder.name).font(appearance.font(12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleFolder(folder.id) }
            .contextMenu { FolderMenu(model: model, folder: folder) }

            if !folder.collapsed {
                ForEach(model.pinned(in: folder.id)) { saved in
                    SavedRow(model: model, saved: saved).padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: Session tabs

private struct SessionSection: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Tabs")
            ForEach(model.sessionTabs) { tab in SessionRow(model: model, tab: tab) }
        }
    }
}

// MARK: Rows

private struct SavedRow: View {
    @ObservedObject var model: BrowserModel
    let saved: SavedTab
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false

    var body: some View {
        RowBody(favicon: { Favicon(png: saved.faviconPNG, name: saved.name, color: saved.colorHex, size: 15) },
                name: saved.name, colorHex: saved.colorHex,
                selected: model.selection == .saved(saved.id), hovering: hovering) { EmptyView() }
            .onTapGesture { model.select(.saved(saved.id)) }
            .onHover { hovering = $0 }
            .contextMenu { EditMenu(model: model, selection: .saved(saved.id), isFavorite: false) }
    }
}

private struct SessionRow: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: Tab
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false

    var body: some View {
        RowBody(favicon: { Favicon(image: tab.favicon, name: tab.displayName, color: tab.colorHex, size: 15, loading: tab.isLoading) },
                name: tab.displayName, colorHex: tab.colorHex,
                selected: model.selection == .session(tab.id), hovering: hovering) {
            if hovering {
                Button { model.close(session: tab) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .padding(3).background(appearance.hover, in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .onTapGesture { model.select(.session(tab.id)) }
        .onHover { hovering = $0 }
        .contextMenu { EditMenu(model: model, selection: .session(tab.id), isFavorite: false) }
    }
}

private struct RowBody<Icon: View, Trailing: View>: View {
    @ViewBuilder var favicon: () -> Icon
    let name: String
    let colorHex: String?
    let selected: Bool
    let hovering: Bool
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 8) {
            favicon()
            Text(name).lineLimit(1).font(appearance.font(13))
            Spacer(minLength: 4)
            if let hex = colorHex, let c = Color(hex: hex) {
                Circle().fill(c).frame(width: 7, height: 7)
            }
            trailing()
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(selected ? appearance.selection : (hovering ? appearance.hover : .clear)))
        .contentShape(Rectangle())
    }
}

// MARK: Favicon view

struct Favicon: View {
    var png: Data? = nil
    var image: NSImage? = nil
    let name: String
    var color: String? = nil
    let size: CGFloat
    var loading = false

    private var nsImage: NSImage? { image ?? png.flatMap(NSImage.init(data:)) }

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.small).scaleEffect(0.55)
            } else if let img = nsImage {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill((color.flatMap(Color.init(hex:)) ?? .secondary).opacity(0.85))
                    .overlay(Text(String(name.first ?? "•").uppercased())
                        .font(.system(size: size * 0.6, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SectionHeader: View {
    let title: String
    @EnvironmentObject var appearance: AppearanceStore
    var body: some View {
        Text(title).font(appearance.font(11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.leading, 8)
    }
}

// MARK: - Context menus

private struct EditMenu: View {
    @ObservedObject var model: BrowserModel
    let selection: Selection
    let isFavorite: Bool

    var body: some View {
        Button("Rename…") { NotificationCenter.default.post(name: .beginRename, object: selection) }
        Menu("Color") {
            ForEach(colorOptions, id: \.0) { name, hex in
                Button(name) { model.setColor(hex, for: selection) }
            }
            Button("None") { model.setColor(nil, for: selection) }
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

    private var colorOptions: [(String, String)] {
        [("Red", "#FF3B30"), ("Orange", "#FF9500"), ("Yellow", "#FFCC00"),
         ("Green", "#34C759"), ("Blue", "#0A84FF"), ("Purple", "#AF52DE"), ("Pink", "#FF2D55")]
    }
}

private struct FolderMenu: View {
    @ObservedObject var model: BrowserModel
    let folder: Folder
    var body: some View {
        Button("Rename…") { NotificationCenter.default.post(name: .beginRenameFolder, object: folder.id) }
        Menu("Icon") {
            ForEach(["folder.fill", "star.fill", "briefcase.fill", "cart.fill", "book.fill", "gamecontroller.fill", "heart.fill"], id: \.self) { icon in
                Button { model.setFolderIcon(folder.id, icon) } label: { Label(icon, systemImage: icon) }
            }
        }
        Divider()
        Button("Delete Folder", role: .destructive) { model.deleteFolder(folder.id) }
    }
}

// MARK: - Content area

private struct ContentArea: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model)
            Divider()
            ZStack {
                appearance.windowBG
                if let tab = model.activeTab {
                    TabContent(tab: tab, model: model)
                } else {
                    StartPage(model: model)
                }
            }
        }
    }
}

private struct TabContent: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: BrowserModel
    var body: some View {
        if tab.urlString.isEmpty && !tab.isLoading {
            StartPage(model: model)
        } else {
            WebContainer(webView: tab.webView).id(tab.id)
        }
    }
}

private struct StartPage: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Rune").font(appearance.font(40, weight: .semibold)).foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(model.settings.searchEngine.name) or enter address", text: $query)
                    .textFieldStyle(.plain).font(appearance.font(17)).focused($focused)
                    .onSubmit { model.navigate(query); query = "" }
            }
            .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: 560)
            .background(appearance.chrome, in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? appearance.accent : appearance.hairline, lineWidth: 1))
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.windowBG)
        .onAppear { focused = true }
    }
}

private struct Toolbar: View {
    @ObservedObject var model: BrowserModel
    @EnvironmentObject var appearance: AppearanceStore
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            button("sidebar.left") { model.sidebarVisible.toggle() }
            button("chevron.left") { model.goBack() }.disabled(!(model.activeTab?.canGoBack ?? false))
            button("chevron.right") { model.goForward() }.disabled(!(model.activeTab?.canGoForward ?? false))
            button(model.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise") { model.reload() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain).focused($addressFocused)
                    .onSubmit { model.navigate(address); addressFocused = false }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(appearance.windowBG, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(addressFocused ? appearance.accent : appearance.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10).padding(.vertical, 7).background(appearance.chrome)
        .onChange(of: model.selection) { sync() }
        .onChange(of: model.activeTab?.urlString) { if !addressFocused { sync() } }
        .onAppear { sync() }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in addressFocused = true }
    }

    private func sync() { address = model.activeTab?.urlString ?? "" }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
        }.buttonStyle(.plain).foregroundStyle(.secondary)
    }
}

extension Notification.Name {
    static let beginRename = Notification.Name("rune.beginRename")
    static let beginRenameFolder = Notification.Name("rune.beginRenameFolder")
}
