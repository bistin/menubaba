#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/MenuBaba.app"

# --- 環境檢查 ---------------------------------------------------------------

command -v swiftc >/dev/null || {
  echo "❌ 找不到 swiftc，請先安裝 Xcode 命令列工具：xcode-select --install" >&2
  exit 1
}

MACOS="$(sw_vers -productVersion)"
if [ "${MACOS%%.*}" -lt 14 ]; then
  echo "❌ 需要 macOS 14 以上，這台是 $MACOS" >&2
  exit 1
fi

# --- 簽章身分 ---------------------------------------------------------------
# TCC 的授權綁在簽章身分上。ad-hoc 簽章的身分是 cdhash，每次重新編譯都會變，
# 輔助使用／螢幕錄製的授權就跟著掉，所以優先找自簽憑證（建立方式見 README）。
# 想指定別張憑證：SIGN_IDENTITY="憑證名稱" ./build.sh

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  for candidate in "MenuBaba Dev" "MenuPeek Dev"; do
    if security find-identity -v -p codesigning | grep -qF "\"$candidate\""; then
      IDENTITY="$candidate"
      break
    fi
  done
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"   # ad-hoc，還是能跑，只是每次重建都要重新授權
fi

# --- 建置 -------------------------------------------------------------------

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MenuBaba</string>
  <key>CFBundleExecutable</key><string>MenuBaba</string>
  <key>CFBundleIdentifier</key><string>com.bistin.MenuBaba</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

# 目標架構跟著這台機器走，Intel 和 Apple silicon 都能編
swiftc -O -target "$(uname -m)-apple-macosx14.0" \
  -o "$APP/Contents/MacOS/MenuBaba" \
  "$ROOT/Sources/Log.swift" "$ROOT/Sources/Prefs.swift" "$ROOT/Sources/Capture.swift" "$ROOT/Sources/Scanner.swift" "$ROOT/Sources/PanelUI.swift" "$ROOT/Sources/main.swift" \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework ScreenCaptureKit -framework ServiceManagement

codesign --force --sign "$IDENTITY" --identifier com.bistin.MenuBaba "$APP"

echo "✅ 建置完成: $APP"
if [ "$IDENTITY" = "-" ]; then
  echo
  echo "⚠️  這次是 ad-hoc 簽章（找不到自簽憑證）。app 可以正常跑，但每次重新"
  echo "    執行 build.sh 之後，輔助使用和螢幕錄製都要重新授權一次。"
  echo "    想一次授權長期有效，請照 README「安裝」一節建一張 MenuBaba Dev 憑證。"
else
  echo "   簽章身分: $IDENTITY"
fi
