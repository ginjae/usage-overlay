#!/usr/bin/env bash
# 릴리스 빌드 후 실행 가능한 .app 번들을 build/ 에 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Usage Overlay.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/UsageOverlay "$APP/Contents/MacOS/UsageOverlay"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Usage Overlay</string>
  <key>CFBundleDisplayName</key><string>Usage Overlay</string>
  <key>CFBundleIdentifier</key><string>io.github.ginjae.usage-overlay</string>
  <key>CFBundleExecutable</key><string>UsageOverlay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>사용량 페이지를 열어 두고 새로고침하기 위해 Google Chrome을 제어합니다.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "빌드 완료 → $PWD/$APP"
