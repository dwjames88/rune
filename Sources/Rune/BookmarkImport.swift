import AppKit
import UniformTypeIdentifiers

/// One-time migration: read Safari's or Chrome's bookmarks and fold them into
/// Rune's pinned shelf. Both are plain files on disk — no scripting, no
/// automation permission, nothing to install.
enum BookmarkImport {

    /// A bookmark tree, normalised across sources: a node is either a link
    /// (`url` set) or a folder (`children` set).
    struct Node {
        var name: String
        var url: String?
        var children: [Node] = []
    }

    enum Source: String, CaseIterable, Identifiable {
        case safari, chrome
        var id: String { rawValue }
        var label: String { self == .safari ? "Safari" : "Chrome" }

        /// Where each browser keeps the file by default.
        var path: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .safari: return home.appendingPathComponent("Library/Safari/Bookmarks.plist")
            case .chrome: return home.appendingPathComponent(
                "Library/Application Support/Google/Chrome/Default/Bookmarks")
            }
        }
    }

    enum Failure: LocalizedError {
        case cancelled
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: "Import cancelled."
            case .unreadable(let name): "Couldn't read \(name)'s bookmarks — the file wasn't in a format Rune understands."
            }
        }
    }

    // MARK: Reading

    /// Read a browser's bookmark file. macOS keeps ~/Library/Safari behind Full
    /// Disk Access, so when the direct read is refused we ask for the file
    /// through an open panel instead — choosing it grants access, which is a
    /// far smaller ask than handing Rune your whole disk.
    @MainActor
    static func load(from source: Source) async throws -> [Node] {
        if let data = try? Data(contentsOf: source.path) {
            return try parse(data, from: source)
        }
        guard let url = await pickFile(for: source) else { throw Failure.cancelled }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(source.label) }
        return try parse(data, from: source)
    }

    @MainActor
    private static func pickFile(for source: Source) async -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Rune needs permission to read \(source.label)'s bookmarks. "
            + "Choose the highlighted file to allow it."
        panel.prompt = "Import"
        panel.directoryURL = source.path.deletingLastPathComponent()
        panel.nameFieldStringValue = source.path.lastPathComponent
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        return await panel.begin() == .OK ? panel.url : nil
    }

    static func parse(_ data: Data, from source: Source) throws -> [Node] {
        switch source {
        case .safari: return try parseSafari(data)
        case .chrome: return try parseChrome(data)
        }
    }

    // MARK: Safari (property list)

    private static func parseSafari(_ data: Data) throws -> [Node] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = root as? [String: Any] else { throw Failure.unreadable("Safari") }
        return safariNodes(dict["Children"] as? [[String: Any]] ?? [])
    }

    private static func safariNodes(_ items: [[String: Any]]) -> [Node] {
        items.compactMap { item in
            switch item["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                guard let url = item["URLString"] as? String else { return nil }
                let title = (item["URIDictionary"] as? [String: Any])?["title"] as? String
                return Node(name: title ?? url, url: url)
            case "WebBookmarkTypeList":
                let raw = item["Title"] as? String ?? "Bookmarks"
                return Node(name: safariTitle(raw), url: nil,
                            children: safariNodes(item["Children"] as? [[String: Any]] ?? []))
            default:
                return nil   // proxies, reading list, etc.
            }
        }
    }

    /// Safari's internal names for its two built-in lists.
    private static func safariTitle(_ raw: String) -> String {
        switch raw {
        case "BookmarksBar": "Favorites"
        case "BookmarksMenu": "Bookmarks Menu"
        default: raw
        }
    }

    // MARK: Chrome (JSON)

    private static func parseChrome(_ data: Data) throws -> [Node] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { throw Failure.unreadable("Chrome") }
        return ["bookmark_bar", "other", "synced"].compactMap {
            (roots[$0] as? [String: Any]).flatMap(chromeNode)
        }
    }

    private static func chromeNode(_ dict: [String: Any]) -> Node? {
        let name = dict["name"] as? String ?? ""
        if dict["type"] as? String == "url" {
            guard let url = dict["url"] as? String else { return nil }
            return Node(name: name.isEmpty ? url : name, url: url)
        }
        let children = (dict["children"] as? [[String: Any]] ?? []).compactMap(chromeNode)
        return children.isEmpty ? nil : Node(name: name, url: nil, children: children)
    }
}

extension BrowserModel {
    /// Fold an imported tree into the pinned shelf. URLs you already have are
    /// skipped, so importing twice doesn't double your sidebar. Returns how
    /// many were actually added.
    @discardableResult
    func importBookmarks(_ nodes: [BookmarkImport.Node]) -> Int {
        var added = 0
        var seen = Set(pinned.map(\.url)).union(favorites.map(\.url))

        func folder(named name: String) -> UUID {
            if let match = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return match.id
            }
            return addFolder(name: name).id
        }

        func walk(_ node: BookmarkImport.Node, into parent: UUID?) {
            if let url = node.url {
                guard url.hasPrefix("http"), seen.insert(url).inserted else { return }
                pinned.append(SavedTab(url: url, name: node.name, customName: true, folderID: parent))
                added += 1
                return
            }
            // Rune's shelf is one level deep, so a folder only becomes a real
            // folder if it directly holds links; nesting below that flattens in.
            let target = node.children.contains { $0.url != nil } ? folder(named: node.name) : parent
            for child in node.children { walk(child, into: target) }
        }

        for node in nodes { walk(node, into: nil) }
        persist()
        return added
    }
}
