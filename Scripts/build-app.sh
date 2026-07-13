#!/usr/bin/env bash
# Builds LocalDashboard.app: a real double-clickable app bundle wrapping the
# SwiftPM release binary, so the app can run without a terminal (Finder,
# Login Items, Dock/Applications) instead of only via `swift run`.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="LocalDashboard"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
BINARY_PATH="${BUILD_DIR}/release/${APP_NAME}"
VERSION="0.1.2"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.mordechaihammer.localdashboard</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS treats it as a normal local app rather than an
# unsigned binary (no Developer ID needed for local/personal use).
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built ${APP_BUNDLE}"
echo "Run:            open \"${APP_BUNDLE}\""
echo "Or drag \"${APP_BUNDLE}\" to /Applications, or add it as a Login Item in System Settings > General > Login Items."
