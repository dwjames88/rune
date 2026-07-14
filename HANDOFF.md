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
hide traffic lights · code signing.

**Built but NOT verified** (needs the owner's Anthropic API key in Settings ▸ Claude):
all four Claude features — link hover summaries, Ask (⌘J), selection actions, AI address bar.

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

---

## 7. Next steps (in the owner's priority order)

### A. Auto Picture-in-Picture — harden it

**Current state:** `Tab.requestPiPIfPlaying()` (in `Browser.swift`) is called on the *outgoing*
tab from `BrowserModel.select(_:)`. It evaluates JS that finds a playing `<video>` and calls
`requestPictureInPicture()`. The web view config also sets the private
`preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")`.

**Why it may not fire:** `HTMLVideoElement.requestPictureInPicture()` normally requires
**transient user activation**. Switching tabs is not a gesture the page sees, so WebKit can
reject the call. This has never been confirmed working — treat it as unproven.

**Suggested plan:**
1. Reproduce: play a YouTube/Vimeo video, switch tabs, watch for a WebKit console error
   (`NotAllowedError`). Add a temporary JS→Swift log through `PageBridge` to see the rejection.
2. Try, in order: (a) the Document Picture-in-Picture API (`documentPictureInPicture.requestWindow()`),
   (b) invoking PiP from inside a real user-gesture handler and keeping the handle, (c) WebKit's
   own media controls / `_WKWebView` SPI if a supported path doesn't exist.
3. Expose it as a setting (`Appearance` or a new `Behavior` struct): **Auto-PiP: off / on tab
   switch / on window blur**, plus a per-site allowlist later.
4. Also wire `webView.closeAllMediaPresentations()` when a tab is closed so PiP windows don't leak.

### B. New tab flow

**Current state:** `BrowserModel.newTab()` creates a blank tab with **no URL**;
`TabContent` shows the native `StartPage` (centered "Rune" + search field) whenever
`urlString.isEmpty && !isLoading`. Deliberately does **not** load a third-party page.

**Where to take it (ask the owner to pick):**
- New-tab behavior setting: blank start page / home URL / duplicate current / last closed.
- Make the start page itself customizable: favorites grid, recent history, custom background
  or color, layout density, optional greeting — all driven from `Appearance`/a new `StartPage`
  config so it round-trips through presets.
- New-tab **placement**: at end vs. next to active (there's already a Helium-era notion of this
  in the owner's head — implement as a setting).
- ⌘T while a start page is already open should focus it rather than pile up empty tabs.
- Consider "open in split" and ⌘-click → background tab (currently popups always foreground —
  see `adoptPopup` in `Browser.swift`).

### C. More layout customization

**Current `Appearance` knobs:** accent, sidebar/toolbar/background colors, font family, font
size, text color (auto-contrast or custom), sidebar width, corner radius, sidebar side,
hide traffic lights.

**Obvious next knobs:**
- **Toolbar**: show/hide individual buttons, compact mode, centered address bar, hide toolbar
  entirely (zen).
- **Sidebar**: row height/density, section order, hide a whole section (e.g. no Favorites),
  collapse-to-icons, auto-hide/overlay mode.
- **Window**: background material/vibrancy, translucency, full-size content behavior.
- **Start page**: see (B).
- **Per-space theming** later, if spaces land.

**How to add a knob (the pattern):** add the field to `Appearance` (Codable → it lands in
presets and `.runetheme` export for free) → surface it in `SettingsWindow.AppearancePane`
→ read it via `AppearanceStore` in the views. If it's an *action* rather than a value, add it
to `Command` instead so it gets a menu item + remappable shortcut automatically.

---

## 8. Suggested first move in the new session

Ask the owner whether they've put an API key in Settings ▸ Claude yet — if yes, verify the four
Claude features actually work before adding anything new. Then start on Auto-PiP (A), since it's
the only *committed* feature still unproven.
