#!/usr/bin/env bash
# Generate the Sparkle appcast from the notarized DMG(s) in build/ (plan U4).
# Run after make-dmg.sh. Signs each item with the EdDSA private key in your
# login Keychain and writes build/appcast.xml.
#
# --maximum-deltas 0: no deltas for now (they need >=2 releases); enable later.
# The download-url-prefix is where the DMGs are actually hosted; override via
# APPCAST_URL_PREFIX. Default assumes DMGs are served from the GitHub Pages site
# alongside appcast.xml (single stable dir → simplest correct enclosure URLs).
set -euo pipefail
cd "$(dirname "$0")/.."

GA="$(find .build -path '*sparkle*/bin/generate_appcast' -type f 2>/dev/null | head -1)"
[ -x "$GA" ] || { echo "error: generate_appcast not found — run 'swift package resolve'." >&2; exit 1; }

PREFIX="${APPCAST_URL_PREFIX:-https://fontesgerards.github.io/meetinggenie/}"

"$GA" --maximum-deltas 0 --download-url-prefix "$PREFIX" build/

echo
echo "==> Wrote build/appcast.xml (enclosure prefix: $PREFIX)"
echo "    Host appcast.xml + the DMG(s) at that prefix so SUFeedURL"
echo "    (https://fontesgerards.github.io/meetinggenie/appcast.xml) resolves."
echo "    Before publishing, add <sparkle:minimumAutoupdateVersion> to each item"
echo "    to block downgrade pushes."
