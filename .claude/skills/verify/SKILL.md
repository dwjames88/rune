---
name: verify
description: Build, launch, and drive Rune.app to verify changes on-device
---

# Verifying Rune changes

## Build & launch

```sh
scripts/dev-run.sh          # build → bundle .build/Rune.app → codesign → launch
```

**Gotcha: `open` reuses a running instance.** If Rune is already running,
`dev-run.sh` just fronts the OLD build. Quit first, then relaunch:

```sh
osascript -e 'quit app id "com.dwjames.Rune"' && sleep 2 && open .build/Rune.app
```

(Graceful quit also exercises `applicationWillTerminate` persistence.)

## Driving the UI

- **computer-use**: request access by bundle id `com.dwjames.Rune` — the display
  name "Rune" does not resolve.
- **Synthetic keystrokes via osascript are blocked** on this machine. Use
  computer-use `key`/`type`, or the env hooks: `RUNE_SHOW_PALETTE=1`,
  `RUNE_OPEN_SETTINGS=1`.
- **Alcove** (notch app) owns an invisible window across the top of the screen;
  clicks near the top fail the allowlist check. Move windows down first, e.g.
  `osascript -e 'tell application "System Events" to set position of window "Rune Settings" of process "Rune" to {620, 300}'`
  (window positioning via System Events works; keystrokes don't).

## Picture in Picture specifics

- The PiP window belongs to the system **PIPAgent** process, not Rune, so it is
  **invisible in filtered computer-use screenshots**. Check it via:
  - `osascript -e 'tell application "System Events" to count windows of (every process whose name is "PIPAgent")'` — 1 = PiP active, 0 = not.
  - `screencapture -o -x /tmp/x.png` from Bash captures the full unfiltered
    screen (may include the owner's other windows — don't share raw).
- PiP JS logs: `Tab.requestPiPIfPlaying`/`togglePiP` NSLog their outcome
  (`webkit` / `no-playing-video` / …), visible when launched from a terminal.
- Good test video: `https://www.youtube.com/watch?v=aqz-KE-bpKQ` (Big Buck
  Bunny) — autoplays in Rune's WKWebView without a click.

## Flows worth driving

- Type URL on start page → Return → page loads.
- ⌘T new tab, ⇧⌘[/⇧⌘] tab switch (never reloads), ⌘W close.
- ⌘, Settings; ⌘K palette.
- Auto-PiP: play video → ⌘T → PIPAgent window count 1 → switch back → count 0.
