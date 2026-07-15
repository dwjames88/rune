# Rune Finder — spec (draft)

A built-in inspiration library: save images, videos, and files from the web with
tags and metadata, fully customizable, no third-party apps. Modeled on Eagle
(eagle.cool), adapted to Rune's rules: Swift only, zero deps, a setting for
everything, Claude ambient.

## 1. What Eagle does (crawl notes, 2026-07-14)

**Capture** (browser extension + app):
- Drag any image to a floating drop target → saved.
- Alt+Right-click saves an image, bypassing site download restrictions.
- **Batch collect**: one click scans the page for all assets, filter by min
  size / format, pick folder + tags at save time, save all.
- Screenshots: capture area / capture element / full page.
- Source URL captured automatically with every save.

**Library on disk** (the part worth copying):
- `library/images/<ID>.info/` — one folder per item containing the original
  file(s) plus `metadata.json`. Folder membership is *metadata*, so one item
  can live in many folders; the physical location never changes.
- Self-describing and corruption-tolerant: lose the index, the items survive.

**Item metadata** (from Eagle's plugin API):
`id, name, ext, size, btime/mtime/importedAt, tags[], folders[], annotation
(note), url (source page), star (0–5), width/height, palettes (dominant
colors), comments[] (anchored annotations)`.

**Organization**: folder hierarchy (password-protectable) · tags + tag groups ·
**smart folders** (rules over tags/colors/ratings/types/keywords) · auto-tagging
rules · star ratings · duplicate detection · search by name/tag/color/metadata.

## 2. Rune Finder design

### Storage — `FinderStore`

- Default library at `~/Library/Application Support/Rune/Finder/`, **location
  is a setting** (so it can sit in iCloud Drive/Dropbox).
- Eagle-style layout, one folder per item:
  ```
  Finder/
    items/<uuid>/
      original.<ext>        # untouched download
      thumb.png             # generated thumbnail (lazy)
      item.json             # everything below
    folders.json            # virtual folder tree + smart folder rules
  ```
- In-memory index built by scanning `items/` at first open (thousands of items
  is fine); persisted index only if it ever gets slow.

### Item model (Codable, tolerant decoding like `Appearance`)

```swift
struct FinderItem {
    var id: UUID
    var fileName: String          // display name, editable
    var ext: String
    var kind: Kind                // image / video / audio / page / other
    var sourceURL: String         // page it was saved from
    var assetURL: String          // direct URL of the asset
    var tags: [String]
    var folderIDs: [UUID]         // multi-membership, Eagle-style
    var note: String
    var star: Int                 // 0–5
    var width: Int?, height: Int?
    var colors: [String]          // dominant hex colors (CoreImage, native)
    var addedAt: Date
    var byteSize: Int
    var custom: [String: String]  // user-defined fields — "fully customizable"
}
```

Smart folders: `folders.json` entries with `rules: [Rule]` (tag / kind / star /
color / keyword / date predicates) evaluated over the index — same data-driven
spirit as `Command`.

### Capture flows (each one is a `Command` → menu item + remappable shortcut)

1. **Right-click → "Save to Finder"** — subclass WKWebView, override
   `willOpenMenu(_:with:)`; PageBridge already tracks the element under the
   cursor, extend it to report `img/video src` on `contextmenu`.
2. **Hover + shortcut** — save the image under the cursor without clicking
   (PageBridge hover target + a Command).
3. **Batch collect** (Eagle's killer feature) — JS scans
   `document.images`/`video` → native grid sheet, filter by min size/format,
   pick tags/folder once, save selected. Min-size default is a setting.
4. **Capture page** — `WKWebView.takeSnapshot` (visible) and full-page via
   pagination; saved as an image item with sourceURL.
5. **Drag out of the page** onto a Finder drop zone in the sidebar (later).

Downloads via `URLSession` (async), never through the page. Metadata captured
at save time: source page URL + title, asset URL, dimensions, dominant colors.

### UI

- A **Finder surface in the content area** (like the start page — native
  SwiftUI, no web view): thumbnail grid, left rail = folders + smart folders +
  tag cloud, top = search + kind/star/color filters, right = inspector for the
  selected item (rename, tags, note, star, custom fields, "open source page").
- Opened via Command (suggested ⌥⌘F) and/or a sidebar section.
- Appearance-driven like everything else; grid density as a knob.

### Claude (ambient, optional, off until enabled)

- Auto-tag + one-line description on save (vision request on the thumbnail);
  description indexed for search — "that moody kitchen render" finds it.
- Batch "suggest tags" over a selection.

### Settings (Settings ▸ Finder)

Library location · default folder for quick saves · auto-tag with Claude
on/off · batch-collect min size · filename policy (keep original / title-based)
· thumbnail size.

## 3. Build order

1. `FinderStore` + item model + disk layout + save-from-URL pipeline + thumbnails.
2. Capture: context menu + hover-shortcut save (PageBridge + willOpenMenu).
3. Finder surface: grid, folders/tags rail, search, inspector.
4. Batch collect sheet + page capture.
5. Smart folders + custom fields UI.
6. Claude auto-tagging.

Sources: eagle.cool, en.eagle.cool/extensions, eagle.cool/support/desktop/organize,
developer.eagle.cool/plugin-api/api/item, ivomynttinen.com (library-on-disk format).
