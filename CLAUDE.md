# Wisp

Open-source, extremely light, insanely customizable native macOS browser.
Swift + SwiftUI/AppKit + WebKit (WKWebView). Codename "Wisp".

## Non-negotiables

- **Swift only, zero dependencies.** SwiftPM, no Xcode project. Native
  frameworks over third-party libraries. Keep the binary small.
- **A setting for everything.** Prefer data-driven behavior that can be exposed
  and remapped. New user-invokable actions go through `Command` in
  `Commands.swift` — never hard-wire a shortcut or menu item elsewhere.
- **Links as applications.** A tab owns its `WKWebView` for life; switching
  must never reload. Don't recreate web views on selection.
- **Secure by default.** Never weaken TLS. System validation stays the default;
  security UI is additive.

## Build & run

- `scripts/dev-run.sh [debug|release]` — builds and launches as a `.app`
  (WKWebView requires a bundle identifier to start its content process; a bare
  `swift run` binary will not load pages reliably).

## Required features (see README roadmap)

Full keyboard remapping + command palette, Auto-PiP, Apple Passwords, and the
links-as-apps model are the committed features. Build toward them.
