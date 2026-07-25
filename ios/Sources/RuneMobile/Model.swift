import Combine
import SwiftUI
import WebKit

/// A tab owns its WKWebView for life — the links-as-applications rule is the
/// same on the phone as on the Mac: switching tabs must never reload.
@MainActor
final class MobileTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let webView: WKWebView

    @Published var urlString = ""
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    /// The page's declared theme-color; the bottom bar wears it, like the
    /// Mac's minimal strip.
    @Published var themeColor: UIColor?
    /// Last look at the page, for the switcher's card.
    @Published var snapshot: UIImage?

    private var observers: [AnyCancellable] = []

    init(id: UUID = UUID(), urlString: String = "") {
        self.id = id
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()

        // Everything the chrome needs, read straight off the web view — no
        // navigation delegate, so there's exactly one source of truth.
        observers = [
            webView.publisher(for: \.url).sink { [weak self] in
                if let url = $0 { self?.urlString = url.absoluteString }
            },
            webView.publisher(for: \.title).sink { [weak self] in self?.title = $0 ?? "" },
            webView.publisher(for: \.canGoBack).sink { [weak self] in self?.canGoBack = $0 },
            webView.publisher(for: \.canGoForward).sink { [weak self] in self?.canGoForward = $0 },
            webView.publisher(for: \.isLoading).sink { [weak self] in self?.isLoading = $0 },
            webView.publisher(for: \.themeColor).sink { [weak self] in self?.themeColor = $0 },
            webView.publisher(for: \.underPageBackgroundColor).sink { [weak self] color in
                // Fallback surface when no theme-color is declared — the
                // page's own background, which is the next-truest thing.
                guard let self, self.webView.themeColor == nil else { return }
                self.themeColor = color
            },
        ]
        if !urlString.isEmpty { load(urlString) }
    }

    /// The host alone ("wikipedia.org"), the compact address the pill shows.
    var compactHost: String {
        guard let host = URL(string: urlString)?.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func load(_ address: String) {
        guard let url = URL(string: address) else { return }
        urlString = address
        webView.load(URLRequest(url: url))
    }

    func takeSnapshot() {
        let config = WKSnapshotConfiguration()
        // Wait for pending render commits: a snapshot taken mid-load came
        // back blank, and a blank card is worse than a late one.
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            if let image { self?.snapshot = image }
        }
    }
}

/// A saved site — the same shape the Mac keeps in its sidebar.
struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

/// A sidebar folder of saved sites.
struct Folder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var items: [Favorite] = []
}

/// The wire format sync will speak: what the phone and the Mac agree to
/// mirror. Deliberately plain Codable JSON — the Mac side serializes the
/// same shape from its stores, and the transport (local network first;
/// CloudKit only once there's a Developer Program membership behind the
/// app) just moves this value.
struct SyncState: Codable {
    var favorites: [Favorite] = []
    var folders: [Folder] = []
    /// Open tabs as addresses, oldest first.
    var tabs: [String] = []
}

@MainActor
final class MobileStore: ObservableObject {
    @Published var tabs: [MobileTab] = []
    @Published var selection: UUID?
    @Published var favorites: [Favorite] = []
    @Published var folders: [Folder] = []

    var activeTab: MobileTab? { tabs.first { $0.id == selection } }

    private var stateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("state.json")
    }

    init() {
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(SyncState.self, from: data) {
            favorites = state.favorites
            folders = state.folders
            tabs = state.tabs.map { MobileTab(urlString: $0) }
        }
        if favorites.isEmpty && folders.isEmpty {
            // A first launch has something to tap; sync replaces these with
            // the Mac's real sidebar.
            favorites = [
                Favorite(name: "Wikipedia", url: "https://en.wikipedia.org"),
                Favorite(name: "Apple", url: "https://apple.com"),
                Favorite(name: "Rune on GitHub", url: "https://github.com/dwjames88/rune"),
            ]
            folders = [
                Folder(name: "Reading", items: [
                    Favorite(name: "The Verge", url: "https://www.theverge.com"),
                    Favorite(name: "Daring Fireball", url: "https://daringfireball.net"),
                ]),
            ]
        }
        if tabs.isEmpty { tabs = [MobileTab()] }
        selection = tabs.last?.id
    }

    func persist() {
        let state = SyncState(favorites: favorites, folders: folders,
                              tabs: tabs.map(\.urlString).filter { !$0.isEmpty })
        try? JSONEncoder().encode(state).write(to: stateURL)
    }

    func newTab(_ address: String = "") {
        let tab = MobileTab(urlString: address)
        tabs.append(tab)
        selection = tab.id
        persist()
    }

    func close(_ tab: MobileTab) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty { tabs = [MobileTab()] }
        if selection == tab.id { selection = tabs.last?.id }
        persist()
    }

    func select(_ tab: MobileTab) {
        activeTab?.takeSnapshot()
        selection = tab.id
    }

    /// Open a saved site: focus the tab that already shows it, or make one.
    /// Saved rows behave like the Mac's pinned sites — a place, not a copy.
    /// Exact address first; failing that, the same host counts as "already
    /// here" — a loaded page rarely keeps its saved spelling (trailing
    /// slashes, redirects like wikipedia.org → /wiki/Main_Page).
    func open(_ url: String) {
        let target = tabs.first { $0.urlString == url }
            ?? host(of: url).flatMap { h in tabs.first { host(of: $0.urlString) == h } }
        if let target {
            select(target)
        } else {
            activeTab?.takeSnapshot()
            newTab(url)
        }
    }

    /// Whether a saved site is already open in some tab (the chip's dot).
    func isOpen(_ url: String) -> Bool {
        tabs.contains { $0.urlString == url }
            || host(of: url).map { h in tabs.contains { host(of: $0.urlString) == h } } ?? false
    }

    private func host(of url: String) -> String? {
        guard let h = URL(string: url)?.host else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        persist()
    }

    /// Address-or-search, the same reading the Mac gives ⌘L input: something
    /// with a dot and no spaces is a site; everything else asks the engine.
    func activate(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let address: String
        if text.contains("://") {
            address = text
        } else if text.contains("."), !text.contains(" ") {
            address = "https://\(text)"
        } else {
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            address = "https://www.google.com/search?q=\(q)"
        }
        if let tab = activeTab { tab.load(address) } else { newTab(address) }
        persist()
    }
}
