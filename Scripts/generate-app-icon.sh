#!/bin/bash
# Regenerate Scripts/packaging/AppIcon.icns from the design bundle's SVG
# (phase-4 plan B0-1). Uses only stock macOS tools: qlmanage rasterizes the
# SVG once at 1024px, sips derives the iconset sizes, iconutil packs them.
# The generated .icns is committed so release builds don't depend on
# qlmanage's SVG support; re-run this only when the SVG changes.
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="agent_docs/gui-wrapper-for-cameravision/project/uploads/cupricaspect_icon-3.svg"
OUT_DIR="Scripts/packaging"
[ -f "$SVG" ] || { echo "FAIL: missing $SVG" >&2; exit 1; }
mkdir -p "$OUT_DIR"

WORK="$(mktemp -d /tmp/cupric-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

qlmanage -t -s 1024 -o "$WORK" "$SVG" > /dev/null
MASTER="$WORK/$(basename "$SVG").png"
[ -f "$MASTER" ] || { echo "FAIL: qlmanage produced no PNG" >&2; exit 1; }

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
echo "wrote $OUT_DIR/AppIcon.icns ($(du -h "$OUT_DIR/AppIcon.icns" | cut -f1 | tr -d ' '))"
