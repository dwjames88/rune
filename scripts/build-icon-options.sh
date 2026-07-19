#!/bin/bash
# Compiles Icon Composer bundles into per-icon .icns under the app's
# Resources/AppIcons — the alternate Dock icons the user can pick in Settings.
# Always includes Assets/Icons; any extra directories passed are compiled too
# (dev-run adds Assets/Dev Icon, so the dev icon is only offered in dev builds).
# Usage: build-icon-options.sh <path-to-.app> [extra-icon-dir ...]
set -euo pipefail

APP="$1"; shift
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
xcrun --find actool >/dev/null 2>&1 || exit 0

DEST="$APP/Contents/Resources/AppIcons"
rm -rf "$DEST"; mkdir -p "$DEST"

# The "Default" tile always shows the main Rune icon, even in dev builds whose
# own bundle icon is the Development one.
MAIN="$REPO_ROOT/Assets/Main Icon/Rune.icon"
if [ -d "$MAIN" ]; then
    tmp="$(mktemp -d)"
    xcrun actool --app-icon "Rune" --include-all-app-icons --compile "$tmp" \
        --platform macosx --minimum-deployment-target 26.0 \
        --output-partial-info-plist "$tmp/p.plist" "$MAIN" >/dev/null 2>&1 || true
    [ -f "$tmp/Rune.icns" ] && cp "$tmp/Rune.icns" "$DEST/Default.icns"
    rm -rf "$tmp"
fi

shopt -s nullglob
for dir in "$REPO_ROOT/Assets/Icons" "$@"; do
    [ -d "$dir" ] || continue
    for icon in "$dir"/*.icon; do
        name="$(basename "$icon" .icon)"
        tmp="$(mktemp -d)"
        xcrun actool \
            --app-icon "$name" --include-all-app-icons \
            --compile "$tmp" \
            --platform macosx --minimum-deployment-target 26.0 \
            --output-partial-info-plist "$tmp/p.plist" \
            "$icon" >/dev/null 2>&1 || { rm -rf "$tmp"; continue; }
        [ -f "$tmp/$name.icns" ] && cp "$tmp/$name.icns" "$DEST/$name.icns"
        rm -rf "$tmp"
    done
done
