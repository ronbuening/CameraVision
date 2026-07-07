#!/usr/bin/env swift
// Fabricate a synthetic photo folder for GUI scale checks (plan M3/M11,
// AC4-014 groundwork): N tiny JPEGs, every other one with a minimal raw-
// sidecar stub so the queue shows mixed states. Usage:
//
//   swift Scripts/generate-synthetic-fixture.swift <directory> [count]
//
// Images are byte-identical copies of one generated JPEG — this measures the
// app's scanning/derivation/grid behavior, not JPEG encode throughput.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-synthetic-fixture.swift <directory> [count]\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let count = arguments.count >= 3 ? Int(arguments[2]) ?? 5000 : 5000

try? FileManager.default.removeItem(at: directory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let context = CGContext(
    data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.setFillColor(CGColor(red: 0.72, green: 0.5, blue: 0.25, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.3, alpha: 1))
context.fillEllipse(in: CGRect(x: 28, y: 12, width: 40, height: 40))

let imageURL = directory.appendingPathComponent("seed.jpg")
let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
let imageData = try Data(contentsOf: imageURL)
try FileManager.default.removeItem(at: imageURL)

let sidecarStub = Data(#"{"schema_version":"ai-sidecar-json/1.3"}"#.utf8)
for index in 0..<count {
    let name = String(format: "IMG_%05d.jpg", index)
    try imageData.write(to: directory.appendingPathComponent(name))
    if index.isMultiple(of: 2) {
        try sidecarStub.write(to: directory.appendingPathComponent(name + ".ai.json"))
    }
}
print("wrote \(count) images (+\((count + 1) / 2) sidecar stubs) to \(directory.path)")
