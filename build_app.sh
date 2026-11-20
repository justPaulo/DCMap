#!/bin/bash
# Builds a double-clickable DCMap.app (release build, ad-hoc signed) into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DCMap"
APP="build/DCMap.app"
ICONSET="build/DCMap.iconset"
RESOURCE_BUNDLE="$(dirname "$BIN")/DCMap_DCMap.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DCMap"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Error: SwiftPM resource bundle not found: $RESOURCE_BUNDLE"
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

mkdir -p "$ICONSET"
swift Scripts/generate_app_icon.swift "$ICONSET/source.png" Sources/DCMap/WorldData.swift
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICONSET/source.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$ICONSET/source.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
rm "$ICONSET/source.png"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DCMap</string>
  <key>CFBundleIdentifier</key><string>local.dcmap.topology</string>
  <key>CFBundleName</key><string>DC DR Topology</string>
  <key>CFBundleDisplayName</key><string>DC DR Topology</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(codesign skipped)"
echo "Built $APP"
echo "Run:  open \"$APP\""
