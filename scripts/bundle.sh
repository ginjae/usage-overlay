#!/usr/bin/env bash
# 릴리스 빌드 후 실행 가능한 .app 번들을 build/ 에 만든다.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UNIVERSAL=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/bundle.sh [--universal]

Environment variables:
  APP_VERSION    Three-part app version (default: 0.1.0)
  BUILD_NUMBER   Numeric bundle build number (default: 1)

--universal builds a binary that runs natively on both Apple Silicon and Intel.
USAGE
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --universal)
      UNIVERSAL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || die "Usage Overlay can only be built on macOS."

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
  cat >&2 <<'ERROR'
error: Swift was not found.

Install Apple's Xcode Command Line Tools and run this script again:
  xcode-select --install

If you only want to use the app, download the prebuilt zip instead:
  https://github.com/ginjae/usage-overlay/releases/latest
ERROR
  exit 1
fi

SWIFT="$(xcrun --find swift)"
CODESIGN="$(xcrun --find codesign 2>/dev/null)" || die "codesign was not found. Install the Xcode Command Line Tools with: xcode-select --install"

if ! SWIFT_VERSION_OUTPUT="$("$SWIFT" --version 2>&1)"; then
  printf '%s\n' "$SWIFT_VERSION_OUTPUT" >&2
  die "Swift could not run. Finish installing Xcode or its Command Line Tools, then try again."
fi

SWIFT_MAJOR="$(printf '%s\n' "$SWIFT_VERSION_OUTPUT" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
if [[ -z "$SWIFT_MAJOR" ]] || ((SWIFT_MAJOR < 6)); then
  cat >&2 <<ERROR
error: Swift 6 or newer is required (found: ${SWIFT_VERSION_OUTPUT%%$'\n'*}).

Install or update to Xcode 16 or newer, then run this script again.
If you only want to use the app, download the prebuilt zip instead:
  https://github.com/ginjae/usage-overlay/releases/latest
ERROR
  exit 1
fi

[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "APP_VERSION must look like 1.2.3 (got: $APP_VERSION)."
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "BUILD_NUMBER must be numeric (got: $BUILD_NUMBER)."

APP="build/Usage Overlay.app"
EXECUTABLE="$APP/Contents/MacOS/UsageOverlay"

if ((UNIVERSAL)); then
  LIPO="$(xcrun --find lipo 2>/dev/null)" || die "lipo was not found. Install the Xcode Command Line Tools with: xcode-select --install"

  ARM_SCRATCH=".build/universal/arm64"
  INTEL_SCRATCH=".build/universal/x86_64"

  "$SWIFT" build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH"
  ARM_BIN_DIR="$("$SWIFT" build -c release --triple arm64-apple-macosx14.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)"

  "$SWIFT" build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$INTEL_SCRATCH"
  INTEL_BIN_DIR="$("$SWIFT" build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$INTEL_SCRATCH" --show-bin-path)"

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  "$LIPO" -create \
    "$ARM_BIN_DIR/UsageOverlay" \
    "$INTEL_BIN_DIR/UsageOverlay" \
    -output "$EXECUTABLE"
else
  "$SWIFT" build -c release
  BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$BIN_DIR/UsageOverlay" "$EXECUTABLE"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Usage Overlay</string>
  <key>CFBundleDisplayName</key><string>Usage Overlay</string>
  <key>CFBundleIdentifier</key><string>io.github.ginjae.usage-overlay</string>
  <key>CFBundleExecutable</key><string>UsageOverlay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>사용량 페이지를 열어 두고 새로고침하기 위해 Google Chrome을 제어합니다.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

"$CODESIGN" --force --sign - "$APP" >/dev/null
"$CODESIGN" --verify --deep --strict "$APP"

if ((UNIVERSAL)); then
  echo "Universal 앱 빌드 완료 → $PWD/$APP"
else
  echo "$(uname -m) 앱 빌드 완료 → $PWD/$APP"
fi
