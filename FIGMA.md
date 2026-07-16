# Rune → Figma component library — build map

> **✅ BUILT (2026-07-14, run `rune-ds-001`).** Layout in the file:
> **Branding** page = owner's brand work + the Tokens sheet (14:18).
> **Assets** page = the library, smallest→largest sections: 🧩 Atoms (Favicon
> set 15:17, Color Dot 15:18, Selection Bar 15:20, Section Header 15:22,
> Toolbar Button set 15:58) · 🧩 Molecules (Tab Row set 19:43, Favorites Tile
> 20:22, Address Bar 20:35, Suggestion Row 21:26, Start Tile 21:27, Toast
> 21:32, New Tab Button 21:34) · 🧩 Organisms (Toolbar 23:19, Suggestion Panel
> 23:31, Ask Bar 23:48, Link Popover 23:52, Selection Actions 23:57, Traffic
> Lights 23:64, Sidebar 24:37, Start Page 24:99).
> **Flows** page = Browser Window screen (25:2, instances only) + Overlays
> gallery (25:180) + **Finder Window screen (37:214)**. Finder design
> components (2026-07-15): Molecules — Finder Rail Row 35:102 (Label/Count
> props), Tag Chip 35:103, Finder Card set 35:135 (Kind × Selected).
> Organisms — Finder Rail 36:98, Finder Inspector 36:136. Single-mode "Rune" variable collection (owner's call: no
> modes); everything bound to it. Text is Inter standing in for SF Pro (SF Pro
> renders zero-width via the plugin API). Starter-plan caps to remember: 1
> mode/collection, 3 pages, MCP call quota (burned one account's quota mid-run).

Target file: <https://www.figma.com/design/Kmi2f7MKB8zKv209g9RXi4/Rune>
Goal: mirror the UI as a **component library the owner can rearrange** —
variables first, then components smallest → largest, screens composed purely
from instances. Every value below is read from the Swift source (2026-07-14);
build from this map, don't re-derive.

**Blocked on:** the Figma connector being authorized (claude.ai ▸ Settings ▸
Connectors ▸ Figma). Once live: load skills `figma-use` +
`figma-generate-library` + `figma-swiftui`, then execute top to bottom.

## Page structure (create in the file)

1. `🎨 Tokens` — variable docs frame (swatches bound to variables)
2. `🧩 Components` — sections: Atoms / Molecules / Organisms
3. `🖥 Screens` — Browser Window, Start Page, Settings (instances only)

## 1. Variables (collection "Rune", modes: Default + Graphite + Paper)

From `Appearance` (defaults) + `AppearanceStore` derived values:

| Variable | Default | Graphite | Paper | Scope |
|---|---|---|---|---|
| color/accent | #4ACB9E | #8E8E93 | #C0704B | fills |
| color/sidebar | #ECECEC (system) | #1C1C1E | #F2EEE6 | frame fill |
| color/chrome (toolbar) | #FFFFFF (system) | #2C2C2E | #FBF8F2 | frame fill |
| color/background | #ECECEC (system) | #000000 | #FFFDF8 | frame fill |
| color/text | #000000 (auto) | #FFFFFF | #000000 | text |
| color/textSecondary | text @ 62% | | | text |
| color/hairline | #000000 @ 8% | | | stroke |
| color/selection | accent @ 16% | | | fill |
| color/hover | #000000 @ 5% | | | fill |
| number/fontSize | 13 | 13 | 13 | text |
| number/cornerRadius | 8 | 6 | 10 | radius |
| number/sidebarWidth | 240 | | | width |

Fonts: system (SF Pro); Paper preset uses Georgia.

## 2. Atoms

| Component | Spec (from code) |
|---|---|
| **Favicon** | 15×15 (row) / 20×20 (tile) / 24×24 (start page); image radius 3; fallback = rounded-rect 4, letter 60% size semibold white on secondary |
| **Toolbar button** | 26×24 hit area, SF Symbol 13pt medium, textSecondary. Variants: sidebar.left, chevron.left, chevron.right, arrow.clockwise, xmark (loading), pip, plus.square — any `Command.icon` |
| **Downloads button** | 26×24, arrow.down.circle 13pt. While fetching: accent ring (2pt, round cap, −90° start) trimmed to progress, 18×18. Unseen-finished: 5×5 accent dot, top-trailing, offset (−3, 3) |
| **Audio badge** | speaker.wave.2.fill / speaker.slash.fill (muted), 9pt, textSecondary, 14×14 hit area |
| ~~**Color dot**~~ | **Removed** — tabs carry no colour; a favicon identifies a tab |
| ~~**Selection bar**~~ | **Removed** — selection is one flat fill, no edge bar |
| **Section header** | text 11 semibold, textSecondary, h-pad 8; optional trailing text 10 |
| **Star** (Finder, future) | SF star/star.fill 0–5 |

## 3. Molecules

| Component | Spec |
|---|---|
| **Tab row** (`RowBody`) | h 30, h-pad 8, spacing 8, radius = cornerRadius. Layers: Favicon 15 · name (fontSize 13, 1 line) · spacer · trailing (audio badge, then close xmark 9 bold in 3-pad hover circle). Variants: default / hovering (hover fill) / selected (selection fill) / session-with-close. **No colour dot, no selection bar** — a tab has no colour of its own |
| **Folder row** | chevron 9 (right/down) 10 wide · icon 11 in folder colour (or accent) · name 12 medium · h-pad 8 v-pad 5, radius = cornerRadius; drop-targeted = folder colour @22%. Folders are the only coloured thing in the sidebar |
| **Favicon tile** (favorites) | 34×34, radius = cornerRadius, hover fill; selected = selection fill + 1.5 accent stroke; Favicon 20 centered |
| **Address bar** | auto-layout h-pad 10 v-pad 6, radius = cornerRadius, fill = background, stroke hairline (focused: accent). Leading magnifyingglass 11. Variants: compact (host only, e.g. "pinkbike.com") / full URL / placeholder "Search or enter address" |
| **Suggestion row** | h-pad 10 v-pad 7 radius 6; icon 16 wide + title + trailing URL (11, max 260, right); highlighted = accent fill, white text. Icon variants: arrow.up.forward / magnifyingglass / clock / sparkles |
| **Start tile** | 52×52 radius cornerRadius+2 chrome fill + hairline stroke, favicon 24; label 11 secondary below, max-w 64, spacing 6 |
| **Toast** | capsule, material, h-pad 14 v-pad 8, text 12 medium, hairline stroke, shadow |
| **New Tab button** | plus + "New Tab" 13, textSecondary, pad 8/7 |

## 4. Organisms

| Component | Spec |
|---|---|
| **Toolbar** | full-width, chrome fill, h-pad 10 v-pad 7, spacing 8: [toolbar buttons…] + address bar (FILL). Buttons are data-driven (`Appearance.toolbarButtons`) |
| **Sidebar** | w 240 (variable), sidebar fill; top spacer 28 (traffic lights); scroll stack spacing 14 pad h8/t4: Favorites section (header + 6-col grid, tiles 34, gap 6, pad 3) · Pinned section (header + folder rows + rows) · Tabs section (header + session rows, spacing 2) ·  bottom New Tab button (pad 8) |
| **Suggestion list** | panel pad 5, radius cornerRadius+2, material + hairline + shadow(18% r14 y6); rows stacked spacing 1 |
| **Start page** | background fill (startPageBackground); centered stack spacing 22: greeting (40 semibold, text@85%) · search capsule (max-w 560, pad 18/14, chrome fill, capsule, hairline/accent stroke, leading magnifyingglass, placeholder 17) · favorites row (tiles, spacing 14) · recents list (rows: clock 11 + title, pad 10/5, max-w 560) |
| **Ask bar** | w 620, radius 12, material, hairline, shadow(22% r24 y8); header row pad 14/11 spacing 10: sparkles (accent) + field (15) + xmark 10; divider; answer scroll pad 14, text 13, max-h 260 |
| **Link summary popover** | w 300, pad 10, radius 10, material + hairline + shadow(18% r12 y4); header: sparkles 10 accent + host 11 semibold; body 12 |
| **Selection actions** | w 300 (360 with result), pad 10, radius 10, material; capsule buttons (label 11, pad 8/5, hover fill): Explain lightbulb / Summarize text.alignleft / Translate globe; divider + result 12 max-h 180 |
| **Window chrome** | traffic lights (3× 12 circles: #FF5F57 #FEBC2E #28C840, spacing 8) — hideable |

## 5. Screens (instances only)

1. **Browser Window** — 1280×820, radius ~10: Sidebar + Divider(hairline) + [Toolbar / Divider / content]. Build one with web-content placeholder image, one with Start Page.
2. **Start Page state** — window with start page + greeting "Rune".
3. **Settings ▸ Appearance** — 600×620, segmented header (Appearance/Presets/Browsing/Claude/Shortcuts), grouped form (optional; lower priority).
4. **Overlay states** — window + suggestion list open; window + Ask bar; page + link popover + selection actions.

## Execution notes (for the session that runs this)

- Inspect the file first — it may not be empty; put work on the pages above,
  positioned clear of existing content.
- Variables → atoms → molecules (variants via `combineAsVariants`) → organisms
  → screens; bind every fill/radius/text size to the variables so preset modes
  (Default/Graphite/Paper) switch the whole board.
- ≤10 operations per `use_figma` call; screenshot-validate after each tier.
- Auto-layout everywhere; name layers exactly as the components above so the
  owner can find things ("Tab row / selected", "Address bar / compact").
