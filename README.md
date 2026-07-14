# Wisp

An open-source, absurdly customizable, extremely light macOS browser — native
Swift + WebKit. Meant to feel natural and fun, and to be *better than Safari*
by getting out of your way.

> **Wisp** is a working codename — easy to rename later.

## Principles

- **Native & light.** Pure Swift, SwiftUI + AppKit, WebKit for content. Zero
  third-party dependencies.
- **A setting for everything.** Behavior is data-driven so it can be exposed
  and remapped — starting with the [command registry](Sources/Wisp/Commands.swift).
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
- **Navigation** — address bar (URL or DuckDuckGo search), back/forward/reload,
  `target=_blank` opens a new tab
- **Command registry → menu → keyboard shortcuts**, every command in one place:

  | Command | Shortcut |
  |---|---|
  | New Tab | ⌘T |
  | Close Tab | ⌘W |
  | Reload | ⌘R |
  | Back / Forward | ⌘[ / ⌘] |
  | Open Location | ⌘L |
  | Toggle Sidebar | ⌥⌘S |
  | Pin / Unpin Tab | ⌘D |
  | Next / Previous Tab | ⇧⌘] / ⇧⌘[ |

## Roadmap (the required features)

- [ ] **Full keyboard remapping** — a settings screen over the command registry, plus a command palette
- [ ] **Auto Picture-in-Picture** — hook is wired (`Tab.requestPiPIfPlaying` on switch); make it robust
- [ ] **Apple Passwords integration** — AutoFill credential provider + entitlements
- [ ] **Links-as-apps, fully** — persistent pinned apps, per-app state, smooth switching
- [ ] **Settings for everything** — theming, layout, sidebar side/width, new-tab behavior
- [ ] Security UI — padlock, certificate sheet, bad-cert interstitial

## Layout

```
Sources/Wisp/
  main.swift          # app bootstrap + menu built from the command registry
  Browser.swift       # Tab (persistent web view) + BrowserModel
  WebCoordinator.swift# navigation/UI delegate (popups; TLS/security hooks)
  WebContainer.swift  # re-parents the active tab's web view (no reload on switch)
  Commands.swift      # the one command registry
  BrowserView.swift   # SwiftUI sidebar + content + address bar
  Theme.swift         # soft, native design tokens
```
