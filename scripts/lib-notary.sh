#!/usr/bin/env bash
# Shared notarization-auth resolution, sourced by sign-and-notarize.sh and
# make-dmg.sh. Sets the NOTARY_AUTH array used for `xcrun notarytool`.
#
# App Store Connect API key (CI) when its env vars are set, else the local
# `notarytool store-credentials` keychain profile. The API-key path is
# all-or-nothing: if ANY of the three vars is set, ALL must be set and the key
# file must exist — otherwise CI fails with a misleading "profile not found"
# instead of "you forgot a secret".

resolve_notary_auth() {
    if [ -n "${AC_API_KEY_ID:-}" ] || [ -n "${AC_API_ISSUER_ID:-}" ] || [ -n "${AC_API_KEY_PATH:-}" ]; then
        if [ -z "${AC_API_KEY_ID:-}" ] || [ -z "${AC_API_ISSUER_ID:-}" ] || [ -z "${AC_API_KEY_PATH:-}" ]; then
            echo "error: App Store Connect API key config is incomplete." >&2
            echo "  Set ALL of AC_API_KEY_ID, AC_API_ISSUER_ID, AC_API_KEY_PATH (or none, for local keychain auth)." >&2
            exit 1
        fi
        [ -f "$AC_API_KEY_PATH" ] || { echo "error: API key file not found at '$AC_API_KEY_PATH'" >&2; exit 1; }
        NOTARY_AUTH=(--key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID")
        echo "==> Notary auth: App Store Connect API key"
    else
        NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-MeetingGenie}")
        if ! xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1; then
            echo "error: notary profile '${NOTARY_PROFILE:-MeetingGenie}' not found, and no App Store Connect API key env is set." >&2
            echo "  Local: xcrun notarytool store-credentials ${NOTARY_PROFILE:-MeetingGenie} --apple-id <you> --team-id <TEAMID>" >&2
            echo "  CI:    set AC_API_KEY_ID, AC_API_ISSUER_ID, AC_API_KEY_PATH." >&2
            exit 1
        fi
        echo "==> Notary auth: keychain profile '${NOTARY_PROFILE:-MeetingGenie}'"
    fi
}
