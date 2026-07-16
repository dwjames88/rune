# Rune roadmap — from surveying Arc, Zen, Vivaldi, Dia, Orion, Safari (2026-07)

What the field considers table stakes vs. flagship, diffed against Rune's
current state. Everything below is implementable with native frameworks only.
Sources: arc.net, zen-browser.app, vivaldi.com/features, diabrowser.com,
kagi.com/orion, apple.com/safari.

Already have (skip): sidebar tabs · persistent web views · themes/presets ·
command palette · shortcut remapping · pop-out video (Auto-PiP) · editable
toolbar · compact address bar · custom search engines · ambient AI (hover
summaries, ⌘J, selection actions, AI address bar) · Finder inspiration library
with system-wide capture.

## Tier 1 — Fundamentals Rune is missing (table stakes everywhere)

1. **Downloads** — nothing handles downloads today. `WKDownloadDelegate`,
   progress in toolbar, toast on finish, "reveal" action; optional "save
   downloads into Finder library" twist.
2. **Find in Page (⌘F)** — native `webView.find(_:)` + a small overlay bar
   (match count, next/prev). Command-registry entry.
3. **Undo Close Tab (⇧⌘T)** — `lastClosedURL` is already tracked; near-free.
4. **⌘-click → background tab** — and popup policy; `adoptPopup` currently
   always foregrounds.
5. **Page zoom (⌘+/−/0)** — `webView.pageZoom`, persisted per host.
6. **Session restore** — setting: reopen last session's tabs (deliberately not
   persisted today; make it a choice).
7. **Private window** — `WKWebsiteDataStore.nonPersistent()`, second window,
   distinct appearance tint.
8. **Print / Save as PDF (⌘P)** — `webView.printOperation` / `createPDF`.
9. **Bookmark import** — read Safari/Chrome bookmark files into Pinned/folders
   (one-time migration sheet in Settings).
10. **Mute tab + audio indicator** — JS media enumeration via PageBridge;
    speaker badge on the tab row.
11. **Apple Passwords / AutoFill** — already committed; needs paid Developer
    Program (same unlock as notarization for sharing builds).

## Tier 2 — Flagship features of the field (aligned with Rune's ethos)

1. **Content blocking** (Vivaldi/Orion/Brave/Safari) — `WKContentRuleList`
   with compiled EasyList + cookie-banner rules. Native, zero deps, huge
   speed/privacy win; later a Safari-style per-page privacy report.
2. **Split View** (Arc/Zen/Vivaldi/Dia) — two tabs side by side;
   `WebContainer` already re-parents live views, split is a natural extension.
   Dia's touch: remember layouts.
3. **Spaces/Workspaces** (Arc/Zen/Vivaldi/Dia) — named contexts with their own
   pinned/session sets + per-space theme (Appearance presets already exist —
   a space is a preset + a tab set).
4. **Glance / Little Arc** (Zen/Arc) — peek a link in a floating temp web view
   (promote to tab or dismiss). Pairs beautifully with the Claude hover
   summary: summary → peek → tab.
5. **Web panels** (Vivaldi) — pin any site as a narrow sidebar panel (chat,
   music, notes).
6. **Tab hibernation** (Vivaldi) — auto-unload background saved tabs after N
   minutes (rows stay; `unload(savedID:)` exists); memory stays tiny.
7. **Reader mode** (Safari/Vivaldi) — PageBridge already extracts article
   text; render natively with Appearance typography. "Save reading to Finder"
   for free.
8. **Auto-archive session tabs** (Arc) — untouched session tabs older than N
   hours close into history (setting; default off).
9. **Per-site settings** — zoom, content-blocker exceptions, auto-PiP
   allowlist, per-site theme override. The Settings machinery is ready.
10. **Named sessions** (Vivaldi) — save/restore a set of tabs ("MTB research").

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

`1.1 Downloads → 1.2 Find in Page → 1.3/1.4/1.5 (small, same session) →
2.1 Content blocking → 2.2 Split View → 1.6/1.7 → 2.3 Spaces → 3.1 Catch-up
brief → 2.4 Glance → rest by appetite.`

Rationale: downloads + find are the two gaps users hit within minutes;
content blocking is the single biggest daily-experience upgrade WebKit gives
us for free; split view + spaces are the flagship pair every modern browser
converged on; then the Claude/Finder moat features nobody else can copy
cheaply.
