import SwiftUI
import WebKit

/// Hosts the selected tab's web view. Because each Tab owns its WKWebView for
/// life, switching tabs just re-parents the live view here — no reload, and
/// background tabs keep running (audio, PiP, timers). Split View is the same
/// trick twice: two containers, two live views, nothing recreated.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView?
    /// Called when a click lands anywhere in this container — how a pane knows
    /// it's been focused.
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let container = ClickReportingView()
        container.wantsLayer = true
        container.onClick = onClick
        install(webView, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        (container as? ClickReportingView)?.onClick = onClick
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

/// A WKWebView consumes mouse events itself, so neither a SwiftUI tap gesture
/// laid over it nor `mouseDown` on its superview ever sees the click — and a
/// transparent catcher on top would work exactly once, by breaking the page.
///
/// `hitTest` is asked first, on the way down. Noticing the click there reports
/// it without taking it: the event still reaches the page.
private final class ClickReportingView: NSView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // hitTest runs for mouse-moved too, and more than once per click —
        // which is fine, since the only thing this does is focus a pane.
        if hit != nil, NSApp.currentEvent?.type == .leftMouseDown { onClick?() }
        return hit
    }
}
