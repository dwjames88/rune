import SwiftUI

/// A page reduced to what you came for.
struct ReaderArticle: Decodable, Equatable {
    struct Block: Decodable, Equatable {
        /// h = heading · p = paragraph · li = list item · q = quote · code
        var type: String
        var text: String
    }
    var title: String
    var blocks: [Block]
}

enum Reader {
    /// Finding the article is the whole problem, and it's the one place Rune's
    /// zero-dependency rule actually costs something: Readability.js is the
    /// standard answer and it's a dependency. So this is the same idea, by
    /// hand, and much smaller.
    ///
    /// Score every block that could be the story — length, paragraph count, and
    /// commas, which are a decent proxy for prose rather than a list of links —
    /// then divide by link density, because a wall of links is a nav bar however
    /// long it is. The winner is the article; everything outside it is the site.
    ///
    /// It will be wrong sometimes. That's why it returns nil rather than
    /// guessing: a reader that shows you a menu is worse than no reader.
    static let extractJS = """
    (function () {
      const junk = /(comment|share|footer|nav|header|sidebar|promo|advert|\\bad[-_]|social|related|recommend|sponsor|cookie|banner|menu|masthead|breadcrumb|popup|newsletter|subscribe)/i;
      const named = (el) => ((el.className && typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || ''));

      const linkDensity = (el) => {
        const len = (el.innerText || '').length;
        if (!len) return 1;
        let linked = 0;
        for (const a of el.querySelectorAll('a')) linked += (a.innerText || '').length;
        return Math.min(1, linked / len);
      };

      const score = (el) => {
        const text = el.innerText || '';
        if (text.length < 250) return 0;
        if (junk.test(named(el))) return 0;
        const paras = el.querySelectorAll('p').length;
        if (!paras) return 0;
        const commas = (text.match(/,/g) || []).length;
        return (text.length / 100 + paras * 4 + commas) * (1 - linkDensity(el));
      };

      let best = null, top = 0;
      for (const el of document.querySelectorAll('article, main, section, div')) {
        const s = score(el);
        if (s > top) { top = s; best = el; }
      }
      if (!best) return null;

      // Walk in document order so the reading flow survives, and skip anything
      // inside a block already taken — otherwise a <p> in a <li> arrives twice.
      const taken = new Set();
      const blocks = [];
      for (const node of best.querySelectorAll('h1,h2,h3,h4,p,li,blockquote,pre')) {
        let anc = node.parentElement, nested = false;
        while (anc && anc !== best) {
          if (taken.has(anc)) { nested = true; break; }
          anc = anc.parentElement;
        }
        if (nested) continue;
        const text = (node.innerText || '').trim();
        if (text.length < 2) continue;
        if (junk.test(named(node))) continue;
        const tag = node.tagName.toLowerCase();
        // A paragraph that's mostly links is a list of links, not prose.
        if ((tag === 'p' || tag === 'li') && linkDensity(node) > 0.5) continue;
        taken.add(node);
        const type = tag[0] === 'h' ? 'h'
                   : tag === 'li' ? 'li'
                   : tag === 'blockquote' ? 'q'
                   : tag === 'pre' ? 'code' : 'p';
        blocks.push({ type: type, text: text.slice(0, 8000) });
      }
      if (blocks.length < 2) return null;

      const h1 = document.querySelector('h1');
      const title = ((h1 && h1.innerText) || document.title || '').trim();
      return JSON.stringify({ title: title, blocks: blocks.slice(0, 500) });
    })();
    """
}

/// The article, set in your typography rather than the site's. This is the part
/// that's free: Rune already knows what you like to read in.
struct ReaderView: View {
    let article: ReaderArticle
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !article.title.isEmpty {
                    Text(article.title)
                        .font(appearance.font(32, weight: .semibold))
                        .padding(.bottom, 4)
                }
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            // A measure, not a window width: long lines are hard to read, and
            // the whole point of this view is that reading is easier.
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 40).padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .background(appearance.startPageBG)
        .foregroundStyle(appearance.text(on: appearance.startPageBG))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: ReaderArticle.Block) -> some View {
        switch block.type {
        case "h":
            Text(block.text).font(appearance.font(21, weight: .semibold)).padding(.top, 10)
        case "li":
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(appearance.accent)
                Text(block.text).font(appearance.font(16))
            }
        case "q":
            Text(block.text)
                .font(appearance.font(16)).italic()
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(appearance.accent).frame(width: 3)
                }
        case "code":
            Text(block.text)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appearance.hover, in: RoundedRectangle(cornerRadius: 6))
        default:
            Text(block.text).font(appearance.font(16)).lineSpacing(5)
        }
    }
}
