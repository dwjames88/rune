import WebKit

/// Shared navigation + UI delegate for every tab's web view.
/// TLS is validated by the system by default (we don't weaken it); this is
/// where a padlock / cert-warning UI and pinning would later hook in.
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var model: BrowserModel?

    init(model: BrowserModel?) { self.model = model }

    // MARK: Page bridge (link hovers + selections for Claude)

    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let webView = message.webView
        Task { @MainActor in
            guard let webView, let tab = self.tab(for: webView) else { return }
            switch type {
            case "linkHover":
                guard let href = body["href"] as? String, let url = URL(string: href),
                      url.absoluteString != tab.urlString else { return }
                tab.hoveredLink = HoverTarget(url: url,
                                              x: body["x"] as? Double ?? 0,
                                              y: body["y"] as? Double ?? 0)
            case "linkOut":
                tab.hoveredLink = nil
            case "selection":
                guard let text = body["text"] as? String else { return }
                tab.selection = SelectionTarget(text: text,
                                                x: body["x"] as? Double ?? 0,
                                                y: body["y"] as? Double ?? 0)
            case "selectionCleared":
                tab.selection = nil
            default: break
            }
        }
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        model?.adoptPopup(configuration: configuration)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        model?.recordVisit(url, title: webView.title ?? "")
        fetchFavicon(for: webView)
    }

    private func tab(for webView: WKWebView) -> Tab? {
        if let t = model?.sessionTabs.first(where: { $0.webView === webView }) { return t }
        return model?.openTabs.values.first { $0.webView === webView }
    }

    /// Grab the page's declared favicon (or /favicon.ico) and hand it to the model.
    private func fetchFavicon(for webView: WKWebView) {
        let js = "document.querySelector(\"link[rel~='icon']\")?.href || (location.origin + '/favicon.ico')"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, let href = result as? String, let iconURL = URL(string: href),
                  let tab = self.tab(for: webView) else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: iconURL),
                      let image = NSImage(data: data) else { return }
                await MainActor.run { self.model?.updateFavicon(image, for: tab) }
            }
        }
    }
}
