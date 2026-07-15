import AppKit
import UniformTypeIdentifiers
import WebKit

/// The Finder: Rune's built-in inspiration library (see FINDER.md).
/// Eagle-style on-disk layout — one folder per item holding the untouched
/// original, a generated thumbnail, and a self-describing item.json. Folder
/// membership is metadata, so an item can live in many folders; the file
/// never moves. Lose the index and the items still describe themselves.
struct FinderItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case image, video, audio, page, other
    }

    var id = UUID()
    var fileName: String              // display name, editable
    var ext: String
    var kind: Kind
    var sourceURL: String             // page it was saved from
    var sourceTitle: String = ""
    var assetURL: String              // direct URL of the asset
    var tags: [String] = []
    var folderIDs: [UUID] = []        // virtual, multi-membership
    var note: String = ""
    var star: Int = 0                 // 0–5
    var width: Int?
    var height: Int?
    var colors: [String] = []         // dominant hex colors
    var addedAt = Date()
    var byteSize: Int = 0
    var custom: [String: String] = [:]  // user-defined fields

    // Tolerant decoding, same rationale as Appearance: adding fields must
    // never invalidate an existing library.
    enum CodingKeys: String, CodingKey {
        case id, fileName, ext, kind, sourceURL, sourceTitle, assetURL
        case tags, folderIDs, note, star, width, height, colors, addedAt, byteSize, custom
    }

    init(fileName: String, ext: String, kind: Kind, sourceURL: String, assetURL: String) {
        self.fileName = fileName; self.ext = ext; self.kind = kind
        self.sourceURL = sourceURL; self.assetURL = assetURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? "Untitled"
        ext = try c.decodeIfPresent(String.self, forKey: .ext) ?? ""
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .other
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        assetURL = try c.decodeIfPresent(String.self, forKey: .assetURL) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        folderIDs = try c.decodeIfPresent([UUID].self, forKey: .folderIDs) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        star = try c.decodeIfPresent(Int.self, forKey: .star) ?? 0
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? []
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
        custom = try c.decodeIfPresent([String: String].self, forKey: .custom) ?? [:]
    }
}

struct FinderFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "folder"
    var parentID: UUID?
}

@MainActor
final class FinderStore: ObservableObject {
    @Published private(set) var items: [FinderItem] = []
    @Published var folders: [FinderFolder] = []

    /// Library root. Default lives next to Rune's other state; a custom
    /// location (iCloud Drive, Dropbox) is a supported setting.
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Storage.url("Finder")
        try? FileManager.default.createDirectory(at: itemsDir, withIntermediateDirectories: true)
        folders = Storage.loadJSON([FinderFolder].self, from: "Finder/folders.json") ?? []
        loadIndex()
    }

    private var itemsDir: URL { root.appendingPathComponent("items") }
    private func dir(for id: UUID) -> URL { itemsDir.appendingPathComponent(id.uuidString) }
    func fileURL(for item: FinderItem) -> URL {
        dir(for: item.id).appendingPathComponent("original.\(item.ext)")
    }
    func thumbURL(for item: FinderItem) -> URL {
        dir(for: item.id).appendingPathComponent("thumb.png")
    }

    /// Build the in-memory index by scanning item.json files. The metadata is
    /// the source of truth on disk; this is just a view of it.
    private func loadIndex() {
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(at: itemsDir, includingPropertiesForKeys: nil) else { return }
        var loaded: [FinderItem] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for folder in ids {
            let meta = folder.appendingPathComponent("item.json")
            if let data = try? Data(contentsOf: meta),
               let item = try? decoder.decode(FinderItem.self, from: data) {
                loaded.append(item)
            }
        }
        items = loaded.sorted { $0.addedAt > $1.addedAt }
    }

    private func writeMetadata(_ item: FinderItem) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(item) {
            try? data.write(to: dir(for: item.id).appendingPathComponent("item.json"), options: .atomic)
        }
    }

    // MARK: Save pipeline

    /// Download an asset and add it to the library. Returns the saved item.
    @discardableResult
    func save(assetURL: URL, sourceURL: String, sourceTitle: String,
              tags: [String] = [], folderIDs: [UUID] = []) async throws -> FinderItem {
        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh) Rune/0.1", forHTTPHeaderField: "User-Agent")
        // Pages often gate assets by referer — claim the page we came from.
        if !sourceURL.isEmpty { request.setValue(sourceURL, forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: request)

        let ext = Self.fileExtension(for: assetURL, response: response)
        let kind = Self.kind(forExtension: ext)
        var item = FinderItem(fileName: Self.displayName(for: assetURL, title: sourceTitle),
                              ext: ext, kind: kind,
                              sourceURL: sourceURL, assetURL: assetURL.absoluteString)
        item.sourceTitle = sourceTitle
        item.tags = tags
        item.folderIDs = folderIDs
        item.byteSize = data.count

        let folder = dir(for: item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: item), options: .atomic)

        if kind == .image, let image = NSImage(data: data) {
            let pixels = image.representations.first.map { ($0.pixelsWide, $0.pixelsHigh) }
            item.width = pixels?.0
            item.height = pixels?.1
            item.colors = Self.dominantColors(of: image)
            if let thumb = Self.thumbnail(of: image, maxDimension: 512),
               let png = thumb.png {
                try? png.write(to: thumbURL(for: item), options: .atomic)
            }
        }

        writeMetadata(item)
        items.insert(item, at: 0)
        return item
    }

    /// Save raw data directly (page snapshots, dropped files). Same pipeline,
    /// no download step.
    @discardableResult
    func save(data: Data, ext: String, fileName: String, sourceURL: String, sourceTitle: String,
              tags: [String] = []) async throws -> FinderItem {
        var item = FinderItem(fileName: fileName, ext: ext, kind: Self.kind(forExtension: ext),
                              sourceURL: sourceURL, assetURL: "")
        item.sourceTitle = sourceTitle
        item.tags = tags
        item.byteSize = data.count
        let folder = dir(for: item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: item), options: .atomic)
        if item.kind == .image, let image = NSImage(data: data) {
            let pixels = image.representations.first.map { ($0.pixelsWide, $0.pixelsHigh) }
            item.width = pixels?.0; item.height = pixels?.1
            item.colors = Self.dominantColors(of: image)
            if let thumb = Self.thumbnail(of: image, maxDimension: 512), let png = thumb.png {
                try? png.write(to: thumbURL(for: item), options: .atomic)
            }
        }
        writeMetadata(item)
        items.insert(item, at: 0)
        return item
    }

    // MARK: Thumbnails (decoded once, cached — same rationale as FaviconCache)

    private let thumbCache = NSCache<NSString, NSImage>()

    func thumbnail(for item: FinderItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let hit = thumbCache.object(forKey: key) { return hit }
        let url = FileManager.default.fileExists(atPath: thumbURL(for: item).path)
            ? thumbURL(for: item) : fileURL(for: item)
        guard let img = NSImage(contentsOf: url) else { return nil }
        thumbCache.setObject(img, forKey: key)
        return img
    }

    // MARK: Claude auto-tagging (optional, text-only — cheap and fast)

    /// Suggest tags from the item's context and merge them in. Fails silently;
    /// tagging is a convenience, never a blocker.
    func autoTag(_ item: FinderItem, using claude: ClaudeService) async {
        guard claude.hasKey else { return }
        let context = "File: \(item.fileName).\(item.ext)\nFrom page: \(item.sourceTitle)\nPage URL: \(item.sourceURL)"
        guard let answer = try? await claude.complete(
            system: "You tag saved design inspiration for later retrieval. Reply with ONLY 2-4 short "
                + "lowercase tags, comma-separated. Concrete subjects and styles, no filler words.",
            user: context, maxTokens: 30, effort: "low") else { return }
        let suggested = answer.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count < 30 }
        guard !suggested.isEmpty, var current = items.first(where: { $0.id == item.id }) else { return }
        current.tags = Array(Set(current.tags).union(suggested)).sorted()
        update(current)
    }

    // MARK: Metadata edits

    func update(_ item: FinderItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        writeMetadata(item)
    }

    /// Remove from the library; the item folder goes to the system Trash, so
    /// nothing is ever destroyed outright.
    func trash(_ item: FinderItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.trashItem(at: dir(for: item.id), resultingItemURL: nil)
    }

    /// Every tag in use, most common first — feeds tag suggestions.
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for item in items { for tag in item.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: Folders

    @discardableResult
    func addFolder(name: String, parentID: UUID? = nil) -> FinderFolder {
        let folder = FinderFolder(name: name, parentID: parentID)
        folders.append(folder)
        persistFolders()
        return folder
    }
    func persistFolders() { Storage.saveJSON(folders, to: "Finder/folders.json") }

    func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name; persistFolders()
    }
    /// Delete a folder; items keep existing (membership is just metadata).
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for var item in items where item.folderIDs.contains(id) {
            item.folderIDs.removeAll { $0 == id }
            update(item)
        }
        persistFolders()
    }

    // MARK: Asset analysis (all native)

    static func fileExtension(for url: URL, response: URLResponse) -> String {
        let fromURL = url.pathExtension.lowercased()
        if !fromURL.isEmpty, fromURL.count <= 5 { return fromURL }
        if let mime = response.mimeType, let type = UTType(mimeType: mime),
           let ext = type.preferredFilenameExtension { return ext }
        return "bin"
    }

    static func kind(forExtension ext: String) -> FinderItem.Kind {
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .html) { return .page }
        return .other
    }

    static func displayName(for url: URL, title: String) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
            .removingPercentEncoding ?? ""
        if stem.count > 2, stem.count < 80 { return stem }
        return title.isEmpty ? "Untitled" : title
    }

    static func thumbnail(of image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }

    /// Up to three dominant colors: downsample to a tiny bitmap, quantize,
    /// count buckets. Crude but dependency-free and plenty for filtering.
    static func dominantColors(of image: NSImage, count: Int = 3) -> [String] {
        guard let small = thumbnail(of: image, maxDimension: 24),
              let tiff = small.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return [] }
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                let r = Int(c.redComponent * 255), g = Int(c.greenComponent * 255), b = Int(c.blueComponent * 255)
                let key = (r / 32) << 10 | (g / 32) << 5 | (b / 32)   // 8 levels per channel
                let cur = buckets[key] ?? (0, 0, 0, 0)
                buckets[key] = (cur.n + 1, cur.r + r, cur.g + g, cur.b + b)
            }
        }
        return buckets.values.sorted { $0.n > $1.n }.prefix(count).map {
            String(format: "#%02X%02X%02X", $0.r / $0.n, $0.g / $0.n, $0.b / $0.n)
        }
    }
}

/// A page asset found by batch collect.
struct CollectCandidate: Codable, Identifiable, Equatable {
    var src: String
    var w: Int
    var h: Int
    var kind: String
    var id: String { src }
}

// MARK: - Capture (context menu)

/// WKWebView subclass that adds "Save to Rune Finder" to the page context
/// menu. The PageBridge posts the media element under the cursor on
/// `contextmenu`; the coordinator stashes it here just before the menu opens.
final class RuneWebView: WKWebView {
    struct ContextTarget {
        var url: URL
        var kind: FinderItem.Kind
        var at: Date
    }

    var contextTarget: ContextTarget?
    var onSaveToFinder: ((URL, FinderItem.Kind) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // Only offer the item when the bridge reported fresh media — a stale
        // target means this right-click landed somewhere else.
        guard let target = contextTarget, Date().timeIntervalSince(target.at) < 2 else { return }
        let title = target.kind == .video ? "Save Video to Rune Finder" : "Save Image to Rune Finder"
        let item = NSMenuItem(title: title, action: #selector(saveContextTarget), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func saveContextTarget() {
        guard let target = contextTarget else { return }
        onSaveToFinder?(target.url, target.kind)
    }
}
