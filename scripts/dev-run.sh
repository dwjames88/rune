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
# Release builds ship without symbols — cuts the binary roughly in third.
if [ "$CONFIG" = "release" ]; then
    strip -rSTx "$APP/Contents/MacOS/Rune"
fi

# App icon. Preferred path: compile the Icon Composer bundle (Assets/Rune.icon)
# with actool — produces Assets.car (the real layered icon on macOS 26+) plus a
# legacy Rune.icns. Falls back to sips/iconutil from the 1024px PNG when the
# Xcode tools aren't available. Cached in .build until the source changes.
ICON_COMPOSER="$REPO_ROOT/Assets/Rune.icon"
ICON_SRC="$REPO_ROOT/Assets/Rune-iOS-Default-1024@1x.png"
ICON_CACHE="$REPO_ROOT/.build/icon"
if [ -d "$ICON_COMPOSER" ] && xcrun --find actool >/dev/null 2>&1; then
    if [ ! -f "$ICON_CACHE/Assets.car" ] || \
       [ -n "$(find "$ICON_COMPOSER" -newer "$ICON_CACHE/Assets.car" 2>/dev/null)" ]; then
        mkdir -p "$ICON_CACHE"
        xcrun actool \
            --app-icon Rune --include-all-app-icons \
            --compile "$ICON_CACHE" \
            --platform macosx --minimum-deployment-target 26.0 \
            --output-partial-info-plist "$ICON_CACHE/partial.plist" \
            "$ICON_COMPOSER" >/dev/null
    fi
    cp "$ICON_CACHE/Assets.car" "$ICON_CACHE/Rune.icns" "$APP/Contents/Resources/"
elif [ -f "$ICON_SRC" ]; then
    ICNS="$REPO_ROOT/.build/Rune.icns"
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
    <key>CFBundleIconName</key><string>Rune</string>
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
    <key>NSServices</key>
    <array>
      <dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Save to Rune Finder</string></dict>
        <key>NSMessage</key><string>saveToRuneFinder</string>
        <key>NSPortName</key><string>Rune</string>
        <key>NSSendTypes</key>
        <array>
          <string>public.file-url</string>
          <string>public.url</string>
          <string>public.png</string>
          <string>public.tiff</string>
          <string>NSStringPboardType</string>
        </array>
      </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key><string>Media</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
          <string>public.image</string>
          <string>public.movie</string>
          <string>public.audio</string>
          <string>com.adobe.pdf</string>
        </array>
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
