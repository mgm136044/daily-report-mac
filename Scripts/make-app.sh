#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DailyReport"
BUNDLE_ID="com.mgm136044.DailyReportMac"
# Version is single-sourced from the Kit (AppVersion.current) so the running app
# and the update check compare the same number.
VERSION="${VERSION:-$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/DailyReportKit/App/AppVersion.swift)}"
# Signing identity: set DAILY_REPORT_SIGN_IDENTITY, else auto-detect the first
# "Developer ID Application" cert in the login keychain (so no name is hard-coded here).
IDENTITY="${DAILY_REPORT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)".*/\1/')}"
[ -n "$IDENTITY" ] || { echo "✗ 서명 신원 없음 — DAILY_REPORT_SIGN_IDENTITY 설정 또는 Developer ID 인증서 필요"; exit 1; }
APP="dist/$APP_NAME.app"

echo "▸ build (release) — v$VERSION"
swift build -c release --product DailyReport
swift build -c release --product daily-report-runner

echo "▸ assemble $APP"
# The schedule is a self-managed LaunchAgent the app writes to ~/Library/LaunchAgents
# at runtime (see ScheduleManager); no plist/wrapper is bundled anymore.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DailyReport            "$APP/Contents/MacOS/DailyReport"
cp .build/release/daily-report-runner    "$APP/Contents/MacOS/daily-report-runner"

# App icon: build a multi-resolution .icns from Resources/logo.png (source of truth).
if [ -f Resources/logo.png ]; then
    echo "▸ app icon (from Resources/logo.png)"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size"           Resources/logo.png --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
        sips -z "$((size*2))" "$((size*2))" Resources/logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DailyReport</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>DailyReport</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "▸ sign (Developer ID, hardened runtime)"
EXTRA="--options runtime --timestamp --entitlements Resources/DailyReport.entitlements"
# nested Mach-O first, then the app
codesign --force $EXTRA -s "$IDENTITY" "$APP/Contents/MacOS/daily-report-runner"
codesign --force $EXTRA -s "$IDENTITY" "$APP/Contents/MacOS/DailyReport"
codesign --force $EXTRA -s "$IDENTITY" "$APP" || { echo "✗ codesign 실패"; exit 1; }

echo "▸ verify"
codesign --verify --strict --verbose=2 "$APP"
echo "✓ $APP"
