#!/usr/bin/env bash
# Builds "Mac Tools.app" (universal) and zips it into dist/. Usage: scripts/build-app.sh
# Signs ad-hoc by default. Set SIGN_IDENTITY="Developer ID Application: ..." to sign for real.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Mac Tools.app"
ZIP="dist/Mac-Tools-${VERSION}.zip"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacTools"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacTools"
iconutil --convert icns assets/AppIcon.iconset --output "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mac Tools</string>
  <key>CFBundleDisplayName</key><string>Mac Tools</string>
  <key>CFBundleIdentifier</key><string>com.denwilliams.mactools</string>
  <key>CFBundleExecutable</key><string>MacTools</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

xattr -cr "$APP"   # no extended attributes in the bundle or zip
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$ZIP"
cp tools/notch.mjs dist/notch
chmod +x dist/notch
( cd dist && shasum -a 256 "Mac-Tools-${VERSION}.zip" notch > SHA256SUMS.txt )
echo "Built: $ZIP"
