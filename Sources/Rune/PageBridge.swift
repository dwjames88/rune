import Foundation
import WebKit

/// What the page is currently offering Claude: a link you're hovering, or text
/// you've selected. Positions are viewport CSS pixels, so the UI can anchor to them.
struct HoverTarget: Equatable {
    var url: URL
    var x: Double
    var y: Double
}

struct SelectionTarget: Equatable {
    var text: String
    var x: Double
    var y: Double
}

/// Injected into every page. Reports link hovers (debounced) and selections.
/// This is the only script Rune adds to pages — no tracking, no network calls.
enum PageBridge {
    static let handlerName = "rune"

    /// The bridge script with the hover settings baked in for fresh pages;
    /// `window.__runeHoverMs` / `__runeHoverOff` override live (see
    /// BrowserModel.applyHoverSettings) so a settings change doesn't need a reload.
    static func userScript(hoverDelayMs: Int, hoverEnabled: Bool) -> WKUserScript {
        WKUserScript(source: source(hoverDelayMs: hoverDelayMs, hoverEnabled: hoverEnabled),
                     injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    private static func source(hoverDelayMs: Int, hoverEnabled: Bool) -> String { """
    (function () {
      const post = (m) => { try { window.webkit.messageHandlers.rune.postMessage(m); } catch (e) {} };
      let timer = null;
      let hoverShown = false;    // a linkHover was posted and not yet cleared
      let selShown = false;      // a selection was posted and not yet cleared
      const hoverMs = () => window.__runeHoverMs !== undefined ? window.__runeHoverMs : \(hoverDelayMs);
      const hoverOff = () => window.__runeHoverOff !== undefined ? window.__runeHoverOff : \(hoverEnabled ? "false" : "true");
      const clearHover = () => {
        clearTimeout(timer); timer = null;
        if (hoverShown) { hoverShown = false; post({ type: 'linkOut' }); }
      };

      document.addEventListener('mouseover', (e) => {
        if (hoverOff()) return;
        const a = e.target.closest && e.target.closest('a[href]');
        if (!a) return;
        const href = a.href;
        if (!href || href.startsWith('javascript:')) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          const r = a.getBoundingClientRect();
          hoverShown = true;
          post({ type: 'linkHover', href: href, x: r.left, y: r.bottom });
        }, hoverMs());
      }, true);

      document.addEventListener('mouseout', (e) => {
        if (e.target.closest && e.target.closest('a[href]')) { clearHover(); }
      }, true);

      document.addEventListener('mouseup', () => {
        setTimeout(() => {
          const sel = window.getSelection();
          const text = sel ? String(sel).trim() : '';
          if (text.length > 1 && sel.rangeCount) {
            const r = sel.getRangeAt(0).getBoundingClientRect();
            selShown = true;
            post({ type: 'selection', text: text.slice(0, 4000), x: r.left, y: r.bottom });
          } else if (selShown) {
            selShown = false;
            post({ type: 'selectionCleared' });
          }
        }, 10);
      }, true);

      // Only bother the native side while something is actually showing —
      // scrolling must never pay for the bridge.
      document.addEventListener('scroll', clearHover, true);
    })();
    """ }

    /// Readable text of the current page, for "ask about this page".
    static let pageTextJS = """
    (function () {
      const el = document.querySelector('article') || document.querySelector('main') || document.body;
      return (el ? el.innerText : '').slice(0, 12000);
    })();
    """

    /// Fetch a URL and reduce it to plain text, so Claude can summarize where a
    /// link goes before you click it.
    static func remoteText(for url: URL, limit: Int = 6000) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh) Rune/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        return strip(html: html, limit: limit)
    }

    /// Crude but dependency-free: drop script/style, strip tags, collapse whitespace.
    static func strip(html: String, limit: Int) -> String {
        var s = html
        for pattern in ["<script[^>]*>[\\s\\S]*?</script>", "<style[^>]*>[\\s\\S]*?</style>",
                        "<!--[\\s\\S]*?-->", "<[^>]+>"] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(limit))
    }
}
