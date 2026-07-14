#!/bin/bash
# Builds Rune and runs it as a proper .app bundle (WKWebView needs a bundle
# identifier to launch its web content process).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="${1:-debug}"
swift build -c "$CONFIG" >/dev/null
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Rune"

APP="$REPO_ROOT/.build/Rune.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rune"

# App icon: build Rune.icns from the 1024px master with system tools only.
# Cached in .build and regenerated whenever the PNG changes.
ICON_SRC="$REPO_ROOT/Assets/Rune-iOS-Default-1024@1x.png"
ICNS="$REPO_ROOT/.build/Rune.icns"
if [ -f "$ICON_SRC" ]; then
    if [ ! -f "$ICNS" ] || [ "$ICON_SRC" -nt "$ICNS" ]; then
        ICONSET="$(mktemp -d)/Rune.iconset"
        mkdir -p "$ICONSET"
        for size in 16 32 128 256 512; do
            sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
            double=$((size * 2))
            sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
        done
        iconutil -c icns "$ICONSET" -o "$ICNS"
        rm -rf "$(dirname "$ICONSET")"
    fi
    cp "$ICNS" "$APP/Contents/Resources/Rune.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Rune</string>
    <key>CFBundleDisplayName</key><string>Rune</string>
    <key>CFBundleIdentifier</key><string>com.dwjames.Rune</string>
    <key>CFBundleExecutable</key><string>Rune</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleIconFile</key><string>Rune</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
      <dict>
        <key>UTTypeIdentifier</key><string>com.dwjames.Rune.tab</string>
        <key>UTTypeDescription</key><string>Rune Tab</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        <key>UTTypeTagSpecification</key><dict/>
      </dict>
    </array>
</dict>
</plist>
PLIST

# Code-sign with the first available Apple Development identity (falls back to
# ad-hoc). Signing gives Rune a stable identity — the prerequisite for
# integrating system features (Apple Passwords, keychain) directly.
IDENTITY_HASH="$(security find-identity -v -p codesigning | awk 'NR==1 && /[0-9A-F]{40}/ {print $2}')"
if [ -n "$IDENTITY_HASH" ]; then
    echo "› Signing with identity $IDENTITY_HASH"
    codesign --force --sign "$IDENTITY_HASH" --timestamp=none "$APP"
else
    echo "› No Developer identity found — ad-hoc signing"
    codesign --force --sign - "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "› Launching $APP"
open "$APP"
