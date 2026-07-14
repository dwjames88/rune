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
                if model.sidebarVisible && !appearance.appearance.sidebarOnRight { sidebar; Divider() }
                ContentArea(model: model)
                if model.sidebarVisible && appearance.appearance.sidebarOnRight { Divider(); sidebar }
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
                    FavoritesSection(model: model)
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
            .buttonStyle(.plain).foregroundStyle(appearance.sidebarSecondary).padding(8)
        }
        .background(appearance.sidebarBG)
        .foregroundStyle(appearance.sidebarText)
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
        Favicon(png: saved.faviconPNG, name: saved.name, color: saved.colorHex, size: 20)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(selected ? appearance.selection : appearance.hover))
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(selected ? tint : .clear, lineWidth: 1.5))
            .help(saved.name)
    }
    private var tint: Color { saved.colorHex.flatMap(Color.init(hex:)) ?? appearance.accent }
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
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9)).foregroundStyle(appearance.sidebarSecondary).frame(width: 10)
                Image(systemName: folder.icon).font(.system(size: 11)).foregroundStyle(appearance.accent)
                Text(folder.name).font(appearance.font(12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(targeted ? appearance.accent.opacity(0.22) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleFolder(folder.id) }
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let drag = items.first else { return false }
                model.handleDrop(drag, to: .pinned(folderID: folder.id, index: nil)); return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                Button("Rename…") { draftName = folder.name; renaming = true }
                Button("Change Icon…") { pickingIcon = true }
                Divider()
                Button("Delete Folder", role: .destructive) { model.deleteFolder(folder.id) }
            }
            .popover(isPresented: $pickingIcon) {
                SymbolPicker(symbol: .constant(folder.icon), tint: appearance.accent) { icon in
                    model.setFolderIcon(folder.id, icon); pickingIcon = false
                }
            }
            .popover(isPresented: $renaming) {
                HStack {
                    TextField("Folder name", text: $draftName)
                        .textFieldStyle(.roundedBorder).frame(width: 180)
                        .onSubmit { model.renameFolder(folder.id, to: draftName); renaming = false }
                    Button("Save") { model.renameFolder(folder.id, to: draftName); renaming = false }
                }.padding(10)
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
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false
    @State private var customizing = false

    var body: some View {
        RowBody(icon: { Favicon(png: saved.faviconPNG, name: saved.name, color: saved.colorHex, size: 15) },
                name: saved.name, colorHex: saved.colorHex,
                selected: model.selection == .saved(saved.id), hovering: hovering) { EmptyView() }
            .onTapGesture { model.select(.saved(saved.id)) }
            .onHover { hovering = $0 }
            .draggable(TabDrag(id: saved.id, origin: origin))
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let drag = items.first else { return false }
                model.handleDrop(drag, to: .pinned(folderID: folderID, index: dropIndex)); return true
            }
            .contextMenu {
                TabMenu(model: model, selection: .saved(saved.id), isFavorite: origin == .favorite,
                        customize: { customizing = true })
            }
            .popover(isPresented: $customizing) {
                CustomizePopover(model: model, selection: .saved(saved.id),
                                 name: saved.name, colorHex: saved.colorHex)
            }
    }
}

private struct SessionRow: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: Tab
    let dropIndex: Int
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false
    @State private var customizing = false

    var body: some View {
        RowBody(icon: { Favicon(image: tab.favicon, name: tab.displayName, color: tab.colorHex,
                                size: 15, loading: tab.isLoading) },
                name: tab.displayName, colorHex: tab.colorHex,
                selected: model.selection == .session(tab.id), hovering: hovering) {
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
                    customize: { customizing = true })
        }
        .popover(isPresented: $customizing) {
            CustomizePopover(model: model, selection: .session(tab.id),
                             name: tab.displayName, colorHex: tab.colorHex)
        }
    }
}

private struct RowBody<Icon: View, Trailing: View>: View {
    @ViewBuilder var icon: () -> Icon
    let name: String
    let colorHex: String?
    let selected: Bool
    let hovering: Bool
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject var appearance: AppearanceStore

    private var tint: Color? { colorHex.flatMap(Color.init(hex:)) }

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text(name).lineLimit(1).font(appearance.font(13))
            Spacer(minLength: 4)
            if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
            trailing()
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
            .fill(selected ? (tint?.opacity(0.22) ?? appearance.selection)
                           : (hovering ? appearance.hover : .clear)))
        .overlay(alignment: .leading) {
            if selected, let tint {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3, height: 16).padding(.leading, 2)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: Favicon

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

// MARK: - Customize (full color + rename)

private struct CustomizePopover: View {
    @ObservedObject var model: BrowserModel
    let selection: Selection
    @State private var draftName: String
    @State private var color: Color
    @State private var hasColor: Bool
    @EnvironmentObject var appearance: AppearanceStore

    init(model: BrowserModel, selection: Selection, name: String, colorHex: String?) {
        self.model = model
        self.selection = selection
        _draftName = State(initialValue: name)
        _color = State(initialValue: colorHex.flatMap(Color.init(hex:)) ?? .accentColor)
        _hasColor = State(initialValue: colorHex != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Customize Tab").font(.headline)
            HStack {
                Text("Name")
                TextField("Tab name", text: $draftName)
                    .textFieldStyle(.roundedBorder).frame(width: 190)
                    .onSubmit(apply)
            }
            HStack {
                Toggle("Color", isOn: $hasColor)
                Spacer()
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden().disabled(!hasColor)
            }
            HStack {
                Spacer()
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(width: 280)
    }

    private func apply() {
        model.setName(draftName, for: selection)
        model.setColor(hasColor ? color.hex : nil, for: selection)
    }
}

// MARK: - Context menu

private struct TabMenu: View {
    @ObservedObject var model: BrowserModel
    let selection: Selection
    let isFavorite: Bool
    var customize: (() -> Void)? = nil

    var body: some View {
        if let customize { Button("Customize…", action: customize) }
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
    @EnvironmentObject var appearance: AppearanceStore

    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @State private var highlighted = 0

    private var suggestions: [Suggestion] {
        guard addressFocused, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let predictions = model.history.predict(address)
        // If you've clearly started typing a host you visit, that's the answer —
        // lead with it so Return just goes there.
        if let top = predictions.first, model.history.isConfident(address, top) {
            return [.history(top), .navigate(address)] + predictions.dropFirst().map(Suggestion.history)
        }
        return [.navigate(address)] + predictions.map(Suggestion.history)
    }

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model, address: $address, addressFocused: $addressFocused,
                    highlighted: $highlighted, suggestionCount: suggestions.count, activate: activate)
            Divider()
            ZStack(alignment: .top) {
                appearance.windowBG
                if let tab = model.activeTab {
                    TabContent(tab: tab, model: model)
                } else {
                    StartPage(model: model)
                }
                if !suggestions.isEmpty {
                    SuggestionList(model: model, suggestions: suggestions, highlighted: highlighted) { index in
                        highlighted = index; activate()
                    }
                    .padding(.horizontal, 44).padding(.top, 4)
                }
            }
        }
        .onChange(of: model.selection) { sync() }
        .onChange(of: model.activeTab?.urlString) { if !addressFocused { sync() } }
        .onAppear { sync() }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in addressFocused = true }
    }

    private func sync() { address = model.activeTab?.urlString ?? "" }

    private func activate() {
        let list = suggestions
        guard !list.isEmpty else { model.navigate(address); addressFocused = false; return }
        switch list[min(highlighted, list.count - 1)] {
        case .navigate(let q): model.navigate(q)
        case .history(let e): model.navigate(e.url)
        }
        addressFocused = false
        highlighted = 0
    }
}

enum Suggestion: Identifiable {
    case navigate(String)
    case history(HistoryEntry)
    var id: String {
        switch self {
        case .navigate(let q): "go:\(q)"
        case .history(let e): "h:\(e.url)"
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
        }
    }
    private func title(_ s: Suggestion) -> String {
        switch s {
        case .navigate(let q):
            if q.contains(".") && !q.contains(" ") { return "Go to \(q)" }
            return "Search \(model.settings.searchEngine.name) for “\(q)”"
        case .history(let e): return e.title.isEmpty ? e.url : e.title
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
            Text("Rune").font(appearance.font(40, weight: .semibold))
                .foregroundStyle(appearance.contentText.opacity(0.85))
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
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.windowBG)
        .onAppear { focused = true }
    }
}

private struct Toolbar: View {
    @ObservedObject var model: BrowserModel
    @Binding var address: String
    var addressFocused: FocusState<Bool>.Binding
    @Binding var highlighted: Int
    let suggestionCount: Int
    let activate: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 8) {
            button("sidebar.left") { model.sidebarVisible.toggle() }
            button("chevron.left") { model.goBack() }.disabled(!(model.activeTab?.canGoBack ?? false))
            button("chevron.right") { model.goForward() }.disabled(!(model.activeTab?.canGoForward ?? false))
            button(model.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise") { model.reload() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
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

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
    }
}
