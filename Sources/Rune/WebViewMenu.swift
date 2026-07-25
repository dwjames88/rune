import AppKit
import WebKit

/// A page asset found by batch collect.
struct CollectCandidate: Codable, Identifiable, Equatable {
    var src: String
    var w: Int
    var h: Int
    var kind: String
    var id: String { src }
}

/// What kind of media a right-click landed on.
enum MediaKind { case image, video }

/// WKWebView subclass that makes the page context menu's download items
/// real. The PageBridge posts the media element under the cursor on
/// `contextmenu`; the coordinator stashes it here just before the menu opens.
final class RuneWebView: WKWebView {
    /// What the last right-click landed on. Either half can be missing — a bare
    /// image has no link, a text link has no media, a linked image has both.
    struct ContextTarget {
        var media: URL?
        var kind: MediaKind
        var link: URL?
        var at: Date
    }

    var contextTarget: ContextTarget?
    var onDownload: ((URL) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // A stale target means this right-click landed somewhere else.
        guard let target = contextTarget, Date().timeIntervalSince(target.at) < 2 else { return }

        // WebKit's own download items build a WKDownload it only hands back
        // through private API, so out of the box they do nothing at all: you
        // click Download Image and the click goes in the bin. We already know
        // what's under the cursor, so point them at Rune's download path —
        // which lands in the download folder like every other save.
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierDownloadMedia":
                redirect(item, to: target.media)
            case "WKMenuItemIdentifierDownloadLinkedFile":
                redirect(item, to: target.link)
            default: break
            }
        }
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
}
