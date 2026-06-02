#!/usr/bin/env bash
# Assemble MeetingGenie.app from the SwiftPM executables (plan U1).
#
# Produces an UNSIGNED bundle containing BOTH binaries:
#   Contents/MacOS/MeetingGenie      (the menu-bar app)
#   Contents/Resources/notch         (the agent CLI the cask symlinks to PATH)
# Signing, notarization, Sparkle.framework embedding, and the DMG are later
# units (U2/U3) and are NOT done here. The unsigned bundle is enough to run the
# GUI on-device verification gate (U9).
#
# Usage: scripts/package-app.sh [short_version] [--native]
#   short_version defaults to 0.1.0; the build number is the git commit count
#   (monotonic — required by both notarization and Sparkle).
#   --native builds a single-arch bundle for LOCAL use (e.g. the U9 GUI
#   verification gate). A SHIPPING build must be universal, which requires full
#   Xcode (`swift build --arch` uses xcbuild); the default attempts universal.
set -euo pipefail

cd "$(dirname "$0")/.."

SHORT_VERSION="0.1.0"
NATIVE=0
for arg in "$@"; do
    case "$arg" in
        --native) NATIVE=1 ;;
        *) SHORT_VERSION="$arg" ;;
    esac
done
BUILD_VERSION="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="MeetingGenie.app"
OUT="build/${APP}"

if [ "$NATIVE" -eq 1 ]; then
    echo "==> Native release build (single-arch — LOCAL ONLY, not shippable)"
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
else
    echo "==> Universal release build (arm64 + x86_64)"
    if ! swift build -c release --arch arm64 --arch x86_64; then
        echo "error: universal build failed. `swift build --arch` needs full Xcode (xcbuild)." >&2
        echo "       On a Command-Line-Tools-only machine, use --native for a local bundle;" >&2
        echo "       shipping builds must be universal and run on a machine with Xcode." >&2
        exit 1
    fi
    BIN_DIR=".build/apple/Products/Release"
fi

APP_BIN="${BIN_DIR}/MeetingGenie"
NOTCH_BIN="${BIN_DIR}/notch"
[ -f "$APP_BIN" ]   || { echo "error: $APP_BIN not found" >&2; exit 1; }
[ -f "$NOTCH_BIN" ] || { echo "error: $NOTCH_BIN not found" >&2; exit 1; }

echo "==> Assembling ${OUT}"
rm -rf "$OUT"
mkdir -p "${OUT}/Contents/MacOS" "${OUT}/Contents/Resources" "${OUT}/Contents/Frameworks"

# Both binaries ship inside the bundle. The app executable name MUST match
# CFBundleExecutable; notch goes in Resources so the cask can symlink it.
cp "$APP_BIN"   "${OUT}/Contents/MacOS/MeetingGenie"
cp "$NOTCH_BIN" "${OUT}/Contents/Resources/notch"
chmod +x "${OUT}/Contents/MacOS/MeetingGenie" "${OUT}/Contents/Resources/notch"

echo "==> Verifying universal slices"
lipo -info "${OUT}/Contents/MacOS/MeetingGenie"
lipo -info "${OUT}/Contents/Resources/notch"

echo "==> Embedding Sparkle.framework"
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FW" ] || { echo "error: Sparkle.framework not found at $SPARKLE_FW (run swift package resolve)" >&2; exit 1; }
# ditto preserves the Versions/Current symlink the framework needs to load.
ditto "$SPARKLE_FW" "${OUT}/Contents/Frameworks/Sparkle.framework"

echo "==> Rendering Info.plist (v${SHORT_VERSION} build ${BUILD_VERSION})"
sed -e "s/__SHORT_VERSION__/${SHORT_VERSION}/" \
    -e "s/__BUILD_VERSION__/${BUILD_VERSION}/" \
    packaging/Info.plist > "${OUT}/Contents/Info.plist"

echo "==> App icon"
if [ -f packaging/AppIcon.icns ]; then
    cp packaging/AppIcon.icns "${OUT}/Contents/Resources/AppIcon.icns"
elif [ -d packaging/AppIcon.iconset ]; then
    iconutil -c icns packaging/AppIcon.iconset -o "${OUT}/Contents/Resources/AppIcon.icns"
else
    echo "    warning: no packaging/AppIcon.icns or AppIcon.iconset — bundling without a custom icon."
    echo "    (Provide a designed icon before shipping; this is fine for the GUI verification gate.)"
fi

echo "==> Stripping extended attributes"
xattr -cr "$OUT"

echo "==> Done: ${OUT}"
echo "    rpath check (expect @loader_path/../Frameworks):"
otool -l "${OUT}/Contents/MacOS/MeetingGenie" | grep -A2 LC_RPATH | grep path || \
    echo "    (no LC_RPATH found — verify the Package.swift linker flag)"
echo
echo "Next (not done here): embed+sign Sparkle.framework (U2), inside-out"
echo "codesign incl. Contents/Resources/notch, notarize, staple, DMG (U3)."
