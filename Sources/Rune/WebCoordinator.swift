import WebKit

/// Shared navigation + UI delegate for every tab's web view.
/// TLS is validated by the system by default (we don't weaken it); this is
/// where a padlock / cert-warning UI and pinning would later hook in.
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var model: BrowserModel?

    /// In-flight downloads, keyed by the WKDownload that owns them — the
    /// framework object has no room for our row. Cleared on finish or failure.
    fileprivate var activeDownloads: [ObjectIdentifier: DownloadItem] = [:]

    init(model: BrowserModel?) { self.model = model }

    // MARK: Page bridge (link hovers, selections, audio)

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
            case "audio":
                tab.isPlayingAudio = body["playing"] as? Bool ?? false
            case "contextTarget":
                guard let runeView = webView as? RuneWebView else { return }
                if let src = body["src"] as? String, let url = URL(string: src) {
                    let kind: FinderItem.Kind = (body["kind"] as? String) == "video" ? .video : .image
                    runeView.contextTarget = .init(url: url, kind: kind, at: Date())
                } else {
                    runeView.contextTarget = nil
                }
            default: break
            }
        }
    }

    // MARK: New windows / links

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        model?.adoptPopup(configuration: configuration,
                          select: !navigationAction.opensInBackground)
    }

    /// ⌘-click opens a link in a background tab, ⇧⌘-click in a foreground one,
    /// and ⇧-click peeks it in a window that floats over this one. Left to
    /// itself WebKit would just navigate the current page.
    ///
    /// ⌥-click is deliberately untouched: macOS spends that on downloading a
    /// link, and Rune has downloads now.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else { return .allow }
        let flags = navigationAction.modifierFlags
        if flags.contains(.command) {
            model?.newTab(url: url, select: !navigationAction.opensInBackground)
            return .cancel
        }
        if flags.contains(.shift) {
            NotificationCenter.default.post(name: .glanceLink, object: url)
            return .cancel
        }
        return .allow
    }

    /// Anything WebKit can't render is a file you meant to keep.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: Load lifecycle

    /// Zoom belongs to the site, so it has to be on before the first paint —
    /// commit is the earliest point the new URL is known.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        model?.applyZoom(to: tab)
        // Reader is a view of *this* page; a new one isn't it.
        tab.reader = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        model?.recordVisit(url, title: webView.title ?? "")
        // A muted tab stays muted across navigations: the bridge is re-injected
        // per page, so the flag has to be re-applied to the fresh document.
        if let tab = tab(for: webView), tab.muted { tab.applyMuteToPage() }
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

// MARK: - Downloads

extension WebCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        guard let model else { return nil }
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename

        let destination: URL?
        switch model.settings.downloadLocation {
        case .downloadsFolder:
            destination = DownloadStore.uniqueURL(in: DownloadStore.downloadsFolder, filename: name)
        case .finderLibrary:
            // Stage in temp; the library ingests it once the bytes have landed.
            destination = DownloadStore.uniqueURL(in: Self.stagingDirectory, filename: name)
        case .ask:
            destination = await Self.askForDestination(name: name)
        }
        guard let destination else { return nil }   // nil cancels the download

        let item = DownloadItem(filename: name,
                                source: download.originalRequest?.url ?? response.url ?? URL(fileURLWithPath: "/"),
                                download: download)
        item.destination = destination
        model.downloads.add(item)
        activeDownloads[ObjectIdentifier(download)] = item
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = activeDownloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.state = .finished
        if model?.settings.downloadLocation == .finderLibrary, let staged = item.destination {
            ingest(staged, into: item)
        } else {
            NotificationCenter.default.post(name: .finderToast, object: "Downloaded \(item.filename)")
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = activeDownloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // A cancel arrives here too; don't overwrite the nicer reason with the
        // framework's "operation couldn't be completed".
        if case .failed = item.state { return }
        item.state = .failed(error.localizedDescription)
    }

    /// Move a staged download into the Finder library and point the row at its
    /// copy there, so "Show in Finder" still leads somewhere real.
    private func ingest(_ staged: URL, into item: DownloadItem) {
        guard let finder = model?.finder else { return }
        Task { @MainActor in
            if let saved = try? await finder.importFile(staged) {
                item.destination = finder.fileURL(for: saved)
                NotificationCenter.default.post(name: .finderToast,
                                                object: "Downloaded \(item.filename) to Finder")
            } else {
                item.state = .failed("Couldn't add it to the Finder library")
            }
            try? FileManager.default.removeItem(at: staged)
        }
    }

    private static var stagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Rune-Downloads")
    }

    private static func askForDestination(name: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = DownloadStore.downloadsFolder
        panel.canCreateDirectories = true
        return await panel.begin() == .OK ? panel.url : nil
    }
}

// MARK: - Modifier conventions

private extension WKNavigationAction {
    /// ⌘-click means "put it over there, I'm still reading this"; adding shift
    /// means "take me there now".
    var opensInBackground: Bool {
        modifierFlags.contains(.command) && !modifierFlags.contains(.shift)
    }
}
