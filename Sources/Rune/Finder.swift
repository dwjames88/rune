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
        // Same asset saved twice returns the existing item — every capture
        // path (context menu, ⌥S, batch, Services) gets dupe protection.
        if let existing = items.first(where: { $0.assetURL == assetURL.absoluteString }) {
            return existing
        }
        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh) Rune/0.1", forHTTPHeaderField: "User-Agent")
        // Pages often gate assets by referer — claim the page we came from.
        if !sourceURL.isEmpty { request.setValue(sourceURL, forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return try await save(data: data,
                              ext: Self.fileExtension(for: assetURL, response: response),
                              fileName: Self.displayName(for: assetURL, title: sourceTitle),
                              sourceURL: sourceURL, sourceTitle: sourceTitle, tags: tags,
                              assetURL: assetURL.absoluteString, folderIDs: folderIDs)
    }

    /// Import a local file (macOS Service, dock drop, window drop). The
    /// original is copied in; the source stays untouched.
    @discardableResult
    func importFile(_ url: URL) async throws -> FinderItem {
        // Read off the main actor — this can be a movie on a slow disk.
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
        return try await save(data: data, ext: ext,
                              fileName: url.deletingPathExtension().lastPathComponent,
                              sourceURL: url.absoluteString, sourceTitle: "")
    }

    /// Save a text snippet (Service: selected text anywhere in macOS).
    @discardableResult
    func saveText(_ text: String) async throws -> FinderItem {
        let name = text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? "Snippet"
        return try await save(data: Data(text.utf8), ext: "txt",
                              fileName: name, sourceURL: "", sourceTitle: "")
    }

    /// The one save pipeline. Every capture path above funnels into here —
    /// two copies of this used to drift, and the image work now happens off
    /// the main actor where a 40-megapixel capture can't stall the UI.
    @discardableResult
    func save(data: Data, ext: String, fileName: String, sourceURL: String, sourceTitle: String,
              tags: [String] = [], assetURL: String = "", folderIDs: [UUID] = []) async throws -> FinderItem {
        var item = FinderItem(fileName: fileName, ext: ext, kind: Self.kind(forExtension: ext),
                              sourceURL: sourceURL, assetURL: assetURL)
        item.sourceTitle = sourceTitle
        item.tags = tags
        item.folderIDs = folderIDs
        item.byteSize = data.count
        let folder = dir(for: item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: item), options: .atomic)
        if item.kind == .image, let analysis = await Task.detached(operation: { Self.analyzeImage(data) }).value {
            item.width = analysis.width
            item.height = analysis.height
            item.colors = analysis.colors
            if let png = analysis.thumbPNG {
                try? png.write(to: thumbURL(for: item), options: .atomic)
            }
        }
        writeMetadata(item)
        items.insert(item, at: 0)
        return item
    }

    /// Decode, measure, bucket colors, thumbnail — everything worth knowing
    /// about an image, computed away from the main actor. The NSImage never
    /// escapes; only value types come back.
    private nonisolated static func analyzeImage(_ data: Data)
        -> (width: Int?, height: Int?, colors: [String], thumbPNG: Data?)? {
        guard let image = NSImage(data: data) else { return nil }
        let pixels = image.representations.first.map { ($0.pixelsWide, $0.pixelsHigh) }
        return (pixels?.0, pixels?.1, dominantColors(of: image),
                thumbnail(of: image, maxDimension: 512)?.png)
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
    func autoTag(_ item: FinderItem, using ai: AIService) async {
        guard ai.isAvailable else { return }
        let context = "File: \(item.fileName).\(item.ext)\nFrom page: \(item.sourceTitle)\nPage URL: \(item.sourceURL)"
        guard let answer = try? await ai.complete(
            system: "You tag saved design inspiration for later retrieval. Reply with ONLY 2-4 short "
                + "lowercase tags, comma-separated. Concrete subjects and styles, no filler words.",
            user: context, maxTokens: 30, effort: .low) else { return }
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

    /// File an item into a folder (membership is metadata; the file never moves).
    func file(_ itemID: UUID, into folderID: UUID) {
        guard var item = items.first(where: { $0.id == itemID }),
              !item.folderIDs.contains(folderID) else { return }
        item.folderIDs.append(folderID)
        update(item)
    }

    func remove(_ itemID: UUID, from folderID: UUID) {
        guard var item = items.first(where: { $0.id == itemID }) else { return }
        item.folderIDs.removeAll { $0 == folderID }
        update(item)
    }

    func count(in folderID: UUID) -> Int {
        items.count { $0.folderIDs.contains(folderID) }
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

    nonisolated static func thumbnail(of image: NSImage, maxDimension: CGFloat) -> NSImage? {
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
    nonisolated static func dominantColors(of image: NSImage, count: Int = 3) -> [String] {
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
    /// What the last right-click landed on. Either half can be missing — a bare
    /// image has no link, a text link has no media, a linked image has both.
    struct ContextTarget {
        var media: URL?
        var kind: FinderItem.Kind
        var link: URL?
        var at: Date
    }

    var contextTarget: ContextTarget?
    var onSaveToFinder: ((URL, FinderItem.Kind) -> Void)?
    var onDownload: ((URL) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // A stale target means this right-click landed somewhere else.
        guard let target = contextTarget, Date().timeIntervalSince(target.at) < 2 else { return }

        // WebKit's own download items build a WKDownload it only hands back
        // through private API, so out of the box they do nothing at all: you
        // click Download Image and the click goes in the bin. We already know
        // what's under the cursor, so point them at Rune's download path.
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierDownloadMedia":
                redirect(item, to: target.media)
            case "WKMenuItemIdentifierDownloadLinkedFile":
                redirect(item, to: target.link)
            default: break
            }
        }

        guard let media = target.media else { return }
        let title = target.kind == .video ? "Save Video to Rune" : "Save Image to Rune"
        let item = NSMenuItem(title: title, action: #selector(saveContextTarget(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = media
        item.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    /// Leave the item alone if we don't know its URL: an item that does nothing
    /// is bad, but one that downloads the wrong thing is worse.
    private func redirect(_ item: NSMenuItem, to url: URL?) {
        guard let url else { return }
        item.target = self
        item.action = #selector(downloadRepresented(_:))
        item.representedObject = url
    }

    @objc private func downloadRepresented(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onDownload?(url)
    }

    @objc private func saveContextTarget(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let target = contextTarget else { return }
        onSaveToFinder?(url, target.kind)
    }
}


// MARK: - Quick Action installer

/// Ships the "Save to Rune" Quick Action: a tiny Automator workflow in
/// ~/Library/Services that funnels right-clicked files into Rune via
/// `open -a`. Installed on launch when missing. macOS ships new Quick
/// Actions disabled — enable once in System Settings ▸ General ▸ Login
/// Items & Extensions ▸ Finder.
enum FinderQuickAction {
    static let version = 1

    static func installIfNeeded() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Save to Rune.workflow/Contents")
        let marker = dir.appendingPathComponent("com.dwjames.rune.version")
        if let v = try? String(contentsOf: marker, encoding: .utf8), Int(v) == version { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try infoPlist.write(to: dir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            try documentWflow.write(to: dir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
            try String(version).write(to: marker, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Rune: quick action install failed — %@", error.localizedDescription)
        }
    }

    private static let infoPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key><string>background</string>
			<key>NSIconName</key><string>NSTouchBarBookmarksTemplate</string>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Save to Rune</string></dict>
			<key>NSMessage</key><string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict><key>NSServiceCategory</key><string>public.item</string></dict>
			<key>NSSendFileTypes</key>
			<array><string>public.item</string></array>
		</dict>
	</array>
</dict>
</plist>
"""

    private static let documentWflow = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key><string>528</string>
	<key>AMApplicationVersion</key><string>2.10</string>
	<key>AMDocumentVersion</key><string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>container</key><string>List</string>
					<key>optional</key><true/>
					<key>types</key><array><string>com.apple.cocoa.string</string></array>
				</dict>
				<key>AMActionVersion</key><string>2.0.3</string>
				<key>AMApplication</key><array><string>Automator</string></array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key><dict/>
					<key>CheckedForUserDefaultShell</key><dict/>
					<key>inputMethod</key><dict/>
					<key>shell</key><dict/>
					<key>source</key><dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>container</key><string>List</string>
					<key>types</key><array><string>com.apple.cocoa.string</string></array>
				</dict>
				<key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key><string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key><string>for f in "$@"; do /usr/bin/open -a Rune "$f"; done</string>
					<key>CheckedForUserDefaultShell</key><true/>
					<key>inputMethod</key><integer>1</integer>
					<key>shell</key><string>/bin/zsh</string>
					<key>source</key><string></string>
				</dict>
				<key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key><string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key><false/>
				<key>CanShowWhenRun</key><true/>
				<key>Category</key><array><string>AMCategoryUtilities</string></array>
				<key>Class Name</key><string>RunShellScriptAction</string>
				<key>InputUUID</key><string>8B4A0C3E-1D2F-4E5A-9B6C-7D8E9F0A1B2C</string>
				<key>Keywords</key><array><string>Shell</string></array>
				<key>OutputUUID</key><string>9C5B1D4F-2E3A-4F6B-8C7D-8E9F0A1B2C3D</string>
				<key>UUID</key><string>7A3F9B2D-0C1E-4D5F-8A6B-6C7D8E9F0A1B</string>
				<key>UnlocalizedApplications</key><array><string>Automator</string></array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key><integer>0</integer>
						<key>name</key><string>inputMethod</string>
						<key>required</key><string>0</string>
						<key>type</key><string>0</string>
						<key>uuid</key><string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key><false/>
						<key>name</key><string>CheckedForUserDefaultShell</string>
						<key>required</key><string>0</string>
						<key>type</key><string>0</string>
						<key>uuid</key><string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key><string></string>
						<key>name</key><string>source</string>
						<key>required</key><string>0</string>
						<key>type</key><string>0</string>
						<key>uuid</key><string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key><string></string>
						<key>name</key><string>COMMAND_STRING</string>
						<key>required</key><string>0</string>
						<key>type</key><string>0</string>
						<key>uuid</key><string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key><string>/bin/sh</string>
						<key>name</key><string>shell</string>
						<key>required</key><string>0</string>
						<key>type</key><string>0</string>
						<key>uuid</key><string>4</string>
					</dict>
				</dict>
			</dict>
		</dict>
	</array>
	<key>connectors</key><dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key><dict/>
		<key>applicationPaths</key><array/>
		<key>inputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
		<key>presentationMode</key><integer>15</integer>
		<key>processesInput</key><integer>0</integer>
		<key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key><integer>0</integer>
		<key>systemImageName</key><string>NSActionTemplate</string>
		<key>useAutomaticInputType</key><integer>0</integer>
		<key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
"""
}
