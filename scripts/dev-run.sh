#!/bin/bash
# Builds Rune and runs it as a proper .app bundle (WKWebView needs a bundle
# identifier to launch its web content process).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="${1:-debug}"
# One source of truth for the version — packaging reads the same file.
VERSION="$(cat "$REPO_ROOT/VERSION")"
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

# App icon. Dev builds wear the Development icon so they're distinct in the
# Dock from a real install. actool compiles the Icon Composer bundle into
# Assets.car (the layered, appearance-aware icon on macOS 26+) plus a .icns.
ICON_NAME="Development"
ICON_COMPOSER="$REPO_ROOT/Assets/Dev Icon/Development.icon"
ICON_CACHE="$REPO_ROOT/.build/icon"
if [ -d "$ICON_COMPOSER" ] && xcrun --find actool >/dev/null 2>&1; then
    if [ ! -f "$ICON_CACHE/$ICON_NAME.icns" ] || \
       [ -n "$(find "$ICON_COMPOSER" -newer "$ICON_CACHE/$ICON_NAME.icns" 2>/dev/null)" ]; then
        mkdir -p "$ICON_CACHE"
        xcrun actool \
            --app-icon "$ICON_NAME" --include-all-app-icons \
            --compile "$ICON_CACHE" \
            --platform macosx --minimum-deployment-target 26.0 \
            --output-partial-info-plist "$ICON_CACHE/partial.plist" \
            "$ICON_COMPOSER" >/dev/null
    fi
    cp "$ICON_CACHE/Assets.car" "$APP/Contents/Resources/"
    cp "$ICON_CACHE/$ICON_NAME.icns" "$APP/Contents/Resources/"
fi

# Alternate icons the user can pick in Settings. Assets/Icons ships in every
# build; the Dev Icon is added here so it's only selectable in dev builds.
"$REPO_ROOT/scripts/build-icon-options.sh" "$APP" "$REPO_ROOT/Assets/Dev Icon" || true

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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>Development</string>
    <key>CFBundleIconName</key><string>Development</string>
    <key>RuneDevBuild</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
      <dict>
        <key>CFBundleURLName</key><string>Web Address</string>
        <key>CFBundleURLSchemes</key>
        <array><string>http</string><string>https</string></array>
      </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
      <dict>
        <key>UTTypeIdentifier</key><string>com.dwjames.Rune.tab</string>
        <key>UTTypeDescription</key><string>Rune Tab</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        <key>UTTypeTagSpecification</key><dict/>
      </dict>
      <dict>
        <key>UTTypeIdentifier</key><string>com.dwjames.Rune.finderItem</string>
        <key>UTTypeDescription</key><string>Rune Finder Item</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        <key>UTTypeTagSpecification</key><dict/>
      </dict>
      <dict>
        <key>UTTypeIdentifier</key><string>com.dwjames.Rune.control</string>
        <key>UTTypeDescription</key><string>Rune Control Button</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        <key>UTTypeTagSpecification</key><dict/>
      </dict>
    </array>
    <key>NSServices</key>
    <array>
      <dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Save to Rune</string></dict>
        <key>NSMessage</key><string>saveToRuneFinder</string>
        <key>NSPortName</key><string>Rune</string>
        <key>NSRequiredContext</key>
        <dict>
          <key>NSServiceCategory</key><string>public.item</string>
        </dict>
        <key>NSSendTypes</key>
        <array>
          <string>public.file-url</string>
        </array>
      </dict>
      <dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Save to Rune</string></dict>
        <key>NSMessage</key><string>saveToRuneFinderData</string>
        <key>NSPortName</key><string>Rune</string>
        <key>NSSendTypes</key>
        <array>
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
