#!/usr/bin/env swift
// Fabricate a synthetic photo folder for GUI scale checks (plan M3/M11,
// AC4-014 groundwork; B0-6 review-scale check): N tiny JPEGs, every other
// one with a minimal raw-sidecar stub so the queue shows mixed states.
// Usage:
//
//   swift Scripts/generate-synthetic-fixture.swift <directory> [count] [--sidecar-template <path>]
//
// With --sidecar-template (a real pipeline-written .ai.json, e.g. the
// committed Tests/CupricAspectAppTests/Fixtures/sample-analyzed.ai.json),
// EVERY image gets a full valid sidecar: the template's source block is
// patched per file (name, paths, size, mtime, sha256 of the actual bytes),
// so session builds and reviews work over the whole synthetic set.
//
// Images are byte-identical copies of one generated JPEG — this measures the
// app's scanning/derivation/grid behavior, not JPEG encode throughput.

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

var arguments = Array(CommandLine.arguments.dropFirst())
var templatePath: String?
if let flagIndex = arguments.firstIndex(of: "--sidecar-template"), flagIndex + 1 < arguments.count {
    templatePath = arguments[flagIndex + 1]
    arguments.removeSubrange(flagIndex...(flagIndex + 1))
}
guard !arguments.isEmpty else {
    FileHandle.standardError.write(
        Data("usage: generate-synthetic-fixture.swift <directory> [count] [--sidecar-template <path>]\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
let count = arguments.count >= 2 ? Int(arguments[1]) ?? 5000 : 5000

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

/// Full-sidecar mode: patch the template's source block per image. All
/// images share one byte-identical JPEG, so one sha256 serves every copy.
func makeSidecarWriter(templatePath: String) throws -> (String, URL) throws -> Data {
    let templateData = try Data(contentsOf: URL(fileURLWithPath: templatePath))
    guard var template = try JSONSerialization.jsonObject(with: templateData) as? [String: Any],
        var source = template["source"] as? [String: Any]
    else {
        FileHandle.standardError.write(Data("FAIL: template is not a raw sidecar JSON object\n".utf8))
        exit(1)
    }
    let sha256 = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
    let formatter = ISO8601DateFormatter()
    return { name, url in
        source["file_name"] = name
        source["path"] = url.path
        source["relative_path"] = name
        source["file_size"] = imageData.count
        source["modified_at"] = formatter.string(from: Date())
        var identity = source["identity"] as? [String: Any] ?? ["policy": "sha256"]
        identity["sha256"] = sha256
        source["identity"] = identity
        template["source"] = source
        return try JSONSerialization.data(withJSONObject: template, options: [.sortedKeys])
    }
}

if let templatePath {
    let writeSidecar = try makeSidecarWriter(templatePath: templatePath)
    for index in 0..<count {
        let name = String(format: "IMG_%05d.jpg", index)
        let url = directory.appendingPathComponent(name)
        try imageData.write(to: url)
        try writeSidecar(name, url).write(to: directory.appendingPathComponent(name + ".ai.json"))
    }
    print("wrote \(count) images with full sidecars to \(directory.path)")
} else {
    let sidecarStub = Data(#"{"schema_version":"ai-sidecar-json/1.3"}"#.utf8)
    for index in 0..<count {
        let name = String(format: "IMG_%05d.jpg", index)
        try imageData.write(to: directory.appendingPathComponent(name))
        if index.isMultiple(of: 2) {
            try sidecarStub.write(to: directory.appendingPathComponent(name + ".ai.json"))
        }
    }
    print("wrote \(count) images (+\((count + 1) / 2) sidecar stubs) to \(directory.path)")
}
