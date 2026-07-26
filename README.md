# Rune

An open-source, absurdly customizable, extremely light macOS browser — native
Swift + WebKit. Meant to feel natural and fun, and to be *better than Safari*
by getting out of your way.

> **Rune** is a working codename — easy to rename later.

**[Download the latest release →](https://github.com/dwjames88/rune/releases/latest)**
· ~3 MB · macOS 14+ · ad-hoc signed, so right-click ▸ Open the first time.

## Principles

- **Native & light.** Pure Swift, SwiftUI + AppKit, WebKit for content. Zero
  third-party dependencies.
- **A setting for everything.** Behavior is data-driven so it can be exposed
  and remapped — starting with the [command registry](Sources/Rune/Commands.swift).
- **Links as applications.** Each tab owns its web view for life, so switching
  tabs never reloads — you return to a page like an app, not re-open a bookmark.
- **Secure by default.** WebKit validates TLS against the system trust store;
  we never weaken it.
- **AI is ambient, not a chatbot.** There when you reach for it, invisible
  otherwise. On-device by default; Claude is the upgrade you opt into.

## Run

```sh
scripts/dev-run.sh          # build + launch as a .app (WKWebView needs a bundle)
scripts/package.sh          # release build → dist/Rune.zip
```

## What works now

**Tabs & windows** — sidebar tabs with Favorites (≤6 favicon tiles), Pinned +
Folders, and disposable session tabs · **Spaces** (each with its own shelf and
optional theme) and **Profiles** (separate cookie jars, so two accounts on one
site don't collide) · **Split view** · a **panel** for a site pinned beside your
tabs · **Glance/Segment** windows (⇧-click a link to peek) · private windows ·
drag & drop everywhere · undo close (⇧⌘T).

**Getting around** — command palette (⌘K) over commands, history and search ·
an address bar that predicts from history · find in page (⌘F) · reader mode
(⇧⌘R) · per-site zoom that's remembered · bookmark import from Safari/Chrome/
Firefox.

**Making it yours** — colors, fonts, radius, transparency, blur, grain, sidebar
side and width, start page, traffic lights · savable and shareable
`.runetheme` presets · a **toolbar you take apart**: every control drags
between two clusters beside the address and a corner kit behind a grab tab
(View ▸ Customize Controls) · **Zen Mode** (⌃⌘Z) in two flavors — nothing but
the page, or a quiet address band that wears the site's own colour · alternate
app icons · **remap any shortcut**, with a key monitor so page content can't
swallow them.

**The web, handled** — content blocking (ads, trackers, cookie banners) with
per-site exceptions · Auto Picture-in-Picture · downloads with live progress ·
image grabs (right-click, ⌥S, ⇧⌘S to collect a page, or capture the page
itself) all landing in one folder you choose · in-app update checks.

**Ambient AI** — link hover summaries, selection Explain/Summarize/Translate,
Ask about this page (⌘J), and an address bar that can find a page you only
half-remember. On-device via Apple Intelligence where available; Claude with
your own API key otherwise.

**Default shortcuts** (all remappable in Settings ▸ Shortcuts):

| Command | Shortcut |  | Command | Shortcut |
|---|---|---|---|---|
| Command Palette | ⌘K |  | Open Location | ⌘L |
| New Tab | ⌘T |  | Toggle Sidebar | ⌥⌘S |
| Close Tab | ⌘W |  | Pin / Unpin Tab | ⌘D |
| Reload | ⌘R |  | Next / Prev Tab | ⇧⌘] / ⇧⌘[ |
| Back / Forward | ⌘[ / ⌘] |  | Settings | ⌘, |
| Find in Page | ⌘F |  | Reader | ⇧⌘R |
| Ask About This Page | ⌘J |  | Zen Mode | ⌃⌘Z |
| Split View | ⌥⌘\ |  | Downloads | ⌥⌘L |

## Roadmap

- [x] **Command palette + shortcut remapping**
- [x] **Custom search engines + native blank start page + web memory**
- [x] **Deep customization** — colors, fonts, radius, sidebar, Liquid Glass,
      Zen Mode; savable/shareable `.runetheme` presets
- [x] **Tab organization** — Favorites, Pinned + Folders, session tabs, Spaces,
      Profiles, split view
- [x] **Auto Picture-in-Picture**
- [x] **Content blocking** — ads, trackers, cookie banners, per-site exceptions
- [x] **Ambient AI** — on-device or Claude
- [x] **Security UI** — padlock, certificate sheet, bad-cert interstitial
      (additive only: system TLS validation is untouched, and there is no
      "proceed anyway")
- [x] **App signing** + in-app update checks
- [ ] **Boosts-lite** — per-site CSS/JS tweaks, data-driven like everything else
- [ ] **Page automations** — recorded actions replayed with AI reasoning
- [ ] **Apple Passwords integration** — AutoFill credential provider (needs a
      paid Developer Program membership, which notarization also waits on)

See [ROADMAP.md](ROADMAP.md) for the full map and [HANDOFF.md](HANDOFF.md) for
how the code is laid out.

## Layout

```
Sources/Rune/
  main.swift           # bootstrap, menu from the command registry, dispatch, key monitor
  Commands.swift       # the one command registry — every action starts here
  Browser.swift        # Tab (persistent web view), BrowserModel, spaces + profiles
  BrowserView.swift    # sidebar, chrome, address bar, start page, split, Zen
  WebCoordinator.swift # navigation/UI delegate (popups, history, downloads, TLS)
  WebContainer.swift   # re-parents the active tab's web view (no reload on switch)
  WebViewMenu.swift    # context-menu repairs for WebKit's dead download items
  Appearance.swift     # the Appearance struct, presets, contrast, control placement
  Stores.swift         # settings, per-site state, history, shortcuts (persisted)
  Downloads.swift      # AssetSaver — the one door every save goes through
  SettingsWindow.swift # Appearance / Presets / Spaces / Browsing / AI / Shortcuts / Updates
  CommandPalette.swift # ⌘K palette
  ContentBlocker.swift # WKContentRuleList compilation + exceptions
  AI.swift, Claude.swift, ClaudeUI.swift, PageBridge.swift
  Reader.swift, FindBar.swift, Detached.swift, Updater.swift
```

An iOS companion lives in `ios/` and is currently hibernated — see HANDOFF §9.
