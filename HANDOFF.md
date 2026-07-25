# Rune — Session Handoff

Everything a fresh session needs to pick this up. Read this + `CLAUDE.md` before touching code.
Last updated **2026-07-25** (v1.16 in development; v1.15 is the public release).

---

## 1. What Rune is

A native macOS browser — and, since v1.16, a companion iOS app: **Swift + SwiftUI/AppKit +
WebKit (WKWebView)**, **zero third-party dependencies**, SwiftPM (no Xcode project on the Mac
side). Owner: James (GitHub `dwjames88`).
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
scripts/dev-run.sh            # macOS debug: build → bundle .app → codesign → launch
scripts/dev-run.sh release
scripts/package.sh            # release build → dist/Rune.app → dist/Rune.zip
scripts/ios-run.sh            # iOS: build → bare .app → install + launch in the simulator
```

**`swift run` will not work** — WKWebView needs a real `.app` bundle (bundle identifier) to
start its web content process. `dev-run.sh` assembles `.build/Rune.app`, writes the
Info.plist, and code-signs.

**If the app won't launch after you edit an Info.plist heredoc**, the plist is probably
malformed — `codesign` still succeeds but launching fails with `Launchd job spawn failed`.
Check `plutil -lint .build/Rune.app/Contents/Info.plist`, and `rm -rf .build/Rune.app`
before rebuilding (a stale bundle keeps a stale signature).

Debug hook: `RUNE_OPEN_SETTINGS=1` opens Settings on launch.

**iOS:** `ios/` is its own SwiftPM package so the root stays a pure macOS build. The
simulator path needs no Xcode project — `swift build --triple arm64-apple-ios17.0-simulator
--sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"` plus a hand-assembled flat `.app`.
Use `--triple`, **not** `-Xswiftc -target` (the latter fails to resolve UIKit). A **device**
build does need a project to code-sign, so `ios/Rune.xcodeproj` is tracked as the one
exception to "no Xcode project":

```sh
xcodebuild -project ios/Rune.xcodeproj -scheme Rune \
  -destination 'platform=iOS,id=<device-udid>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> <built>.app
xcrun devicectl device process launch --device <udid> com.dwjames.Rune.ios
```

## 3. Where state lives

`~/Library/Application Support/Rune/`

| File | Contents |
|---|---|
| `tabs.json` | Profiles, spaces, favorites, pinned, folders, named sessions (session tabs are **not** persisted) |
| `appearance.json` | Current look (the `Appearance` struct) |
| `presets.json` | Saved/imported theme presets |
| `settings.json` | Search engines, AI model, blocking, downloads, tidying, session |
| `history.json` | Browsing history (`HistoryEntry`) |
| `shortcuts.json` | Keyboard shortcut overrides |
| `sites.json` | Per-site zoom + content-blocking exceptions |
| `Finder/` | **Retired.** The pre-v1.16 inspiration library. Nothing reads it any more; it was deliberately left on disk rather than deleted. |

Web session (cookies/logins) lives in `WKWebsiteDataStore.default()`, per profile — that's
why you stay signed in. **The Anthropic API key is in the macOS Keychain**
(`com.dwjames.Rune` / `anthropic-api-key`), never in JSON.
iOS keeps `state.json` (a `SyncState`) in its app Documents directory.

## 4. Source map

### `Sources/Rune/` (macOS)

| File | Role |
|---|---|
| `main.swift` | `AppDelegate`: windows, menu built from the `Command` registry, `dispatch`, the **local key monitor** that makes Rune's shortcuts beat the page, updater wiring |
| `Commands.swift` | **The** command registry. Title, icon, menu section, default shortcut. Add new actions here first. |
| `Browser.swift` | `Tab`, `BrowserModel`, `SavedTab`/`Folder`/`Space`/`Profile`, drag-drop, spaces + profiles, asset grabs |
| `WebCoordinator.swift` | Nav/UI delegate: popups, history, favicons, theme-color sampling, `WKDownloadDelegate` |
| `WebContainer.swift` | `NSViewRepresentable` that re-parents the active tab's web view (no reload on switch) |
| `WebViewMenu.swift` | `RuneWebView` — repairs WebKit's dead "Download Image/Linked File" menu items; `CollectCandidate` |
| `BrowserView.swift` | Sidebar, rows, minimal strip / classic toolbar, address bar + suggestions, start page, split view, corner kit, **Zen reveals**, collect sheet |
| `Appearance.swift` | `Appearance`, `AppearanceStore`, presets, WCAG contrast, `Color(hex:)`, control placement, app icons |
| `Stores.swift` | `Storage`, `DebouncedWrite`, `SiteSettings`, `SearchEngine`, `SettingsStore`, `HistoryStore`, `ShortcutStore`, notification names |
| `SettingsWindow.swift` | Settings: Appearance / Presets / Spaces / Browsing / AI / Shortcuts / **Updates** |
| `Downloads.swift` | `DownloadLocation`, **`AssetSaver`** (the one door every save goes through), `DownloadItem`, `DownloadStore`, toolbar ring, progress card |
| `Updater.swift` | Zero-dependency GitHub-releases check (notify only, never auto-swaps) |
| `ContentBlocker.swift` | `WKContentRuleList` compilation + per-site exceptions |
| `CommandPalette.swift` | ⌘K palette (commands + history + go/search) |
| `Reader.swift` · `FindBar.swift` · `Detached.swift` | Reader mode · ⌘F · glance/segment windows |
| `AI.swift` · `Claude.swift` · `ClaudeUI.swift` | Model routing (on-device FoundationModels ↔ Claude) · raw HTTP + Keychain · hover/selection/Ask UI |
| `PageBridge.swift` | Injected JS: link hover, selection, audio, scroll direction, context target, media collection |
| `SpacesPane.swift` · `BookmarkImport.swift` · `SymbolPicker.swift` · `DragDrop.swift` | Spaces/profiles settings · bookmark import · SF Symbol picker · Transferables |

### `ios/Sources/RuneMobile/` (iOS, new in v1.16)

| File | Role |
|---|---|
| `App.swift` | `@main`, persists on background |
| `Model.swift` | `MobileTab` (owns its web view for life), `MobileStore`, `Favorite`/`Folder`, **`SyncState`** — the shape sync will speak |
| `BrowserScreen.swift` | The one floating bottom bar (page-tinted Liquid Glass), start page |
| `TabSwitcher.swift` | Saved chips (favourites + folders) above snapshot cards |
| `SearchOverlay.swift` · `MenuSheet.swift` · `WebView.swift` · `Theme.swift` | Typing room · action tiles · web container · Rune tokens + `runeGlass` |

## 5. Feature state (v1.16, on `tier-1-fundamentals` and `main`)

**Shipped and verified on-device:** sidebar tabs · persistent web views · favorites / pinned +
folders / session tabs · spaces + profiles · drag & drop · command palette · shortcut
remapping (**and a key monitor so page content can't swallow ⌘K**) · Auto-PiP · content
blocking + cookie-banner hiding · split view · panels · reader · find in page · downloads ·
glance/segment windows · bookmark import · deep appearance customization + presets ·
Liquid Glass · customizable toolbar with wiggle mode + corner kit · **Zen Mode** (full and
subtle, ⌃⌘Z) · **in-app update checks** · **alternate app icons** (drop a `.icon` bundle in
`Assets/Icons`) · **Rune for iOS** (tabs, folders, search, glass chrome).

**v1.16's big change:** the **Finder library window was removed**. The grab tools stayed —
right-click, ⌥S, ⇧⌘S collect, Capture Page as Image — and all now land in your download
folder through `AssetSaver`. Settings ▸ Browsing ▸ Downloads & Saves picks the folder. Gone
with it: the Finder window, tagging/inspector, Claude auto-tag, the "Save to Rune Finder"
system Service and Quick Action, and the `finderItem` UTI.

**Not started:** Apple Passwords (needs the AutoFill Credential Provider entitlement, which
needs a **paid** Developer Program membership — the same thing notarization waits on).

## 6. Gotchas that will waste your time

- **⌘K never reaches Rune from synthetic input on this machine** — verified with an event
  monitor: ⌘J arrives, ⌘K doesn't. Real key presses are fine (the owner remapped it and
  confirmed it works). Verify the palette via View ▸ Command Palette when automating.
- **`open` (and `dev-run.sh`) reuses a running instance** — you'll be looking at the old
  build. Quit first: `osascript -e 'quit app "Rune"'`.
- **computer-use: request access by the display name "Rune"** (bundle id also works).
- **The iOS simulator on this Mac is half-broken under Xcode-beta.** `xcode-select -p` points
  at `/Applications/Xcode-beta.app`, whose CoreSimulator freezes the display seconds after
  boot and whose `SimulatorKit.framework` is missing (so the Claude simulator panel can't
  attach). Workaround: `DEVELOPER_DIR=/Applications/Xcode.app/...` plus a device on the
  **stable iOS 26.5 runtime**. The real fix needs the owner's password:
  `sudo xcode-select -s /Applications/Xcode.app`.
- **The PiP window belongs to `PIPAgent`**, not Rune — invisible in filtered computer-use
  screenshots, and it blocks clicks beneath it.
- **Claude / Sonnet 5 API rules** (`claude-sonnet-5`): `temperature`/`top_p`/`top_k` are
  **rejected (400)**; adaptive thinking is on by default — we disable it and set
  `output_config.effort` low/medium so the ambient UI stays fast. Always check
  `stop_reason == "refusal"` before reading `content`. Load the `claude-api` skill first.
- See `.claude/skills/verify/SKILL.md` for the on-device verification recipe.

## 7. Release flow

Versions track tiers, not sequence — **don't infer the next number from git log**; `VERSION`
is the source of truth (no trailing newline). Feature versions get a GitHub Release with the
zip; patch bumps don't.

```sh
printf '1.16' > VERSION
# commit on tier-1-fundamentals (poetic house-voice subject), then:
git checkout main && git merge --no-ff tier-1-fundamentals && git push origin main
scripts/package.sh
gh release create v1.16 --target main --title "…" --notes-file … dist/Rune.zip
```

No `--draft`/`--prerelease`: the in-app updater reads `releases/latest`, so a draft would be
invisible to it. Builds are **ad-hoc signed, not notarized** — first launch needs
right-click ▸ Open, worth repeating in every release note.

## 8. Where to pick up

**v1.16 is committed and pushed but deliberately not released.** The Finder removal is a
visible feature loss, so the owner should run it before it reaches anyone who downloaded
v1.15. To ship: bump `VERSION`, then follow §7.

The agreed appetite after that, in order:

1. **Boosts-lite** (ROADMAP 3.4) — per-site CSS/JS snippets, stored data-driven like
   everything else. `PageBridge` already has the injection seam and `SiteSettings` already
   has the per-host store to hang them on.
2. **Page automations** (ROADMAP 3.5) — recorded PageBridge actions replayed with
   Claude/Apple Intelligence reasoning on top.
3. **Folder + tab sync** (ROADMAP 4.1) — the reason the iOS app exists. `SyncState` is
   already the on-disk shape on both ends. Local network first (Bonjour +
   `Network.framework`, zero deps); CloudKit waits on the Developer Program.
