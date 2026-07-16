#!/bin/bash
# Packages Rune for sharing: release build → dist/Rune.app → dist/Rune.zip.
# Separate from dev-run.sh so packaging never clobbers the .app you're running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Defaults to the VERSION file; pass an argument to override for a one-off.
VERSION="${1:-$(cat "$REPO_ROOT/VERSION")}"

echo "› Building release"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/Rune"

APP="$REPO_ROOT/dist/Rune.app"
rm -rf "$REPO_ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rune"
strip -rSTx "$APP/Contents/MacOS/Rune"

# App icon: Icon Composer bundle via actool (Assets.car + legacy icns).
ICON_COMPOSER="$REPO_ROOT/Assets/Rune.icon"
ICON_TMP="$(mktemp -d)"
if [ -d "$ICON_COMPOSER" ] && xcrun --find actool >/dev/null 2>&1; then
    xcrun actool \
        --app-icon Rune --include-all-app-icons \
        --compile "$ICON_TMP" \
        --platform macosx --minimum-deployment-target 26.0 \
        --output-partial-info-plist "$ICON_TMP/partial.plist" \
        "$ICON_COMPOSER" >/dev/null
    cp "$ICON_TMP/Assets.car" "$ICON_TMP/Rune.icns" "$APP/Contents/Resources/"
fi
rm -rf "$ICON_TMP"

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

IDENTITY_HASH="$(security find-identity -v -p codesigning | awk 'NR==1 && /[0-9A-F]{40}/ {print $2}')"
if [ -n "$IDENTITY_HASH" ]; then
    echo "› Signing with identity $IDENTITY_HASH"
    codesign --force --sign "$IDENTITY_HASH" --timestamp=none "$APP"
else
    echo "› No Developer identity found — ad-hoc signing"
    codesign --force --sign - "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "› Zipping"
ditto -c -k --keepParent "$APP" "$REPO_ROOT/dist/Rune.zip"
echo "› Done:"
du -sh "$APP" "$REPO_ROOT/dist/Rune.zip"
