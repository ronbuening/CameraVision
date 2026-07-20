#!/bin/bash
# Regenerate Scripts/packaging/AppIcon.icns from the design bundle's SVG
# (phase-4 plan B0-1). Uses only stock macOS tools: qlmanage rasterizes the
# SVG once at 1024px, a short CoreGraphics pass (`swift -`) clips the render to
# the circular disc and resizes it into the iconset, then iconutil packs them.
#
# The clip step is what keeps the corners transparent (issue #33). qlmanage
# flattens its thumbnail onto an opaque white matte, so the raw render has a
# white square behind the round icon; sips would carry that white through to
# every size. Clipping to the disc (r=74 in the SVG's 160-unit viewBox) drops
# the matte and yields transparent corners in the dock and Finder.
#
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

# Clip the white-matted master to the SVG's disc and emit transparent iconset
# PNGs. Disc geometry comes straight from the SVG (viewBox 0 0 160 160, fill
# circle r=74 at 80,80): a centered circle covering 74/160 of each side.
swift - "$MASTER" "$ICONSET" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: mask <master.png> <iconset-dir>\n".utf8))
    exit(2)
}
let masterPath = args[1]
let outDir = args[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: masterPath) as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("FAIL: cannot load master render\n".utf8))
    exit(1)
}

// SVG viewBox is 160 units; the disc is fill circle r=74 centered at (80,80).
let discFraction = 74.0 / 160.0
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func emit(pixels: Int, name: String) {
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write(Data("FAIL: cannot create \(pixels)px context\n".utf8))
        exit(1)
    }
    ctx.interpolationQuality = .high
    let side = CGFloat(pixels)
    let radius = side * CGFloat(discFraction)
    let center = side / 2
    ctx.addEllipse(in: CGRect(x: center - radius, y: center - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: side, height: side))

    guard let image = ctx.makeImage() else {
        FileHandle.standardError.write(Data("FAIL: cannot render \(name)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        FileHandle.standardError.write(Data("FAIL: cannot open \(name)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("FAIL: cannot write \(name)\n".utf8))
        exit(1)
    }
}

for size in [16, 32, 128, 256, 512] {
    emit(pixels: size, name: "icon_\(size)x\(size).png")
    emit(pixels: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
SWIFT

iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
echo "wrote $OUT_DIR/AppIcon.icns ($(du -h "$OUT_DIR/AppIcon.icns" | cut -f1 | tr -d ' '))"
