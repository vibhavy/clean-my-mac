#!/bin/bash
# Builds CleanupApp and assembles a runnable .app bundle in ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Clean Up My Machine"
BUNDLE="dist/${APP_NAME}.app"

echo "==> Compiling…"
swift build -c release

echo "==> Rendering icon…"
rm -rf dist/AppIcon.iconset
mkdir -p dist
swift tools/make-icon.swift dist/AppIcon.iconset >/dev/null
iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns

echo "==> Assembling bundle…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/CleanupApp "$BUNDLE/Contents/MacOS/CleanupApp"
cp dist/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.vibhav.cleanup</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>CleanupApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)…"
codesign --force --sign - "$BUNDLE" 2>/dev/null || echo "   (unsigned — fine for local use)"

echo "==> Done: $BUNDLE"
