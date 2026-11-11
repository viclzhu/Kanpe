#!/usr/bin/env bash
# Builds Kanpe.app into ./build.
#   scripts/bundle.sh            # release build (see Signing below)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#
# Signing: uses "Kanpe Local Signing" (create it once with scripts/setup-signing.sh) so the
# Accessibility permission survives rebuilds. Without it, builds are ad-hoc signed and macOS
# treats every rebuild as a new app.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Kanpe.app"
VERSION="${VERSION:-0.2.0}"

swift build -c "$CONFIG" --product Kanpe
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Kanpe"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kanpe"
cp -R Resources/Sites "$APP/Contents/Resources/Sites"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" # from scripts/make-icon.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.victorzhu.Kanpe</string>
  <key>CFBundleName</key><string>Kanpe</string>
  <key>CFBundleDisplayName</key><string>Kanpe</string>
  <key>CFBundleExecutable</key><string>Kanpe</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Prefer a stable identity: explicit SIGN_IDENTITY, else the local one from setup-signing.sh,
# else ad-hoc (which makes macOS forget Accessibility permission on every rebuild).
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-certificate -c "Kanpe Local Signing" >/dev/null 2>&1; then
  SIGN_IDENTITY="Kanpe Local Signing"
fi
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${SIGN_IDENTITY:-ad-hoc})"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "note: ad-hoc signed. Run scripts/setup-signing.sh once so Accessibility permission survives rebuilds."
fi
