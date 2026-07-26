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
        // The topmost subview is the one on show — a container can briefly hold
        // the tab you just left underneath it (see `install`).
        if container.subviews.last !== webView {
            install(webView, in: container)
        }
    }

    private func install(_ webView: WKWebView?, in container: NSView) {
        // The outgoing view is hidden first and taken out a moment later,
        // rather than yanked here and now.
        //
        // Auto-PiP asks the tab you're leaving to hand its video to Picture in
        // Picture, and WebKit animates that handoff out of the video's own
        // layer — which needs to still be in a window while it happens. Pulling
        // the view immediately (the selection changes in the same turn) killed
        // the layer mid-flight, so auto-PiP quietly did nothing on every tab
        // switch while the manual toggle, which leaves the tab on screen,
        // worked fine.
        // Deliberately *not* hidden: a hidden layer can't animate to Picture in
        // Picture any more than a detached one can. The incoming view is added
        // on top and covers it completely, so it's invisible either way.
        for old in container.subviews where old !== webView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak old, weak container] in
                // Still underneath means still unwanted: if this tab was picked
                // again in the meantime it's back on top, and a view adopted by
                // another container is no longer ours to remove.
                guard let old, let container, old.superview === container,
                      container.subviews.last !== old else { return }
                old.removeFromSuperview()
            }
        }
        guard let webView else { return }
        guard webView.superview !== container else {
            container.addSubview(webView, positioned: .above, relativeTo: nil)
            return
        }
        webView.removeFromSuperview()
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
        // which is fine, since focusing a pane and blurring the address bars
        // are both idempotent.
        if hit != nil, NSApp.currentEvent?.type == .leftMouseDown {
            onClick?()
            NotificationCenter.default.post(name: .pageClicked, object: nil)
        }
        return hit
    }
}
