#!/bin/bash
#
# build_dmg.sh — compile Prism, bundle it as Prism.app, and package Prism.dmg
#
# Run this on macOS 13+ with the Xcode command-line tools installed:
#     cd PrismBrowser
#     ./build_dmg.sh
#
# Output: ./dist/Prism.dmg  (drag-to-Applications installer)

set -euo pipefail

APP_NAME="Prism"
BUNDLE_ID="com.prism.browser"
VERSION="1.0"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

echo "▸ Checking toolchain…"
command -v swift   >/dev/null || { echo "✗ Swift not found. Install Xcode command-line tools."; exit 1; }
command -v hdiutil >/dev/null || { echo "✗ hdiutil not found (are you on macOS?)."; exit 1; }

echo "▸ Building release binary…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ Built binary not found at $BIN"; exit 1; }

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>CFBundleIconFile</key>        <string>Prism</string>
</dict>
</plist>
PLIST

echo "PkgInfo" > "$APP/Contents/PkgInfo"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Ad-hoc code-signing…"

if [ -f "$ROOT/assets/logo/Prism.icns" ]; then
  cp "$ROOT/assets/logo/Prism.icns" "$APP/Contents/Resources/Prism.icns"
fi
codesign --force --deep --sign - "$APP" || echo "  (codesign warning ignored)"

echo "▸ Creating DMG…"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "✓ Done."
echo "  App:  $APP"
echo "  DMG:  $DMG"
echo ""
echo "Open the DMG and drag $APP_NAME into Applications."
echo "First launch: right-click → Open (it's ad-hoc signed, not notarized)."
