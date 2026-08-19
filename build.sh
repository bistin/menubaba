#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/MenuPeek.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MenuPeek</string>
  <key>CFBundleExecutable</key><string>MenuPeek</string>
  <key>CFBundleIdentifier</key><string>com.bistin.MenuPeek</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

swiftc -O -target arm64-apple-macosx14.0 \
  -o "$APP/Contents/MacOS/MenuPeek" \
  "$ROOT/Sources/Log.swift" "$ROOT/Sources/Prefs.swift" "$ROOT/Sources/Capture.swift" "$ROOT/Sources/Scanner.swift" "$ROOT/Sources/PanelUI.swift" "$ROOT/Sources/main.swift" \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework ScreenCaptureKit

codesign --force --sign "MenuPeek Dev" --identifier com.bistin.MenuPeek "$APP"
echo "✅ 建置完成: $APP"
