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

    static var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    private static let source = """
    (function () {
      const post = (m) => { try { window.webkit.messageHandlers.rune.postMessage(m); } catch (e) {} };
      let timer = null;

      document.addEventListener('mouseover', (e) => {
        const a = e.target.closest && e.target.closest('a[href]');
        if (!a) return;
        const href = a.href;
        if (!href || href.startsWith('javascript:')) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          const r = a.getBoundingClientRect();
          post({ type: 'linkHover', href: href, x: r.left, y: r.bottom });
        }, 450);
      }, true);

      document.addEventListener('mouseout', (e) => {
        const a = e.target.closest && e.target.closest('a[href]');
        if (a) { clearTimeout(timer); post({ type: 'linkOut' }); }
      }, true);

      document.addEventListener('mouseup', () => {
        setTimeout(() => {
          const sel = window.getSelection();
          const text = sel ? String(sel).trim() : '';
          if (text.length > 1 && sel.rangeCount) {
            const r = sel.getRangeAt(0).getBoundingClientRect();
            post({ type: 'selection', text: text.slice(0, 4000), x: r.left, y: r.bottom });
          } else {
            post({ type: 'selectionCleared' });
          }
        }, 10);
      }, true);

      document.addEventListener('scroll', () => post({ type: 'linkOut' }), true);
    })();
    """

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
