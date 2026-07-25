#!/bin/bash
# Builds Rune for iOS and installs it in the booted simulator — the same
# no-Xcode-project trick as dev-run.sh: SwiftPM builds the bare binary
# against the iphonesimulator SDK, and we dress it as an .app ourselves.
# (A real device needs code signing — that bridge waits for a Developer
# Program membership. The simulator takes an ad-hoc signature happily.)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/ios"

CONFIG="${1:-debug}"
VERSION="$(cat "$REPO_ROOT/VERSION")"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios17.0-simulator"

swift build -c "$CONFIG" --triple "$TARGET" --sdk "$SDK" >/dev/null
BIN="$(swift build -c "$CONFIG" --triple "$TARGET" --sdk "$SDK" --show-bin-path)/RuneMobile"

APP="$REPO_ROOT/ios/.build/Rune.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$BIN" "$APP/RuneMobile"

# iOS bundles are flat — Info.plist beside the binary, no Contents/.
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Rune</string>
    <key>CFBundleDisplayName</key><string>Rune</string>
    <key>CFBundleIdentifier</key><string>com.dwjames.Rune.ios</string>
    <key>CFBundleExecutable</key><string>RuneMobile</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>17.0</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>UILaunchScreen</key><dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
      <string>UIInterfaceOrientationPortrait</string>
      <string>UIInterfaceOrientationLandscapeLeft</string>
      <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
      <!-- A browser loads what the user asks for; ATS still guards app-level
           fetches. Same posture as Safari's web content. -->
      <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
    </dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Into the booted simulator (boot the first iPhone if none is up).
UDID="$(xcrun simctl list devices | awk -F '[()]' '/iPhone.*Booted/ { print $2; exit }')"
if [ -z "$UDID" ]; then
    UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
    xcrun simctl bootstatus "$UDID" -b >/dev/null
fi
xcrun simctl install "$UDID" "$APP"
echo "› Installed on $UDID"
xcrun simctl launch "$UDID" com.dwjames.Rune.ios
