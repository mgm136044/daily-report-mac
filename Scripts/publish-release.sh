#!/bin/bash
# Publish the notarized dmg as a GitHub Release on the app's public repo, so the app
# can check for updates unauthenticated and users can download it.
# Usage: ./Scripts/publish-release.sh [notes-file]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/DailyReportKit/App/AppVersion.swift)}"
RELEASES_REPO="${RELEASES_REPO:-mgm136044/daily-report-mac}"
DMG="dist/DailyReport-$VERSION.dmg"
NOTES_FILE="${1:-}"

[ -f "$DMG" ] || { echo "✗ $DMG 없음 — 먼저 ./Scripts/make-dmg.sh (공증)"; exit 1; }

gh repo view "$RELEASES_REPO" >/dev/null 2>&1 || { echo "✗ 레포 없음: $RELEASES_REPO"; exit 1; }

echo "▸ publish v$VERSION → $RELEASES_REPO"
ARGS=(release create "v$VERSION" "$DMG" --repo "$RELEASES_REPO" --title "v$VERSION" --latest)
if [ -n "$NOTES_FILE" ]; then ARGS+=(--notes-file "$NOTES_FILE"); else ARGS+=(--generate-notes); fi
gh "${ARGS[@]}"
echo "✓ published v$VERSION"
