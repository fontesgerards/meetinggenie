#!/usr/bin/env bash
# Build a notarized, stapled DMG from the signed app (plan U3).
# Run scripts/sign-and-notarize.sh first (the app inside must already be signed
# + notarized + stapled). The DMG is separately notarized + stapled so Gatekeeper
# validates offline, and its sha256 (printed at the end) is the cask's anchor.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MeetingGenie.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-MeetingGenie}"
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="build/MeetingGenie-${VERSION}.dmg"
STAGE="build/dmg-stage"

echo "==> Staging DMG contents (app + /Applications symlink)"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MeetingGenie.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Building ${DMG}"
hdiutil create -volname "MeetingGenie" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

rm -rf "$STAGE"
echo "==> sha256 (cask anchor):"
shasum -a 256 "$DMG"
echo "==> Done: $DMG"
