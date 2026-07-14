import SwiftUI
import WebKit

/// Hosts the selected tab's web view. Because each Tab owns its WKWebView for
/// life, switching tabs just re-parents the live view here — no reload, and
/// background tabs keep running (audio, PiP, timers).
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        install(webView, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // If a different web view should be shown, swap it in.
        if container.subviews.first !== webView {
            install(webView, in: container)
        }
    }

    private func install(_ webView: WKWebView?, in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
