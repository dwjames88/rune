import AppKit
import SwiftUI

/// The Finder library window: rail (kinds / folders / tags) · thumbnail grid
/// · inspector. Fully native and appearance-driven.
@MainActor
final class FinderWindowController {
    private var window: NSWindow?
    private let model: BrowserModel
    private let appearance: AppearanceStore

    init(model: BrowserModel, appearance: AppearanceStore) {
        self.model = model
        self.appearance = appearance
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Finder"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.minSize = NSSize(width: 720, height: 440)
            w.center(); w.setFrameAutosaveName("RuneFinder"); w.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: FinderView(model: model, finder: model.finder)
                .overlay(alignment: .topLeading) {
                    TrafficLights().padding(.leading, 12).padding(.top, 10)
                }
                .environmentObject(appearance))
            hosting.sizingOptions = []
            w.contentViewController = hosting
            // Same rule as the browser windows: no invisible titlebar region.
            TitlebarRemover.strip(w)
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌥⌘F toggles; ⌘W in this window closes it instead of a browser tab.
    func toggle() {
        if let w = window, w.isVisible, w.isKeyWindow { w.close() } else { show() }
    }
    var isKey: Bool { window?.isKeyWindow ?? false }
    func close() { window?.close() }
}

struct FinderView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var finder: FinderStore
    @EnvironmentObject var appearance: AppearanceStore

    @State private var query = ""
    @State private var filter = Filter.all
    @State private var selectedID: UUID?
    @State private var toast: String?
    @State private var toastDismiss: Task<Void, Never>?

    enum Filter: Equatable {
        case all, images, videos, starred
        case folder(UUID)
        case tag(String)
    }

    private var filtered: [FinderItem] {
        var items = finder.items
        switch filter {
        case .all: break
        case .images: items = items.filter { $0.kind == .image }
        case .videos: items = items.filter { $0.kind == .video }
        case .starred: items = items.filter { $0.star > 0 }
        case .folder(let id): items = items.filter { $0.folderIDs.contains(id) }
        case .tag(let tag): items = items.filter { $0.tags.contains(tag) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.fileName.lowercased().contains(q) || $0.note.lowercased().contains(q)
                || $0.sourceTitle.lowercased().contains(q) || $0.sourceURL.lowercased().contains(q)
                || $0.tags.contains { $0.contains(q) }
        }
    }

    private var selected: FinderItem? { filtered.first { $0.id == selectedID } ?? finder.items.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(appearance.hairline)
            main
            if let item = selected {
                Divider().overlay(appearance.hairline)
                FinderInspector(finder: finder, item: item, openSource: openSource)
                    .frame(width: 250)
            }
        }
        .background(appearance.windowBG)
        .overlay(alignment: .top) {
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
        .animation(.easeOut(duration: 0.18), value: toast)
        .onReceive(NotificationCenter.default.publisher(for: .finderToast)) { note in
            toast = note.object as? String
            toastDismiss?.cancel()
            toastDismiss = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled { toast = nil }
            }
        }
    }

    private func openSource(_ item: FinderItem) {
        guard let url = URL(string: item.sourceURL) else { return }
        model.newTab(url: url)
        NotificationCenter.default.post(name: .frontBrowserWindow, object: nil)
    }

    // MARK: Rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Clearance for the window's traffic lights, which sit over
                // the rail's top-left corner now that the titlebar is gone.
                Color.clear.frame(height: 18)
                railSection("Library", entries: [
                    ("sparkles.rectangle.stack", "All", Filter.all, finder.items.count),
                    ("photo", "Images", .images, finder.items.filter { $0.kind == .image }.count),
                    ("film", "Videos", .videos, finder.items.filter { $0.kind == .video }.count),
                    ("star", "Starred", .starred, finder.items.filter { $0.star > 0 }.count),
                ])
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Folders").font(appearance.font(11, weight: .semibold))
                            .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                        Spacer()
                        Button { _ = finder.addFolder(name: "New Folder") } label: {
                            Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                    }
                    .padding(.horizontal, 8)
                    ForEach(finder.folders) { folder in
                        FinderFolderRow(finder: finder, folder: folder,
                                        selected: filter == .folder(folder.id)) {
                            filter = filter == .folder(folder.id) ? .all : .folder(folder.id)
                        }
                    }
                }
                if !finder.allTags.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tags").font(appearance.font(11, weight: .semibold))
                            .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                            .padding(.horizontal, 8)
                        ForEach(finder.allTags.prefix(24), id: \.self) { tag in
                            railRow("number", tag, active: filter == .tag(tag), count: nil) {
                                filter = filter == .tag(tag) ? .all : .tag(tag)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 190)
        .background(appearance.sidebarBG)
    }

    private func railSection(_ title: String, entries: [(String, String, Filter, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(appearance.font(11, weight: .semibold))
                .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                .padding(.horizontal, 8)
            ForEach(entries, id: \.1) { icon, label, f, count in
                railRow(icon, label, active: filter == f, count: count) {
                    filter = f
                }
            }
        }
    }

    private func railRow(_ icon: String, _ label: String, active: Bool, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 16)
                    .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                Text(label).font(appearance.font(12)).lineLimit(1)
                    .foregroundStyle(appearance.text(on: appearance.sidebarBG))
                Spacer(minLength: 2)
                if let count {
                    Text("\(count)").font(appearance.font(10)).monospacedDigit()
                        .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .fill(active ? appearance.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Grid

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                        .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                    TextField("Search names, tags, notes, sources", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(appearance.chromeText)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(appearance.windowBG, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius).strokeBorder(appearance.hairline))
                Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                    .font(appearance.font(11)).foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            }
            .padding(10)
            .background(appearance.chrome)
            Divider().overlay(appearance.hairline)

            Group {
                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { item in
                                FinderCard(finder: finder, item: item,
                                           selected: selectedID == item.id,
                                           select: { selectedID = item.id },
                                           open: { openSource(item) })
                            }
                        }
                        .padding(14)
                    }
                }
            }
            // Drag anything in: files from macOS Finder, images/links from
            // other apps or web pages.
            .dropDestination(for: URL.self) { urls, _ in
                Task { @MainActor in
                    var saved = 0
                    for url in urls {
                        if url.isFileURL {
                            if (try? await finder.importFile(url)) != nil { saved += 1 }
                        } else if (try? await finder.save(assetURL: url, sourceURL: url.absoluteString,
                                                          sourceTitle: "")) != nil { saved += 1 }
                    }
                    if saved > 0 {
                        NotificationCenter.default.post(name: .finderToast,
                                                        object: "Saved \(saved) item\(saved == 1 ? "" : "s") to Finder")
                    }
                }
                return true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34))
                .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
            Text(finder.items.isEmpty ? "Nothing saved yet" : "No matches")
                .font(appearance.font(15, weight: .semibold))
                .foregroundStyle(appearance.contentText)
            if finder.items.isEmpty {
                Text("Right-click any image → Save to Rune Finder\n⌥S saves the image under your cursor · ⇧⌘S collects a whole page")
                    .font(appearance.font(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid card

private struct FinderCard: View {
    @ObservedObject var finder: FinderStore
    let item: FinderItem
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: appearance.cornerRadius)
                    .fill(appearance.chrome)
                if let thumb = finder.thumbnail(for: item) {
                    Image(nsImage: thumb).resizable().scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
                } else {
                    Image(systemName: item.kind == .video ? "film" : "doc")
                        .font(.system(size: 26))
                        .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                }
                if item.kind == .video {
                    Image(systemName: "play.circle.fill").font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 3)
                }
            }
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .strokeBorder(selected ? appearance.accent : appearance.hairline, lineWidth: selected ? 2 : 1))

            Text(item.fileName).font(appearance.font(11)).lineLimit(1)
                .foregroundStyle(appearance.contentText)
            HStack(spacing: 4) {
                if item.star > 0 {
                    Image(systemName: "star.fill").font(.system(size: 8))
                        .foregroundStyle(appearance.accent)
                    Text("\(item.star)").font(appearance.font(9))
                        .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                }
                ForEach(item.tags.prefix(2), id: \.self) { tag in
                    Text(tag).font(appearance.font(9))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(appearance.hover, in: Capsule())
                        .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .onTapGesture { select() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open Source Page") { open() }
            Button("Reveal in macOS Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([finder.fileURL(for: item)])
            }
            Divider()
            Button(item.star > 0 ? "Remove Star" : "Star") {
                var updated = item; updated.star = item.star > 0 ? 0 : 5; finder.update(updated)
            }
            Divider()
            Button("Move to Trash", role: .destructive) { finder.trash(item) }
        }
    }
}

// MARK: - Folder row

private struct FinderFolderRow: View {
    @ObservedObject var finder: FinderStore
    let folder: FinderFolder
    let selected: Bool
    let toggle: () -> Void
    @EnvironmentObject var appearance: AppearanceStore
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        Group {
            if renaming {
                TextField("Folder name", text: $draft, onCommit: {
                    finder.renameFolder(folder.id, to: draft); renaming = false
                })
                .textFieldStyle(.plain).font(appearance.font(12))
                .padding(.horizontal, 8).frame(height: 26)
            } else {
                Button(action: toggle) {
                    HStack(spacing: 7) {
                        Image(systemName: folder.icon).font(.system(size: 11)).frame(width: 16)
                            .foregroundStyle(appearance.secondaryText(on: appearance.sidebarBG))
                        Text(folder.name).font(appearance.font(12)).lineLimit(1)
                            .foregroundStyle(appearance.text(on: appearance.sidebarBG))
                        Spacer(minLength: 2)
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: appearance.cornerRadius)
                        .fill(selected ? appearance.selection : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") { draft = folder.name; renaming = true }
                    Button("Delete Folder", role: .destructive) { finder.deleteFolder(folder.id) }
                }
            }
        }
    }
}

// MARK: - Inspector

private struct FinderInspector: View {
    @ObservedObject var finder: FinderStore
    let item: FinderItem
    let openSource: (FinderItem) -> Void
    @EnvironmentObject var appearance: AppearanceStore

    @State private var name = ""
    @State private var tagsText = ""
    @State private var note = ""
    @State private var newCustomKey = ""
    @State private var newCustomValue = ""
    // Edits save themselves: debounced while typing, flushed when switching
    // items or closing. `editingID` pins drafts to the item they belong to so
    // switching selection mid-edit never writes onto the wrong item.
    @State private var editingID: UUID?
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let thumb = finder.thumbnail(for: item) {
                    Image(nsImage: thumb).resizable().scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
                }
                TextField("Name", text: $name, onCommit: commit)
                    .textFieldStyle(.plain).font(appearance.font(14, weight: .semibold))
                    .foregroundStyle(appearance.contentText)

                // Stars
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { i in
                        Button {
                            var updated = item; updated.star = item.star == i ? 0 : i; finder.update(updated)
                        } label: {
                            Image(systemName: i <= item.star ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(i <= item.star ? appearance.accent
                                                                : appearance.secondaryText(on: appearance.windowBG))
                        }
                        .buttonStyle(.plain)
                    }
                }

                labeled("Tags") {
                    TextField("comma, separated", text: $tagsText, onCommit: commit)
                        .textFieldStyle(.plain).font(appearance.font(12))
                }
                labeled("Note") {
                    TextField("Why it's saved…", text: $note, axis: .vertical)
                        .textFieldStyle(.plain).font(appearance.font(12))
                        .lineLimit(2...5)
                        .onSubmit(commit)
                }

                if !finder.folders.isEmpty {
                    labeled("Folders") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(finder.folders) { folder in
                                Toggle(folder.name, isOn: folderBinding(folder.id))
                                    .toggleStyle(.checkbox).font(appearance.font(12))
                            }
                        }
                    }
                }

                labeled("Custom Fields") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.custom.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(spacing: 6) {
                                Text(key).font(appearance.font(11, weight: .semibold))
                                Text(value).font(appearance.font(11)).lineLimit(1)
                                Spacer()
                                Button {
                                    var updated = item; updated.custom.removeValue(forKey: key); finder.update(updated)
                                } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                        }
                        HStack(spacing: 6) {
                            TextField("field", text: $newCustomKey).font(appearance.font(11))
                            TextField("value", text: $newCustomValue).font(appearance.font(11))
                            Button {
                                let k = newCustomKey.trimmingCharacters(in: .whitespaces)
                                guard !k.isEmpty else { return }
                                var updated = item; updated.custom[k] = newCustomValue; finder.update(updated)
                                newCustomKey = ""; newCustomValue = ""
                            } label: { Image(systemName: "plus").font(.system(size: 9)) }
                            .buttonStyle(.plain)
                        }
                        .textFieldStyle(.plain)
                    }
                }

                // Dominant colors
                if !item.colors.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.colors, id: \.self) { hexColor in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: hexColor) ?? .gray)
                                .frame(width: 22, height: 22)
                                .help(hexColor)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let w = item.width, let h = item.height {
                        meta("\(w) × \(h) · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))")
                    } else {
                        meta(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                    }
                    meta("Saved \(item.addedAt.formatted(date: .abbreviated, time: .shortened))")
                    if !item.sourceURL.isEmpty {
                        Button {
                            openSource(item)
                        } label: {
                            Label(item.sourceTitle.isEmpty ? item.sourceURL : item.sourceTitle,
                                  systemImage: "arrow.up.forward")
                                .font(appearance.font(11)).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appearance.accent)
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(14)
        }
        .background(appearance.windowBG)
        .onAppear(perform: load)
        .onChange(of: item.id) { commit(); load() }
        .onChange(of: name) { scheduleCommit() }
        .onChange(of: tagsText) { scheduleCommit() }
        .onChange(of: note) { scheduleCommit() }
        .onDisappear { commit() }
    }

    private func load() {
        commitTask?.cancel()
        editingID = item.id
        name = item.fileName
        tagsText = item.tags.joined(separator: ", ")
        note = item.note
    }

    private func scheduleCommit() {
        guard editingID == item.id else { return }   // load() itself changed the fields
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            if !Task.isCancelled { commit() }
        }
    }

    /// Writes drafts back to the item they were loaded from — never the one
    /// currently displayed (they differ when the user just switched).
    private func commit() {
        commitTask?.cancel()
        guard let id = editingID, var updated = finder.items.first(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        updated.fileName = trimmedName.isEmpty ? updated.fileName : trimmedName
        updated.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        updated.note = note
        finder.update(updated)
    }

    private func folderBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { item.folderIDs.contains(id) },
            set: { on in
                var updated = item
                updated.folderIDs.removeAll { $0 == id }
                if on { updated.folderIDs.append(id) }
                finder.update(updated)
            })
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(appearance.font(10, weight: .semibold))
                .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
            content()
        }
    }

    private func meta(_ s: String) -> some View {
        Text(s).font(appearance.font(10))
            .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
    }
}

// MARK: - Batch collect sheet

struct CollectSheet: View {
    @ObservedObject var model: BrowserModel
    let candidates: [CollectCandidate]
    @EnvironmentObject var appearance: AppearanceStore

    @State private var picked: Set<String> = []
    @State private var tagsText = ""
    @State private var previews: [String: NSImage] = [:]
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Collect from this page").font(appearance.font(14, weight: .semibold))
                Spacer()
                Button(picked.count == candidates.count ? "Select None" : "Select All") {
                    picked = picked.count == candidates.count ? [] : Set(candidates.map(\.id))
                }
                .font(appearance.font(11))
                Button { model.collectCandidates = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            Divider().overlay(appearance.hairline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(candidates) { c in
                        candidateCell(c)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 380)

            Divider().overlay(appearance.hairline)
            HStack(spacing: 8) {
                TextField("tags for all (comma, separated)", text: $tagsText)
                    .textFieldStyle(.plain).font(appearance.font(12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(appearance.windowBG, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius).strokeBorder(appearance.hairline))
                Button(saving ? "Saving…" : "Save \(picked.count)") { saveAll() }
                    .disabled(picked.isEmpty || saving)
                    .keyboardShortcut(.return)
            }
            .padding(12)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .onAppear { picked = Set(candidates.prefix(20).map(\.id)) }
    }

    private func candidateCell(_ c: CollectCandidate) -> some View {
        let on = picked.contains(c.id)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = previews[c.id] {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(appearance.hover)
                        .overlay(ProgressView().controlSize(.small).scaleEffect(0.5))
                        .task {
                            guard previews[c.id] == nil, let url = URL(string: c.src),
                                  let (data, _) = try? await URLSession.shared.data(from: url),
                                  let img = NSImage(data: data) else { return }
                            previews[c.id] = img
                        }
                }
            }
            .frame(width: 110, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(on ? appearance.accent : appearance.hairline, lineWidth: on ? 2 : 1))
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(on ? appearance.accent : .white.opacity(0.85))
                .shadow(radius: 2)
                .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if on { picked.remove(c.id) } else { picked.insert(c.id) }
        }
        .help(c.w > 0 ? "\(c.w) × \(c.h)" : c.src)
    }

    private func saveAll() {
        saving = true
        let tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        let chosen = candidates.filter { picked.contains($0.id) }
        let webView = model.activeTab?.webView
        Task { @MainActor in
            var saved = 0
            for c in chosen {
                if let url = URL(string: c.src) {
                    model.saveToFinder(assetURL: url, from: webView, tags: tags, quiet: true)
                    saved += 1
                }
            }
            NotificationCenter.default.post(name: .finderToast, object: "Saving \(saved) items to Finder")
            model.collectCandidates = nil
        }
    }
}
