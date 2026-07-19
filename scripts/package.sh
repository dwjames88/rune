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
ICON_COMPOSER="$REPO_ROOT/Assets/Main Icon/Rune.icon"
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

# Alternate icons the user can pick in Settings (Assets/Icons/*.icon).
"$REPO_ROOT/scripts/build-icon-options.sh" "$APP" || true

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
        <key>CFBundleTypeName</key><string>Web Page</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Default</string>
        <key>LSItemContentTypes</key>
        <array>
          <string>public.html</string>
          <string>public.xhtml</string>
        </array>
      </dict>
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

# Distribution signing is not dev signing. Only a Developer ID certificate is
# meant to leave this Mac, and it's the one notarization accepts — so take that
# if it exists and give it a secure timestamp, which is what keeps a build
# working after the certificate expires.
#
# Deliberately NOT falling back to an "Apple Development" identity: that cert is
# for this machine, we can't notarize with it, and without a timestamp every
# copy handed out stops launching the day it expires. Ad-hoc never expires, and
# until there's a Developer ID, Gatekeeper treats both exactly the same — it
# objects to the missing notarization, not to the certificate.
IDENTITY_HASH="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')"
if [ -n "$IDENTITY_HASH" ]; then
    echo "› Signing with Developer ID $IDENTITY_HASH"
    codesign --force --options runtime --timestamp --sign "$IDENTITY_HASH" "$APP"
    echo "› Next: notarize — xcrun notarytool submit dist/Rune.zip --wait && xcrun stapler staple $APP"
else
    echo "› No Developer ID certificate — ad-hoc signing."
    echo "  The build works, but macOS will ask each tester to allow it once."
    codesign --force --sign - "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "› Zipping"
ditto -c -k --keepParent "$APP" "$REPO_ROOT/dist/Rune.zip"
echo "› Done:"
du -sh "$APP" "$REPO_ROOT/dist/Rune.zip"
