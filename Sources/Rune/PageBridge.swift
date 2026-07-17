import Foundation
import WebKit

/// A link you're hovering. No position: the summary lives in the corner, out of
/// the page's way, because a page draws its *own* popups next to its links and
/// two popups fighting for the same spot is what you get for anchoring there.
struct HoverTarget: Equatable {
    var url: URL
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
          hoverShown = true;
          post({ type: 'linkHover', href: href });
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

      // Media under the cursor: tracked locally on mouseover (no bridge
      // traffic); read by the context menu and the ⌥S save-under-cursor
      // command via window.__runeMedia().
      let lastMedia = null;
      const mediaInfo = (t) => {
        const media = t && t.closest && t.closest('img,video,picture');
        if (!media) return null;
        const el = media.tagName === 'PICTURE' ? media.querySelector('img') : media;
        if (!el) return null;
        const src = el.currentSrc || el.src || null;
        if (!src) return null;
        return { src: src, kind: el.tagName === 'VIDEO' ? 'video' : 'image' };
      };
      document.addEventListener('mouseover', (e) => { lastMedia = mediaInfo(e.target); }, true);
      window.__runeMedia = () => lastMedia;

      // Right-click → tell native what's under the cursor, so the context menu
      // can offer "Save to Rune Finder" and can repair WebKit's dead download
      // items. Fires once per right-click.
      document.addEventListener('contextmenu', (e) => {
        const m = mediaInfo(e.target);
        const a = e.target.closest && e.target.closest('a[href]');
        post({ type: 'contextTarget', src: m ? m.src : null, kind: m ? m.kind : null,
               href: a && a.href && !a.href.startsWith('javascript:') ? a.href : null });
      }, true);

      // Audio state + mute. WKWebView has no public per-tab mute, so the media
      // elements are silenced directly. Media events don't bubble, but a
      // capture listener on document still sees every one of them — including
      // elements added later — so this needs no observer and no polling, and
      // costs nothing on a page that never plays anything.
      let muted = false;
      const mediaEls = () => [...document.querySelectorAll('video,audio')];
      const audible = () => mediaEls().some(m => !m.paused && !m.ended && !m.muted && m.volume > 0);
      let wasAudible = false;
      const reportAudio = () => {
        const now = audible();
        if (now !== wasAudible) { wasAudible = now; post({ type: 'audio', playing: now }); }
      };

      document.addEventListener('play', (e) => {
        // Anything that starts playing into a muted tab starts muted.
        if (muted && e.target && 'muted' in e.target) e.target.muted = true;
        reportAudio();
      }, true);
      for (const ev of ['pause', 'ended', 'volumechange', 'emptied']) {
        document.addEventListener(ev, reportAudio, true);
      }

      window.__runeMute = (on) => {
        muted = on;
        for (const m of mediaEls()) m.muted = on;
        reportAudio();
      };
    })();
    """ }

    /// Scan the page for collectable media (batch collect). Returns
    /// [{src, w, h, kind}], deduped, largest first.
    static let collectMediaJS = """
    (function () {
      const seen = new Set();
      const out = [];
      for (const img of document.querySelectorAll('img')) {
        const src = img.currentSrc || img.src;
        if (!src || !src.startsWith('http') || seen.has(src)) continue;
        seen.add(src);
        out.push({ src: src, w: img.naturalWidth || img.width || 0, h: img.naturalHeight || img.height || 0, kind: 'image' });
      }
      for (const v of document.querySelectorAll('video')) {
        const src = v.currentSrc || v.src;
        if (!src || !src.startsWith('http') || seen.has(src)) continue;
        seen.add(src);
        out.push({ src: src, w: v.videoWidth || 0, h: v.videoHeight || 0, kind: 'video' });
      }
      out.sort((a, b) => (b.w * b.h) - (a.w * a.h));
      return JSON.stringify(out.slice(0, 120));
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
