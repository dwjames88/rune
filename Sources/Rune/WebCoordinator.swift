import WebKit

/// Shared navigation + UI delegate for every tab's web view.
/// TLS is validated by the system by default (we don't weaken it); this is
/// where a padlock / cert-warning UI and pinning would later hook in.
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?

    init(model: BrowserModel?) {
        self.model = model
    }

    // target=_blank / window.open → open a new tab instead of a detached window.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        model?.adoptPopup(configuration: configuration)
    }

    // Record every completed navigation into browsing history.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        model?.recordVisit(url, title: webView.title ?? "")
    }
}
