#!/bin/bash
# WI-2 (agent_docs/06-packaging-single-app-plan.md): prove the SwiftPM
# resource bundle still resolves after the executables are relocated into an
# app-bundle-like layout — the plan's own "single most likely packaging bug".
#
# Layouts under test:
#
#   A. bin-dir shape — aisidecar copied out with the bundle beside it
#   B. app-bundle shape (what Scripts/build-release.sh assembles) —
#      Contents/Helpers/aisidecar resolving the single shared copy in
#      Contents/Resources/<bundle>
#
# The CLI is exercised through --help (wiring), benchmark --self-test
# (offline aggregation), and a session-only normalize over a fixture sidecar —
# the last one loads the bundled default vocabulary through the Core resource
# locator, which is exactly what breaks when relocation goes wrong. All Core
# resource classes (prompts, schemas, vocabulary) resolve through the same
# locator, so one discriminating probe covers them.
#
# Usage: Scripts/wi2-relocation-check.sh [-c debug|release]
set -euo pipefail

CONFIG=release
while getopts "c:" opt; do
    case "$opt" in
        c) CONFIG="$OPTARG" ;;
        *) echo "usage: $0 [-c debug|release]" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/.."
REPO="$PWD"
BUNDLE_NAME="CameraVision_AISidecarCore.bundle"

echo "==> building aisidecar ($CONFIG)"
swift build -c "$CONFIG" --product aisidecar > /dev/null

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
[ -x "$BIN_DIR/aisidecar" ] || { echo "FAIL: no aisidecar at $BIN_DIR" >&2; exit 1; }
[ -d "$BIN_DIR/$BUNDLE_NAME" ] || { echo "FAIL: no $BUNDLE_NAME at $BIN_DIR" >&2; exit 1; }

STAGE="$(mktemp -d /tmp/wi2-relocation.XXXXXX)"
HELPERS="$STAGE/Staging.app/Contents/Helpers"
mkdir -p "$HELPERS"
cp "$BIN_DIR/aisidecar" "$HELPERS/"
cp -R "$BIN_DIR/$BUNDLE_NAME" "$HELPERS/"

# Fabricate the normalize input BEFORE hiding the build-tree bundle: the
# fixture generator is unrelated to relocation, and Bundle.module's baked-in
# fallback is that build-tree path — leaving it in place would let every
# check pass vacuously on the machine that built the binary.
WORK="$STAGE/work"
mkdir -p "$WORK"
swift Scripts/generate-synthetic-fixture.swift "$WORK/photos" 1 > /dev/null
rm -f "$WORK/photos/"*.ai.json
mv "$WORK/photos/IMG_00000.jpg" "$WORK/photos/DSC_0421.jpg"
cp Tests/CupricAspectAppTests/Fixtures/sample-analyzed.ai.json "$WORK/photos/DSC_0421.jpg.ai.json"

HIDDEN="$STAGE/hidden-build-bundle"
mv "$BIN_DIR/$BUNDLE_NAME" "$HIDDEN"
restore() {
    [ -d "$HIDDEN" ] && mv "$HIDDEN" "$BIN_DIR/$BUNDLE_NAME"
    rm -rf "$STAGE"
}
trap restore EXIT

echo "==> relocated CLI: --help"
"$HELPERS/aisidecar" --help > /dev/null

echo "==> relocated CLI: benchmark --self-test (offline)"
"$HELPERS/aisidecar" benchmark --self-test > /dev/null

echo "==> layout A (bundle beside executable): normalize with bundled vocabulary"
"$HELPERS/aisidecar" normalize --from-json "$WORK/photos" --vocabulary-mode controlled-vocabulary \
    --source-root "$WORK/photos" --source-verification warn \
    --output-dir "$WORK/artifacts" --dry-run > /dev/null 2>&1 \
    || { echo "FAIL: layout A — bundled vocabulary did not resolve" >&2; exit 1; }

echo "==> layout B (shared copy in ../Resources): normalize with bundled vocabulary"
RESOURCES="$STAGE/Staging.app/Contents/Resources"
mkdir -p "$RESOURCES"
mv "$HELPERS/$BUNDLE_NAME" "$RESOURCES/"
"$HELPERS/aisidecar" normalize --from-json "$WORK/photos" --vocabulary-mode controlled-vocabulary \
    --source-root "$WORK/photos" --source-verification warn \
    --output-dir "$WORK/artifacts-b" --dry-run > /dev/null 2>&1 \
    || { echo "FAIL: layout B — bundled vocabulary did not resolve from ../Resources" >&2; exit 1; }

# Negative control: with no bundle anywhere (build tree hidden too) the same
# command must fail — otherwise this check is vacuous.
echo "==> negative control: bundle removed"
rm -rf "$RESOURCES/$BUNDLE_NAME"
if "$HELPERS/aisidecar" normalize --from-json "$WORK/photos" --vocabulary-mode controlled-vocabulary \
    --source-root "$WORK/photos" --source-verification warn \
    --output-dir "$WORK/artifacts-neg" --dry-run > /dev/null 2>&1; then
    echo "FAIL: normalize succeeded without its resource bundle — check is vacuous" >&2
    exit 1
fi

echo "PASS: resource bundle resolves in both relocated layouts (and only with a bundle present)"
