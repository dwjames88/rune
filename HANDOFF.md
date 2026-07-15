# Rune — Session Handoff

Everything a fresh session needs to pick this up. Read this + `CLAUDE.md` before touching code.

---

## 1. What Rune is

A native macOS browser: **Swift + SwiftUI/AppKit + WebKit (WKWebView)**, **zero third-party
dependencies**, SwiftPM (no Xcode project). Owner: James (GitHub `dwjames88`).
Repo: <https://github.com/dwjames88/rune> · Local: `~/Developer/rune`

**Non-negotiables** (from the owner, repeated across sessions):

- **Swift only, zero dependencies.** Native frameworks over libraries. Keep it light.
- **A setting for everything.** "This browser should be 100% mine." Prefer data-driven
  behavior that can be exposed in the UI. New user actions go through `Command` in
  `Commands.swift` — never hard-wire a shortcut or menu item elsewhere.
- **Links as applications.** A tab owns its `WKWebView` for life; switching must never
  reload. Don't recreate web views on selection.
- **Secure by default.** Never weaken TLS. System validation stays the default.
- **Claude is ambient, not a chatbot.** "There when I need it," no chat sidebar.

## 2. Build & run

```sh
scripts/dev-run.sh            # debug: build → bundle .app → codesign → launch
scripts/dev-run.sh release
```

**`swift run` will not work** — WKWebView needs a real `.app` bundle (bundle identifier) to
start its web content process. `dev-run.sh` assembles `.build/Rune.app`, writes the
Info.plist (incl. the `com.dwjames.Rune.tab` UTI used by drag & drop), and code-signs with
the first available **Apple Development** identity (ad-hoc fallback).

Debug hooks (env-gated, harmless):
`RUNE_SHOW_PALETTE=1` opens the command palette on launch · `RUNE_OPEN_SETTINGS=1` opens Settings.

## 3. Where state lives

`~/Library/Application Support/Rune/`

| File | Contents |
|---|---|
| `tabs.json` | Favorites, pinned tabs, folders (session tabs are **not** persisted) |
| `appearance.json` | Current look (the `Appearance` struct) |
| `presets.json` | Saved/imported theme presets |
| `settings.json` | Search engine + custom engines |
| `history.json` | Browsing history (`HistoryEntry`) |
| `shortcuts.json` | Keyboard shortcut overrides |

Web session (cookies/logins) lives in `WKWebsiteDataStore.default()` — that's why you stay
signed in. **Anthropic API key is in the macOS Keychain** (`com.dwjames.Rune` /
`anthropic-api-key`), never in JSON.

## 4. Source map (`Sources/Rune/`)

| File | Role |
|---|---|
| `main.swift` | `AppDelegate`: window, menu built from the `Command` registry, dispatch, traffic-light hiding, save-on-quit |
| `Commands.swift` | **The** command registry. Title, icon, menu section, default shortcut. Add new actions here first. |
| `Browser.swift` | `Tab` (live web view), `BrowserModel`, `SavedTab`/`Folder`, `Selection`, `DropTarget`, drag-drop handling, `findInHistory` (Claude) |
| `WebCoordinator.swift` | Nav/UI delegate: popups → new tabs, history recording, favicon fetch, page-bridge messages |
| `WebContainer.swift` | `NSViewRepresentable` that re-parents the active tab's web view (no reload on switch) |
| `BrowserView.swift` | Sidebar (favorites/pinned+folders/session), rows, toolbar, address bar + suggestions, start page, Claude overlays |
| `Appearance.swift` | `Appearance` struct, `AppearanceStore`, presets, WCAG contrast helpers, `Color(hex:)` |
| `Stores.swift` | `Storage`, `SearchEngine`, `SettingsStore`, `HistoryStore` (incl. `predict`/`isConfident`), `Shortcut`/`ShortcutStore`, notification names |
| `SettingsWindow.swift` | Settings: Appearance / Presets / Browsing / Claude / Shortcuts + key recorder |
| `CommandPalette.swift` | ⌘K palette (commands + history + go/search) |
| `SymbolPicker.swift` | SF Symbol grid + free-text (any symbol name) — used for folder icons |
| `DragDrop.swift` | `TabDrag` Transferable + `UTType.runeTab` |
| `Claude.swift` | `ClaudeService` (raw HTTP Messages API) + `Keychain` |
| `ClaudeUI.swift` | Link hover popover, selection actions, Ask bar (⌘J), summary cache |
| `PageBridge.swift` | Injected JS (link hover + selection), page-text extraction, HTML→text fetcher |
| `Theme.swift` | Legacy static tokens — **only** `CommandPalette` still uses these. Migrate it to `AppearanceStore` when convenient. |

## 5. Feature state

**Working and verified on-device:**
sidebar tabs · persistent web views (no reload on switch) · Favorites (≤6) / Pinned + Folders /
Session tabs · drag & drop (reorder, into folders, drag-to-pin/favorite) · per-tab name + full
color · SF Symbol folder icons · favicons · command palette (⌘K) · shortcut remapping ·
auto-predict address bar · native blank start page · persistent login + history · custom search
engine · deep appearance customization + shareable `.runetheme` presets · WCAG auto-contrast ·
hide traffic lights · code signing · **Auto-PiP** (verified 2026-07-14: enter on tab switch,
return-inline on switch back, manual ⌥⌘P toggle, no PiP leak on tab close) · **app icon**
(dev-run.sh compiles `Assets/Rune.icon` with **actool** → `Assets.car` + legacy `Rune.icns`
+ `CFBundleIconName`; sips/iconutil PNG fallback if actool is missing) · **custom app icon
setting** (Appearance ▸ App Icon: `AppIconRenderer` draws the rune glyph polygon natively in
any colors, applied via `NSApp.applicationIconImage`, off = bundled icon — verified in Dock) · **new-tab flow** (behavior: start page /
home / duplicate / last closed; placement: end / next-to-active; ⌘T focuses an existing start
page instead of stacking — verified) · **customizable start page** (greeting, favorites grid,
recents, background — in `Appearance`, round-trips presets) · **customizable toolbar**
(`Appearance.toolbarButtons` = command rawValues rendered as dispatch buttons — verified live)
· **compact address bar** (host-only until clicked — verified) · **window restores last
size, clamped to 900×600 min** (`NSHostingController.sizingOptions = []` was the fix for the
tiny-launch-window bug: SwiftUI was shrinking the window to its ideal size, and that frame
got autosaved).

**Claude features — all four verified on-device 2026-07-14** (owner's API key is in the
Keychain): link hover summaries · selection Explain/Summarize/Translate · Ask bar (⌘J,
streams, answers honestly when the page lacks the answer) · AI address bar ("that yeti
enduro bike review" → found and opened the right history page). Also shipped + verified:
**configurable hover delay** (Settings ▸ Claude ▸ Link Previews: on/off + 0.1–2.0 s slider;
baked into the injected PageBridge script for new pages, pushed live to open pages via
`window.__runeHoverMs` / `__runeHoverOff` — see `BrowserModel.applyHoverSettings`).

**Not started:** Apple Passwords (needs the AutoFill Credential Provider entitlement — likely
requires a **paid** Apple Developer Program membership; confirm enrollment before starting).

## 6. Gotchas that will waste your time

- **Can't send synthetic keystrokes.** `osascript` keystroke is blocked ("not allowed to send
  keystrokes"). Use the env hooks above, or computer-use.
- **computer-use: request access by bundle id `com.dwjames.Rune`.** The display name "Rune"
  does not resolve.
- **Alcove** (the owner's notch app) has an invisible window across the top of the screen; clicks
  near the top of the display get rejected. Move the Rune window down before automating.
- **Claude / Sonnet 5 API rules** (model id `claude-sonnet-5`): `temperature`/`top_p`/`top_k` are
  **rejected (400)**; adaptive thinking is **on by default** — we set `thinking: {"type":"disabled"}`
  + `output_config.effort` low/medium so the ambient UI stays fast. Always check
  `stop_reason == "refusal"` before reading `content`. Load the `claude-api` skill before editing
  anything that calls the API.
- **Screenshots:** `screencapture -o -x /tmp/x.png` from Bash works and bypasses compositor
  filtering; `sips -c H W --cropOffset Y X` to crop.
- **`open` (and dev-run.sh) reuses a running Rune instance** — you'll be looking at the old
  build. Quit first: `osascript -e 'quit app id "com.dwjames.Rune"'` (window positioning via
  System Events also works; only keystrokes are blocked).
- **The PiP window belongs to the system `PIPAgent` process**, not Rune, so it's invisible in
  filtered computer-use screenshots. Check it with: `tell application "System Events" to count
  windows of (every process whose name is "PIPAgent")` — 1 = PiP active, 0 = not.
- See `.claude/skills/verify/SKILL.md` for the full on-device verification recipe.

---

## 7. Next steps (in the owner's priority order)

### A. Auto Picture-in-Picture — ✅ DONE (2026-07-14, verified on-device)

**Root cause was not user activation:** WebKit never implemented the W3C PiP API —
`document.pictureInPictureEnabled` is `undefined` in WKWebView, so the old JS condition
silently never fired. WebKit's real API is `video.webkitSetPresentationMode('picture-in-picture')`,
which needs no gesture. `Tab` (Browser.swift) now uses it (W3C kept as fallback) and NSLogs
each attempt's outcome.

**Shipped:** Auto-PiP setting in Settings ▸ Browsing ▸ Media (`AutoPiPMode` in Stores.swift:
off / tab switch / tab switch + leaving Rune, via `applicationDidResignActive`) · "return
video to the page when you come back" toggle (`exitPiPIfActive` on select) · manual
`togglePiP` Command (⌥⌘P, View menu) · `closeAllMediaPresentations` on tab close/unload
(no PiP leak — verified). Possible later: per-site allowlist.

### B. New tab flow — ✅ DONE (2026-07-14, verified on-device)

Shipped: `NewTabBehavior` + `NewTabPlacement` in Stores.swift, surfaced in
Settings ▸ Browsing ▸ New Tabs · `lastClosedURL` tracked on close/unload · ⌘T focuses an
existing empty start page (`.focusStartPage` notification) instead of stacking · start page
customization (greeting, favorites grid, recents, background) via `Appearance` fields.

**Still open from B:** "open in split" and ⌘-click → background tab (popups always
foreground — see `adoptPopup` in `Browser.swift`).

### C. More layout customization — toolbar part ✅ DONE (2026-07-14)

Shipped: `Appearance.toolbarButtons` (any Command as a toolbar button, user-composable,
verified live) · `compactAddressBar` (host-only display until clicked) · **Appearance now
decodes with per-field defaults** (`init(from:)` with `decodeIfPresent`), so adding knobs
never resets saved themes — but note the memberwise init is gone; build presets by mutating
`var a = Appearance()`.

**Remaining knob ideas:**
- **Toolbar**: reorder buttons (currently check-order), centered address bar, hide toolbar
  entirely (zen).
- **Sidebar**: row height/density, section order, hide a whole section (e.g. no Favorites),
  collapse-to-icons, auto-hide/overlay mode.
- **Window**: background material/vibrancy, translucency, full-size content behavior.
- **Per-space theming** later, if spaces land.

**How to add a knob (the pattern):** add the field to `Appearance` (Codable → it lands in
presets and `.runetheme` export for free) → surface it in `SettingsWindow.AppearancePane`
→ read it via `AppearanceStore` in the views. If it's an *action* rather than a value, add it
to `Command` instead so it gets a menu item + remappable shortcut automatically.

---

### D2. Finder UI + capture flows — ✅ DONE (2026-07-15, verified on-device)

`FinderView.swift`: the library is a **separate window** (`FinderWindowController`,
frame-autosaved, ⌥⌘F toggles, sidebar button + **Finder menu**; ⌘W closes the
window when it's key — see `dispatch(.closeTab)`; double-click fronts the browser
window via `.frontBrowserWindow`) — rail (All/Images/Videos/Starred +
folders CRUD + tag list), adaptive thumbnail grid (double-click opens source,
context menu: reveal/star/trash), inspector (rename, 0–5 stars, tags, note,
folder membership, custom key/value fields, dominant-color swatches, source
link). Capture: ⌥S save-media-under-cursor (`window.__runeMedia`), ⇧⌘S batch
collect (JS page scan → native sheet with live previews, min-size setting,
shared tags), Capture Page (WKWebView.takeSnapshot). Optional **Claude
auto-tag** (Settings ▸ Browsing ▸ Finder, off by default; text-context, effort
low). Verified: grid/inspector edits persist to item.json, batch-collected 5
tagged items from Pinkbike, tag filter works. **System-wide capture
(2026-07-15, verified)**: macOS Service "Save to Rune Finder" (NSServices in the
Info.plist heredocs of BOTH dev-run.sh and package.sh; `NSApp.servicesProvider`
+ `saveToRuneFinder(_:userData:error:)` in main.swift) takes files, copied
images, URLs, and selected text from any app's right-click ▸ Services menu ·
"Open With Rune"/dock drops import files (CFBundleDocumentTypes + 
`application(_:open:)`; web URLs open as tabs) · drag anything onto the Finder
window grid. Test recipe: NSPerformService("Save to Rune Finder", pboard) from
`swift -e`. If the Services item doesn't show: System Settings ▸ Keyboard ▸
Keyboard Shortcuts ▸ Services. Remaining ideas: smart folders, drag-out
capture, video thumbnails, full-page (paginated) capture.

### D. Finder (inspiration library) — phase 1 ✅ DONE (2026-07-14, verified)

See **`FINDER.md`** for the full spec (Eagle-style). Shipped and verified on-device:
`Finder.swift` — `FinderStore` (library at `…/Rune/Finder/items/<uuid>/` with
original + thumb.png + self-describing item.json, tolerant decoding), save
pipeline (URLSession download with Referer, UTType kind detection, dimensions,
dominant-color extraction, 512px thumbnail), `RuneWebView.willOpenMenu` adds
**"Save Image/Video to Rune Finder"** (PageBridge posts the media element on
`contextmenu`), toast feedback in ContentArea.

**Next phases** (FINDER.md §3): Finder UI surface (grid + folders/tags rail +
inspector) → batch collect + page capture → smart folders/custom fields UI →
Claude auto-tagging. `FinderFolder` + `allTags` already exist in the store.

### E. Figma component library — blocked on Figma MCP auth

Owner wants the UI mirrored into
<https://www.figma.com/design/Kmi2f7MKB8zKv209g9RXi4/Rune> as a component
library (tokens → smallest components → composed screens) so they can rearrange
in Figma. Blocked until the Figma connector is authorized (claude.ai connector
settings). Load skills figma-use + figma-generate-library + figma-swiftui first.

## 8. Suggested first move in the new session

Everything committed through the app-icon work is verified; Claude features are verified
too. Pick up the remaining items in (B)/(C) above (⌘-click background tabs, split view,
sidebar/window knobs, toolbar reorder), or Apple Passwords if Developer Program enrollment
is sorted. Read `.claude/skills/verify/SKILL.md` before driving the app.
