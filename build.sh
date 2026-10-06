#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ServerBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O main.swift -o "$APP/Contents/MacOS/ServerBar"

if [ -f MenuIcon.png ]; then
  cp MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"
fi

ICON_KEY=""
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ServerBar</string>
    <key>CFBundleIdentifier</key><string>local.serverbar</string>
    <key>CFBundleExecutable</key><string>ServerBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    $ICON_KEY
</dict>
</plist>
PLIST

echo "Built $APP"
