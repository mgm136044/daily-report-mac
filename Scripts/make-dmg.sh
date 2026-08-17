#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/DailyReport.app"
VERSION="${VERSION:-$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/DailyReportKit/App/AppVersion.swift)}"
DMG="dist/DailyReport-$VERSION.dmg"
PROFILE="${NOTARY_PROFILE:-daily-report-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"   # 1 = signed-only dmg (works on your own Mac; notarize later)
[ -d "$APP" ] || { echo "✗ $APP 없음 — 먼저 ./Scripts/make-app.sh"; exit 1; }

if [ "$SKIP_NOTARIZE" != "1" ]; then
    echo "▸ notarize the app"
    ZIP="dist/DailyReport.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
else
    echo "▸ 공증 생략 (서명된 앱으로 dmg만 — 본인 Mac에서 동작)"
fi

echo "▸ build dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DailyReport" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ "$SKIP_NOTARIZE" != "1" ]; then
    echo "▸ notarize + staple the dmg"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "▸ verify (the dmg has no code signature itself — assess the app inside)"
    xcrun stapler validate "$DMG"
    MP="$(mktemp -d)"
    hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MP"
    spctl -a -t exec -vv "$MP/DailyReport.app" || true   # expect: accepted, Notarized Developer ID
    hdiutil detach "$MP" -quiet
fi
echo "✓ $DMG"
