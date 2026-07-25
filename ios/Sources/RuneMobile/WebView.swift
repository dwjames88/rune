import SwiftUI
import WebKit

/// Presents a tab's own web view. The view is created once by the tab and
/// only ever re-parented here — switching tabs must never reload.
struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
