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
#   --native builds a single-arch (host) bundle for LOCAL use (e.g. the U9 GUI
#   verification gate). The default builds a universal (arm64+x86_64) bundle via
#   two native per-arch compiles + lipo — no xcbuild, so it works on any machine
#   with the Swift toolchain and the (universal) macOS SDK.
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
    echo "==> Universal release build (arm64 + x86_64 via per-arch native builds + lipo)"
    # `swift build --arch arm64 --arch x86_64` routes through xcbuild, which is
    # broken on Xcode 16.x for this package: swiftLanguageMode(.v5) trips
    # "Swift language versions ... (given: [5], supported: [])" and "Unexpected
    # duplicate tasks". Instead build each slice with the NATIVE build system
    # (llbuild) — `-Xswiftc -target` selects the arch, and the macOS SDK is
    # universal so x86_64 cross-compiles on an arm64 host — into separate
    # scratch dirs, then lipo the two slices together. No xcbuild involved.
    echo "    -- arm64 slice"
    swift build -c release --scratch-path .build-arm64  -Xswiftc -target -Xswiftc arm64-apple-macos13.0
    echo "    -- x86_64 slice"
    swift build -c release --scratch-path .build-x86_64 -Xswiftc -target -Xswiftc x86_64-apple-macos13.0
    # Both per-arch scratch builds emit to <scratch>/<host-triple>/release — the
    # bin-path dir is named for the HOST triple even for the cross slice, so the
    # only difference between the two is the scratch prefix. Query the base path
    # once and swap the prefix (anchored on /.build/ so a repo living under a
    # path containing ".build" can't false-match) instead of paying for two more
    # package-graph evaluations.
    BASE_BIN_DIR="$(swift build -c release --show-bin-path)"   # .../.build/<host-triple>/release
    BIN_SUFFIX="${BASE_BIN_DIR#*/.build/}"                      # <host-triple>/release (anchored on /.build/)
    ARM_DIR=".build-arm64/${BIN_SUFFIX}"
    X86_DIR=".build-x86_64/${BIN_SUFFIX}"
    BIN_DIR="build/universal"
    rm -rf "$BIN_DIR"; mkdir -p "$BIN_DIR"
    lipo -create "${ARM_DIR}/MeetingGenie" "${X86_DIR}/MeetingGenie" -output "${BIN_DIR}/MeetingGenie"
    lipo -create "${ARM_DIR}/notch"        "${X86_DIR}/notch"        -output "${BIN_DIR}/notch"
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
# Locate the framework rather than hardcoding the arch-slice path (robust across
# Sparkle/SwiftPM versions). On macOS the xcframework yields one universal slice.
# Search both the native (.build) and per-arch universal (.build-arm64) scratch
# trees; the xcframework slice it points to is already universal (arm64+x86_64).
SPARKLE_FW="$(find .build-arm64/artifacts .build/artifacts -path '*macos-arm64_x86_64*' -name 'Sparkle.framework' -type d 2>/dev/null | head -1)"
[ -n "$SPARKLE_FW" ] && [ -d "$SPARKLE_FW" ] || { echo "error: Sparkle.framework not found under .build*/artifacts (run 'swift package resolve')" >&2; exit 1; }
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
