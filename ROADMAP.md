# Rune roadmap — from surveying Arc, Zen, Vivaldi, Dia, Orion, Safari (2026-07)

## Versioning

`VERSION` at the repo root is the one source of truth — `dev-run.sh` and
`package.sh` both read it, nothing hardcodes a number.

**v1.00** = Tier 1 complete, and the baseline Tier 2 starts from. Each Tier 2
feature ships as its own **+0.01** (v1.01, v1.02, …): one feature at a time,
verified on device, versioned, then the next. Nothing rolls out half-built.

**v1.1 = Tier 2 complete, and the next public build.** Everything between is a
dev build: committed and versioned, but not packaged or released. v1.01 was the
last thing handed out; the next one people can download is v1.1.

What the field considers table stakes vs. flagship, diffed against Rune's
current state. Everything below is implementable with native frameworks only.
Sources: arc.net, zen-browser.app, vivaldi.com/features, diabrowser.com,
kagi.com/orion, apple.com/safari.

Already have (skip): sidebar tabs · persistent web views · themes/presets ·
command palette · shortcut remapping · pop-out video (Auto-PiP) · editable
toolbar · compact address bar · custom search engines · ambient AI (hover
summaries, ⌘J, selection actions, AI address bar) · Finder inspiration library
with system-wide capture.

## Tier 1 — Fundamentals ✅ DONE (2026-07-16)

All shipped. Kept here as the map of what landed where.

1. **Downloads** — `Downloads.swift`: `WKDownloadDelegate` on `WebCoordinator`,
   `DownloadStore` aggregating progress, toolbar ring + panel (⌥⌘L), toast on
   finish, reveal/open. Destination is a setting: Downloads folder / ask each
   time / straight into the Finder library.
2. **Find in Page (⌘F)** — `FindBar.swift`, native `webView.find(_:)`. No match
   count: `WKFindResult` only reports whether it hit, and counting would mean
   walking the DOM per keystroke. The field turns red instead.
3. **Undo Close Tab (⇧⌘T)** — `closedURLs` stack (25 deep). Unloading a pinned
   tab deliberately doesn't stack: its row never left the sidebar.
4. **⌘-click → background tab** — `decidePolicyFor navigationAction`, plus the
   same rule for popups. ⇧⌘-click foregrounds.
5. **Page zoom (⌘+/−/0)** — `ZoomStore`, keyed by host, applied on commit.
   100% is stored as absence, so `zoom.json` only holds real choices.
6. **Session restore** — setting, off by default. Only URLs are kept.
7. **Private window (⇧⌘N)** — `BrowserModel(isPrivate:)` with a
   `nonPersistent()` store: no history, no persist, no undo stack, no saved
   tabs. Commands aim at the front window's model.
8. **Print / Save as PDF (⌘P)** — `webView.printOperation`; "Save as PDF" is in
   the system panel, so one command covers both.
9. **Bookmark import** — `BookmarkImport.swift`, Safari plist + Chrome JSON.
   Safari's file is behind Full Disk Access; an open panel is the fallback ask.
10. **Mute tab + audio indicator** — PageBridge capture listeners (no observer,
    no polling) + `window.__runeMute`; speaker badge on the row.
11. **No coloured tabs** — colour belongs to folders now. The tab colour dot and
    selection bar are gone; `Folder.colorHex` replaces `SavedTab.colorHex`.

**Deferred:** Apple Passwords / AutoFill — needs the paid Developer Program
(same unlock as notarization for sharing builds).

## Tier 2 — Flagship features of the field (aligned with Rune's ethos)

0. **On-device AI** — ✅ **DONE (v1.01)**. Apple's `FoundationModels` runs every
   AI feature by default: free, offline, and the page never leaves the Mac.
   Claude stays the opt-in upgrade, chosen by one picker in Settings ▸ AI.
   `AI.swift` holds an `AIProvider` protocol both models implement and an
   `AIService` that owns the choice and hides the difference — so every AI
   feature is written once and runs on whatever is there. The framework is
   weak-linked, so Rune still launches on macOS 14/15 with no on-device model.
   Built first on purpose: the Tier 3 AI features are born on the local model
   rather than ported to it.

1. **Content blocking** — ✅ **DONE (v1.02)**. `WKContentRuleList` compiles the
   rules to bytecode once and enforces them in WebKit's own networking path: a
   blocked request is never made and the page pays nothing at runtime.
   `BlockRules` keeps the ruleset as ordinary Swift and generates WebKit's JSON
   from it — a blob would neither diff readably nor resist mis-escaping. The
   compiled list is cached under an identifier carrying the rule version, the
   banner setting and the exception set, and stale compilations are swept.
   Rules attach to the configuration every web view is built from, so private
   windows inherit blocking free.
   - Curated ~55 hosts, not EasyList: EasyList is ABP syntax WebKit doesn't
     speak, and the usual converter is a dependency. **Still open:** an
     ABP→WebKit converter, which drops in behind the same seam.
   - Cookie walls are hidden, not answered — the markup is the page's own, so
     there's no request to stop.
   - **Still open:** the Safari-style per-page privacy report.

2. **⌘T address bar overlay** — ⌘T brings up an address bar rather than
   stacking a blank tab. Note: this is ~90% of the ⌘K palette already, so it
   becomes a *mode* of that palette, not a second overlay to keep in sync.

3. **Split View** — two tabs side by side. `WebContainer` already re-parents
   live views, so the split itself is natural; the real work is that
   `activeTab` stops being unambiguous and commands need a focused pane.
   Dia's touch: remember layouts.

4. **Spaces / Workspaces** — a space = an Appearance preset + its own tab sets.
   The preset half already exists. The biggest refactor in Tier 2: it
   restructures tabs.json, so it needs a migration and a verified round trip.

5. **Glance** — peek a link in a floating temporary view, then promote it to a
   tab or dismiss it. Chains after the hover summary: summary → peek → tab.

6. **Rune Segment (Little Arc)** — a standalone window for a URL opened from
   another app while Rune is the default browser. Like a Safari popup but
   lighter, and the thing that makes a website feel like its own app.
   Shares one primitive with Glance: a floating window hosting a live Tab.

7. **The rest, by appetite** — web panels (pin a chat/music site in the
   sidebar; the same "a Tab rendered somewhere else" primitive again) · tab
   hibernation (`unload(savedID:)` already exists) · reader mode (PageBridge
   extracts the text — but good extraction without a dependency is the one
   place the zero-deps rule actively costs us) · auto-archive stale tabs ·
   named sessions.
   - **Per-site settings** — ✅ **mostly DONE (v1.02)**. `SiteSettings` is one
     host-keyed store for zoom and blocking exceptions; the next per-site thing
     costs a field, not a file. Auto-PiP allowlist and per-site theme are the
     remaining candidates.

## Tier 3 — Rune-only flagships (the moat: Claude + Finder + themes)

1. **Catch-up brief** (Dia's Morning Brief, ambient) — start-page card:
   Claude clusters yesterday's history into "you were researching X" with
   reopen-all buttons. History + findInHistory infra exists.
2. **AI tab organization** (Dia) — one command: name + group current session
   tabs into folders (low-effort Claude call).
3. **Research mode** — "collect this browsing session": tabs + selected
   images/text into a tagged Finder folder; export as moodboard/markdown.
4. **Boosts-lite** (Arc) — per-site CSS/JS snippets (zap annoyances, restyle
   sites) stored data-driven like everything else; PageBridge injects.
5. **Page automations** (Dia skills/Comet) — recorded PageBridge action +
   Claude reasoning ("every morning open these, summarize what changed").
6. **Theme sync with wallpaper/space** — per-Space appearance follows macOS
   appearance or wallpaper accent.

## Suggested build order

Tier 1 is done. From here:

`2.1 Content blocking → 2.2 ⌘T address overlay → 2.3 Split View → 2.4 Spaces →
2.5 FoundationModels → 3.1 Catch-up brief → 2.6 Glance / Segment → rest by
appetite.`

Rationale: content blocking is the single biggest daily-experience upgrade
WebKit gives us for free; split view + spaces are the flagship pair every
modern browser converged on, and both want the same window-model work;
FoundationModels before the Tier 3 AI features so they're built on the local
model from the start rather than ported to it; then the Claude/Finder moat
nobody else can copy cheaply.
