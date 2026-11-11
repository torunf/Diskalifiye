#!/bin/bash
# Diskalifiye.app paketini üretir:  ./build.sh  (ardından: open build/Diskalifiye.app)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Diskalifiye.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Diskalifiye "$APP/Contents/MacOS/Diskalifiye"

# Simge
TMP=$(mktemp -d)
swift scripts/make_icon.swift "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Diskalifiye</string>
  <key>CFBundleDisplayName</key><string>Diskalifiye</string>
  <key>CFBundleIdentifier</key><string>com.diskalifiye.app</string>
  <key>CFBundleExecutable</key><string>Diskalifiye</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Çöp Kutusu'nu boşaltmak için Finder'a komut gönderilir.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Hazır: $APP"
