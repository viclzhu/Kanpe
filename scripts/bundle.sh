#!/usr/bin/env bash
# Builds Kanpe.app into ./build.
#   scripts/bundle.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#
# Note: with ad-hoc signing, macOS treats every rebuild as a new app, so you may need to
# remove and re-add Kanpe under System Settings → Privacy & Security → Accessibility.
# A stable signing identity avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Kanpe.app"
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" --product Kanpe
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Kanpe"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kanpe"
cp -R Resources/Sites "$APP/Contents/Resources/Sites"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.victorzhu.Kanpe</string>
  <key>CFBundleName</key><string>Kanpe</string>
  <key>CFBundleDisplayName</key><string>Kanpe</string>
  <key>CFBundleExecutable</key><string>Kanpe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Kanpe reads the address of the current browser tab, only when you open the shortcuts panel, to show shortcuts for that website. The address is never stored or sent anywhere.</string>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
