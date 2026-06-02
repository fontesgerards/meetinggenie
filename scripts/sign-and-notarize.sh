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
NOTARY_PROFILE="${NOTARY_PROFILE:-MeetingGenie}"
ENTITLEMENTS="packaging/entitlements.plist"

[ -d "$APP" ] || { echo "error: $APP not found — run scripts/package-app.sh first" >&2; exit 1; }

# Signing identity: honor $CODESIGN_IDENTITY if set, else auto-detect the lone
# "Developer ID Application" identity in the keychain. Nothing is hardcoded in
# the repo; error out on zero or multiple so the maintainer chooses explicitly.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IFS=$'\n' read -r -d '' -a _ids < <(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' && printf '\0')
    case "${#_ids[@]}" in
        1) IDENTITY="${_ids[0]}" ;;
        0) echo "error: no 'Developer ID Application' identity in the keychain. Install one (Xcode → Settings → Accounts → Manage Certificates) or set CODESIGN_IDENTITY." >&2; exit 1 ;;
        *) echo "error: multiple Developer ID Application identities found; set CODESIGN_IDENTITY to one of:" >&2
           printf '  %s\n' "${_ids[@]}" >&2; exit 1 ;;
    esac
fi
echo "==> Signing identity: $IDENTITY"

# Notarization auth (API key in CI, else keychain profile) — shared with make-dmg.sh.
source scripts/lib-notary.sh
resolve_notary_auth

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
xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait
rm -f "$ZIP"

echo "==> Stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> Done: signed + notarized + stapled $APP"
echo "    Next: scripts/make-dmg.sh to build, notarize, and staple the DMG."
