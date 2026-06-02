#!/usr/bin/env bash
# Sign (inside-out), notarize, and staple build/MeetingGenie.app (plan U3).
# Run scripts/package-app.sh first to assemble the bundle.
#
# Credentials come from the keychain only — the Developer ID identity and the
# `notarytool store-credentials` profile. The app-specific password is never
# passed inline or via env, so it can't leak into logs/history.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MeetingGenie.app"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Frederic Fontes Gerards (R47R74J893)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MeetingGenie}"
ENTITLEMENTS="packaging/entitlements.plist"

[ -d "$APP" ] || { echo "error: $APP not found — run scripts/package-app.sh first" >&2; exit 1; }

# Pre-flight: the notary profile must exist; never fall back to inline creds.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: notary profile '$NOTARY_PROFILE' not found in keychain. Create it once:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you> --team-id <TEAMID>" >&2
    exit 1
fi

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

FW="$APP/Contents/Frameworks/Sparkle.framework"
echo "==> Signing inside-out (no --deep)"
sign "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign "$FW/Versions/B/Updater.app/Contents/MacOS/Updater"
sign "$FW/Versions/B/Updater.app"
sign "$FW/Versions/B/Autoupdate"
sign "$FW"
sign "$APP/Contents/Resources/notch"
sign --entitlements "$ENTITLEMENTS" "$APP/Contents/MacOS/MeetingGenie"
sign "$APP"

echo "==> Verifying signatures (strict)"
codesign --verify --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$APP/Contents/Resources/notch"

echo "==> Notarizing the app (ditto zip → notarytool submit --wait)"
ZIP="build/MeetingGenie-app.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "==> Stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> Done: signed + notarized + stapled $APP"
echo "    Next: scripts/make-dmg.sh to build, notarize, and staple the DMG."
