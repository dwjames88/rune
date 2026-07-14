import Combine
import SwiftUI
import WebKit

/// A single tab. Its WKWebView is created once and kept alive for the tab's
/// whole lifetime — switching tabs never reloads, which is what makes a link
/// feel like an application you return to rather than a bookmark you re-open.
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var host: String = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isPinned = false

    private var cancellables: Set<AnyCancellable> = []

    /// Wraps a web view the model built (or one the engine handed us for a popup).
    init(webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.webView = webView

        // Mirror WKWebView's KVO-observable state into @Published properties.
        webView.publisher(for: \.title).sink { [weak self] in
            if let t = $0, !t.isEmpty { self?.title = t }
        }.store(in: &cancellables)
        webView.publisher(for: \.url).sink { [weak self] url in
            self?.urlString = url?.absoluteString ?? ""
            self?.host = url?.host ?? ""
        }.store(in: &cancellables)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    /// Best-effort auto-PiP: if a video is playing, pop it out. Called when the
    /// tab is switched away from.
    func requestPiPIfPlaying() {
        let js = """
        (function(){
          const v = [...document.querySelectorAll('video')].find(v => !v.paused && !v.ended && v.readyState > 2);
          if (v && document.pictureInPictureEnabled && !document.pictureInPictureElement) {
            v.requestPictureInPicture().catch(()=>{});
          }
        })();
        """
        webView.evaluateJavaScript(js)
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTabID: Tab.ID?
    @Published var sidebarVisible = true

    let configuration: WKWebViewConfiguration
    private lazy var coordinator = WebCoordinator(model: self)

    static let homeURL = URL(string: "https://duckduckgo.com")!

    var pinnedTabs: [Tab] { tabs.filter(\.isPinned) }
    var unpinnedTabs: [Tab] { tabs.filter { !$0.isPinned } }
    var selectedTab: Tab? { tabs.first { $0.id == selectedTabID } }

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()            // persistent cookies/logins
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        self.configuration = config
    }

    // MARK: Tabs

    private func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration ?? self.configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return webView
    }

    @discardableResult
    func newTab(url: URL? = nil, pinned: Bool = false, select: Bool = true) -> Tab {
        let tab = Tab(webView: makeWebView())
        tab.isPinned = pinned
        tabs.append(tab)
        tab.load(url ?? Self.homeURL)
        if select { self.select(tab) }
        return tab
    }

    /// Wrap a WKWebView the engine created for us (target=_blank popups) and
    /// return it so WebKit can drive the new navigation.
    func adoptPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = makeWebView(configuration: configuration)
        let tab = Tab(webView: webView)
        tabs.append(tab)
        select(tab)
        return webView
    }

    func select(_ tab: Tab) {
        if let current = selectedTab, current.id != tab.id {
            current.requestPiPIfPlaying()
        }
        selectedTabID = tab.id
    }

    func selectAdjacent(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == selectedTabID } ?? 0
        let next = (index + delta + tabs.count) % tabs.count
        select(tabs[next])
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.webView.stopLoading()
        tabs.remove(at: index)
        if selectedTabID == tab.id {
            selectedTabID = tabs[max(0, index - 1)...].first?.id ?? tabs.last?.id
        }
    }

    func closeSelected() { if let t = selectedTab { close(t) } }

    func togglePinSelected() { selectedTab?.isPinned.toggle() }

    // MARK: Navigation

    func navigate(_ input: String) {
        guard let tab = selectedTab ?? tabs.first else {
            if let url = Self.resolve(input) { newTab(url: url) }
            return
        }
        if let url = Self.resolve(input) { tab.load(url) }
    }

    func goBack() { selectedTab?.webView.goBack() }
    func goForward() { selectedTab?.webView.goForward() }
    func reload() { selectedTab?.webView.reload() }

    /// Turn a typed string into a URL, or a DuckDuckGo search if it isn't one.
    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains(" ") || !text.contains(".") {
            var comps = URLComponents(string: "https://duckduckgo.com/")!
            comps.queryItems = [URLQueryItem(name: "q", value: text)]
            return comps.url
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        return URL(string: "https://\(text)")
    }
}

