#!/bin/bash
# WI-1 (agent_docs/06-packaging-single-app-plan.md, B0-1 scope): assemble the
# distributable CupricAspect.app around the SwiftPM release binaries and pack
# it into a DMG.
#
#   Scripts/build-release.sh [--no-cli] [--no-dmg] [--universal]
#                            [--sign "Developer ID Application: ..."]
#
# The product version is read from AISidecarVersion.swift — the single source
# (plan D5); the script injects it into CFBundleShortVersionString so the
# About card, `aisidecar --version`, and the bundle can never disagree.
#
# Signing/notarization: without --sign the bundle is ad-hoc signed (runs on
# the build machine and machines with Gatekeeper exceptions; fine for local
# beta prep). Developer ID signing + `notarytool submit` + `stapler staple`
# are the documented WI-1 steps 4–5 and slot in where marked when the
# Developer ID certificate is available.
set -euo pipefail

WITH_CLI=1
WITH_DMG=1
UNIVERSAL=0
SIGN_IDENTITY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-cli) WITH_CLI=0 ;;
        --no-dmg) WITH_DMG=0 ;;
        --universal) UNIVERSAL=1 ;;
        # Convenience for the release workflow (WI plan 11 W1): a release build
        # is always universal so Intel Macs are covered. Local bare invocations
        # stay host-arch/fast.
        --for-release) UNIVERSAL=1 ;;
        --sign) SIGN_IDENTITY="$2"; shift ;;
        *) echo "usage: $0 [--no-cli] [--no-dmg] [--universal] [--for-release] [--sign identity]" >&2; exit 2 ;;
    esac
    shift
done

cd "$(dirname "$0")/.."
BUNDLE_NAME="CameraVision_AISidecarCore.bundle"

VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' \
    Sources/AISidecarCore/Support/AISidecarVersion.swift)"
[ -n "$VERSION" ] || { echo "FAIL: could not read AISidecarVersion.current" >&2; exit 1; }
echo "==> CupricAspect $VERSION"

BUILD_FLAGS=(-c release)
if [ "$UNIVERSAL" = 1 ]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build (release)"
swift build "${BUILD_FLAGS[@]}" --product CupricAspect
if [ "$WITH_CLI" = 1 ]; then
    swift build "${BUILD_FLAGS[@]}" --product aisidecar
fi
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
[ -x "$BIN_DIR/CupricAspect" ] || { echo "FAIL: no CupricAspect at $BIN_DIR" >&2; exit 1; }
[ -d "$BIN_DIR/$BUNDLE_NAME" ] || { echo "FAIL: no $BUNDLE_NAME at $BIN_DIR" >&2; exit 1; }

DIST="dist"
APP="$DIST/CupricAspect.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/CupricAspect" "$APP/Contents/MacOS/"
# One shared copy in Contents/Resources: the Core resource locator (WI-2)
# resolves it for the GUI via Bundle.main.resourceURL and for the embedded
# CLI via ../Resources. The SwiftPM bundle is flat (no Contents/Info.plist),
# so a copy under Helpers/ would fail codesign as an unrecognized bundle.
cp -R "$BIN_DIR/$BUNDLE_NAME" "$APP/Contents/Resources/"
cp Scripts/packaging/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" Scripts/packaging/Info.plist.template \
    > "$APP/Contents/Info.plist"

if [ "$WITH_CLI" = 1 ]; then
    mkdir -p "$APP/Contents/Helpers"
    cp "$BIN_DIR/aisidecar" "$APP/Contents/Helpers/"
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$PLIST_VERSION" = "$VERSION" ] || { echo "FAIL: plist version mismatch" >&2; exit 1; }
CLI_VERSION=""
if [ "$WITH_CLI" = 1 ]; then
    CLI_VERSION="$("$APP/Contents/Helpers/aisidecar" --version)"
    [ "$CLI_VERSION" = "$VERSION" ] || { echo "FAIL: CLI reports '$CLI_VERSION', expected $VERSION" >&2; exit 1; }
fi

echo "==> codesign"
if [ -n "$SIGN_IDENTITY" ]; then
    # WI-1 steps 4–5: inside-out with hardened runtime, then notarize+staple.
    if [ "$WITH_CLI" = 1 ]; then
        codesign --force --timestamp --options runtime -s "$SIGN_IDENTITY" "$APP/Contents/Helpers/aisidecar"
    fi
    codesign --force --timestamp --options runtime -s "$SIGN_IDENTITY" "$APP"
    echo "    NOTE: run 'xcrun notarytool submit --wait' and 'xcrun stapler staple' before distributing."
else
    # Ad-hoc: keeps the bundle launchable locally; replace with --sign for beta hand-out.
    if [ "$WITH_CLI" = 1 ]; then
        codesign --force -s - "$APP/Contents/Helpers/aisidecar"
    fi
    codesign --force -s - "$APP"
    echo "    (ad-hoc signed — not distributable; pass --sign for Developer ID)"
fi
codesign --verify --deep "$APP"

if [ "$WITH_DMG" = 1 ]; then
    DMG="$DIST/CupricAspect-$VERSION.dmg"
    echo "==> $DMG"
    rm -f "$DMG"
    DMG_ROOT="$(mktemp -d /tmp/cupric-dmg.XXXXXX)"
    trap 'rm -rf "$DMG_ROOT"' EXIT
    cp -R "$APP" "$DMG_ROOT/"
    ln -s /Applications "$DMG_ROOT/Applications"
    hdiutil create -volname "CupricAspect $VERSION" -srcfolder "$DMG_ROOT" \
        -ov -format UDZO "$DMG" > /dev/null
    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"
    fi

    # SHA256SUMS over the DMG, basename only so `shasum -a 256 -c SHA256SUMS`
    # verifies from inside the download folder (plan 11 W1). The DMG is the
    # sole distributable; a zipped .app can be re-added here if Sparkle
    # auto-update (roadmap F4-R2) ever needs one.
    echo "==> $DIST/SHA256SUMS"
    ( cd "$DIST" && shasum -a 256 "CupricAspect-$VERSION.dmg" > SHA256SUMS )
fi

echo "PASS: $APP assembled (version $VERSION$([ "$WITH_CLI" = 1 ] && echo ", CLI embedded"))"
