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

      // The corner kit's grab tab ducks while you read downward. Only a
      // *change* of direction crosses the bridge, so a long scroll costs one
      // message, not one per frame.
      let lastY = 0, wentDown = false;
      document.addEventListener('scroll', () => {
        const y = window.scrollY || 0;
        const down = y > lastY + 2 ? true : (y < lastY - 2 ? false : wentDown);
        lastY = y;
        const next = y < 40 ? false : down;   // near the top is always "shown"
        if (next !== wentDown) { wentDown = next; post({ type: 'scroll', down: next }); }
      }, { passive: true, capture: true });

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

      // Picture in Picture, in every frame.
      //
      // evaluateJavaScript only ever runs in the main frame, and a great many
      // players — Vimeo, embedded YouTube, anything in an <iframe> — keep
      // their <video> a frame down, where document.querySelectorAll('video')
      // from the top can't see it (and cross-origin can't be reached across).
      // This script is injected into every frame, so each one can answer for
      // itself: the top frame tries locally, then broadcasts to its children,
      // and each child does the same. First one with a video wins.
      //
      // WebKit doesn't implement the W3C API (document.pictureInPictureEnabled
      // is undefined); its own path is webkitSetPresentationMode, which needs
      // no user gesture. The W3C call stays as a fallback in case that changes.
      const pipPlaying = (v) => !v.paused && !v.ended && v.readyState > 2;
      const pipAudible = (v) => !v.muted && v.volume > 0;
      const pipActive = () =>
        [...document.querySelectorAll('video')]
          .find(v => v.webkitPresentationMode === 'picture-in-picture')
        || document.pictureInPictureElement || null;

      const pipEnterHere = (audibleOnly, anyState) => {
        if (pipActive()) return 'already-pip';
        const vids = [...document.querySelectorAll('video')];
        // Autoplay heroes and hover previews are forced to start muted, so a
        // video with sound is the one you actually chose to watch. Even when
        // sound isn't required it breaks the tie between several playing ones.
        let v = vids.find(x => pipPlaying(x) && pipAudible(x));
        if (!v && !audibleOnly) v = vids.find(pipPlaying);
        if (!v && anyState) v = vids.find(x => x.readyState > 2);
        if (!v) return null;
        if (v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
          v.webkitSetPresentationMode('picture-in-picture'); return 'webkit';
        }
        if (document.pictureInPictureEnabled && v.requestPictureInPicture) {
          v.requestPictureInPicture().catch(() => {}); return 'w3c';
        }
        return 'unsupported';
      };

      const pipExitHere = () => {
        const v = [...document.querySelectorAll('video')]
          .find(x => x.webkitPresentationMode === 'picture-in-picture');
        if (v) { v.webkitSetPresentationMode('inline'); return 'webkit'; }
        if (document.pictureInPictureElement) {
          document.exitPictureInPicture().catch(() => {}); return 'w3c';
        }
        return null;
      };

      const pipBroadcast = (msg) => {
        for (const f of document.querySelectorAll('iframe')) {
          try { f.contentWindow.postMessage(msg, '*'); } catch (e) {}
        }
      };

      // Try here; if this frame has nothing, ask the children. Returns what
      // happened locally — a child's answer arrives on its own, which is why
      // the native side treats 'delegated' as "wait and see".
      window.__runePiP = (action, audibleOnly, anyState) => {
        const local = action === 'exit' ? pipExitHere() : pipEnterHere(audibleOnly, anyState);
        if (local) return local;
        const kids = document.querySelectorAll('iframe').length;
        if (kids) {
          pipBroadcast({ __rune: 'pip', action: action, audibleOnly: audibleOnly, anyState: anyState });
          return 'delegated';
        }
        return action === 'exit' ? 'none' : 'no-playing-video';
      };

      window.addEventListener('message', (e) => {
        const d = e.data;
        if (!d || d.__rune !== 'pip') return;
        window.__runePiP(d.action, d.audibleOnly, d.anyState);
      });

      // Right-click → tell native what's under the cursor, so the context menu
      // can repair WebKit's dead download
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
