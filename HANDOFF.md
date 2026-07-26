# Rune — Session Handoff

Everything a fresh session needs to pick this up. Read this + `CLAUDE.md` before touching code.
Last updated **2026-07-25** (v1.16 in development; v1.15 is the public release).

---

## 1. What Rune is

A native macOS browser: **Swift + SwiftUI/AppKit + WebKit (WKWebView)**, **zero third-party
dependencies**, SwiftPM (no Xcode project). Owner: James (GitHub `dwjames88`).
An iOS companion exists in `ios/` but is **hibernated** — see §9.
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
scripts/test-pip.sh           # headless: PiP video-selection logic against a stubbed DOM
```

`test-pip.sh` is the one automated test so far. It pulls the injected script out
of `PageBridge.swift`, fills in the Swift interpolations, and runs it under
`jsc` (which ships with macOS — no node, no dependency). It needs no window and
no network, so it's safe to run while someone is using the Mac. Exit code is
non-zero on failure; verified by breaking a rule on purpose.

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

### `ios/` — hibernated, see §9

## 5. Feature state (v1.16, on `tier-1-fundamentals` and `main`)

**Shipped and verified on-device:** sidebar tabs · persistent web views · favorites / pinned +
folders / session tabs · spaces + profiles · drag & drop · command palette · shortcut
remapping (**and a key monitor so page content can't swallow ⌘K**) · Auto-PiP · content
blocking + cookie-banner hiding · split view · panels · reader · find in page · downloads ·
glance/segment windows · bookmark import · deep appearance customization + presets ·
Liquid Glass · customizable toolbar with wiggle mode + corner kit · **Zen Mode** (full and
subtle, ⌃⌘Z) · **in-app update checks** · **alternate app icons** (drop a `.icon` bundle in
`Assets/Icons`).

**v1.16's big change:** the **Finder library window was removed**. The grab tools stayed —
right-click, ⌥S, ⇧⌘S collect, Capture Page as Image — and all now land in your download
folder through `AssetSaver`. Settings ▸ Browsing ▸ Downloads & Saves picks the folder. Gone
with it: the Finder window, tagging/inspector, Claude auto-tag, the "Save to Rune Finder"
system Service and Quick Action, and the `finderItem` UTI.

**Not started:** Apple Passwords (needs the AutoFill Credential Provider entitlement, which
needs a **paid** Developer Program membership — the same thing notarization waits on).

## 6. Gotchas that will waste your time

- **⌘K *and Escape* never reach Rune from synthetic (computer-use) input on this machine** —
  re-verified 2026-07-25 with an `NSLog` inside the `dismissOnEscape` monitor: it installs,
  a typed character logs a keyDown, Escape logs nothing at all. Real key presses are fine.
  This has twice looked like a real bug (an "unclosable" command palette, a find bar stuck
  ghosted over the page) and twice been the harness. **Clicking the ✕ closes them — that's
  the tell.** Verify the palette via View ▸ Command Palette; dismiss overlays by click.
  Diagnostic when unsure whether a key is broken in-app: launch the binary directly so
  stderr is capturable (`.build/Rune.app/Contents/MacOS/Rune > /tmp/rune.log 2>&1 &`), add a
  temporary NSLog in a local keyDown monitor, and see whether the event arrives at all.
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

The agreed appetite, in order — **Mac only**:

1. **Boosts-lite** (ROADMAP 3.4) — per-site CSS/JS snippets, stored data-driven like
   everything else. `PageBridge` already has the injection seam and `SiteSettings` already
   has the per-host store to hang them on.
2. **Page automations** (ROADMAP 3.5) — recorded PageBridge actions replayed with
   Claude/Apple Intelligence reasoning on top.

## 9. Rune for iOS — hibernated (2026-07-25)

`ios/` holds a working first cut: a phone-shaped Rune whose whole chrome is one floating
bar (page-tinted Liquid Glass), a card tab-switcher that also carries favourites and
folders, a search overlay, and a menu sheet. It builds and runs on the simulator
(`scripts/ios-run.sh`) and on device via `ios/Rune.xcodeproj`.

**It is parked on purpose. Don't spend time on it** unless the owner reopens it — the
appetite is the Mac app. Nothing in the macOS target depends on `ios/`; the root package
is macOS-only and never compiles it.

When it wakes up, the point is **folder + tab sync**: `SyncState` (favourites, folders,
tabs) is already the on-disk shape on both ends, chosen as the wire format. Local network
first (Bonjour + `Network.framework`, zero deps); CloudKit waits on a paid Developer
Program membership. Also outstanding there: real favicons instead of letter chips, and
restoring the previously-selected tab rather than the last one.

**Simulator caveat** (the reason this cost time): under Xcode-beta the CoreSimulator
display freezes seconds after boot and `SimulatorKit.framework` is missing, so the Claude
simulator panel can't attach. Use a device on the stable **iOS 26.5** runtime, or fix it
properly with `sudo xcode-select -s /Applications/Xcode.app` (needs the owner's password).
