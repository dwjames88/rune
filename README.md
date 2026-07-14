# Rune

An open-source, absurdly customizable, extremely light macOS browser — native
Swift + WebKit. Meant to feel natural and fun, and to be *better than Safari*
by getting out of your way.

> **Rune** is a working codename — easy to rename later.

## Principles

- **Native & light.** Pure Swift, SwiftUI + AppKit, WebKit for content. Zero
  third-party dependencies.
- **A setting for everything.** Behavior is data-driven so it can be exposed
  and remapped — starting with the [command registry](Sources/Rune/Commands.swift).
- **Links as applications.** Each tab owns its web view for life, so switching
  tabs never reloads — you return to a page like an app, not re-open a bookmark.
- **Secure by default.** WebKit validates TLS against the system trust store;
  we never weaken it.

## Run

```sh
scripts/dev-run.sh          # build + launch as a .app (WKWebView needs a bundle)
```

## What works now (foundation)

- **Sidebar tabs** — pinned "Apps" and regular "Tabs", live titles/loading,
  hover-to-close, right-click to pin/close
- **Persistent web views** — switching tabs keeps pages alive (audio, video, state)
- **Native start page** — a blank page with a centered search bar; new tabs
  never load a third-party site
- **Web memory** — you stay signed in across launches (persistent site data),
  and browsing history is recorded (searchable in the palette)
- **Customizable search engine** — DuckDuckGo, Google, Bing, Brave, Kagi
- **Command palette** (⌘K) — fuzzy-run any command, jump to history, or search
- **Shortcut remapping** — rebind any command in Settings (⌘,); the menu and
  palette update live. Defaults:

  | Command | Shortcut |  | Command | Shortcut |
  |---|---|---|---|---|
  | Command Palette | ⌘K |  | Open Location | ⌘L |
  | New Tab | ⌘T |  | Toggle Sidebar | ⌥⌘S |
  | Close Tab | ⌘W |  | Pin / Unpin Tab | ⌘D |
  | Reload | ⌘R |  | Next / Prev Tab | ⇧⌘] / ⇧⌘[ |
  | Back / Forward | ⌘[ / ⌘] |  | Settings | ⌘, |

## Roadmap (the required features)

- [x] **Command palette + shortcut remapping**
- [x] **Custom search engine + native blank start page + web memory**
- [x] **Deep customization** — colors, fonts, radius, sidebar, hide traffic lights; savable/shareable `.runetheme` presets (Settings ▸ Appearance / Presets)
- [x] **Tab organization** — Favorites (≤6, favicon tiles), Pinned + Folders, Session tabs; per-tab custom name & color; favicons everywhere
- [x] **App signing** — Apple Development identity (every build signs)
- [ ] **Apple Passwords integration** — AutoFill credential provider (needs signing + entitlements)
- [ ] **Auto Picture-in-Picture** — hook is wired (`Tab.requestPiPIfPlaying` on switch); make it robust
- [ ] **Links-as-apps, fully** — persistent pinned apps, per-app state, smooth switching
- [ ] **Settings for everything** — theming, layout, sidebar side/width, new-tab behavior
- [ ] Security UI — padlock, certificate sheet, bad-cert interstitial

## Layout

```
Sources/Rune/
  main.swift          # app bootstrap + menu built from the command registry
  Browser.swift       # Tab (persistent web view) + BrowserModel
  WebCoordinator.swift# navigation/UI delegate (popups, history; TLS/security hooks)
  WebContainer.swift  # re-parents the active tab's web view (no reload on switch)
  Commands.swift      # the one command registry
  Stores.swift        # settings, search engine, history, shortcut overrides (persisted)
  CommandPalette.swift# ⌘K palette (commands + history + go/search)
  SettingsWindow.swift# settings: search engine + shortcut remapping (key recorder)
  BrowserView.swift   # SwiftUI sidebar + content + address bar + start page
  Theme.swift         # soft, native design tokens
```
