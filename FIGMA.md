# Rune → Figma component library — build map

> **Run state (2026-07-14, run `rune-ds-001`)** — build is ~60% done and paused
> on the **Figma Starter-plan MCP tool-call cap** (account dwjames88@icloud.com).
> DONE in the file: "Rune" variable collection (12 vars, single Theme mode —
> Starter allows 1 mode), 8 Inter text styles + 4 shadow styles, Tokens sheet,
> **Atoms** (Favicon set 15:17, Color Dot, Selection Bar, Section Header,
> Toolbar Button set 15:58) and **Molecules** (Tab Row set 19:43, Favorites
> Tile 20:22, Address Bar 20:35, Suggestion Row 21:26, Start Tile, Toast, New
> Tab Button) — all as sections on the "Assets" page (Starter = 3-page cap).
> REMAINING: Organisms section 14:17, Screens on "Flows", QA. Full node-id
> ledger in the session scratchpad (`dsb-state-rune-ds-001.json`) and mirrored
> in section notes below. NOTE: SF Pro renders zero-width via the plugin API —
> use Inter.

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
| **Favicon** | 15×15 (row) / 20×20 (tile) / 24×24 (start page); image radius 3; fallback = rounded-rect 4, letter 60% size semibold white on tab-color |
| **Toolbar button** | 26×24 hit area, SF Symbol 13pt medium, textSecondary. Variants: sidebar.left, chevron.left, chevron.right, arrow.clockwise, xmark (loading), pip, plus.square — any `Command.icon` |
| **Color dot** | 7×7 circle, tab custom color |
| **Selection bar** | 3×16, radius 2, tab tint (leading edge of selected row) |
| **Section header** | text 11 semibold, textSecondary, h-pad 8; optional trailing text 10 |
| **Star** (Finder, future) | SF star/star.fill 0–5 |

## 3. Molecules

| Component | Spec |
|---|---|
| **Tab row** (`RowBody`) | h 30, h-pad 8, spacing 8, radius = cornerRadius. Layers: Favicon 15 · name (fontSize 13, 1 line) · spacer · color dot · trailing (close xmark 9 bold in 3-pad hover circle). Variants: default / hovering (hover fill) / selected (selection fill or tint@22% + selection bar) / session-with-close |
| **Favicon tile** (favorites) | 34×34, radius = cornerRadius, hover fill; selected = selection fill + 1.5 stroke in tint/accent; Favicon 20 centered |
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
