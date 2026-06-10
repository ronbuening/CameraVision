import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

func writeTestImage(
    _ relativePath: String,
    width: Int = 64,
    height: Int = 32,
    orientation: Int = 1,
    in root: URL,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> URL {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let image = try testCGImage(width: width, height: height)
    guard let imageDestination = CGImageDestinationCreateWithURL(
        destination as CFURL,
        typeIdentifier(for: destination.pathExtension) as CFString,
        1,
        nil
    ) else {
        XCTFail("Could not create image destination", file: file, line: line)
        return destination
    }

    CGImageDestinationAddImage(
        imageDestination,
        image,
        [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary
    )
    XCTAssertTrue(CGImageDestinationFinalize(imageDestination), file: file, line: line)
    return destination
}

func decodedImageSize(at url: URL) throws -> (width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        throw XCTSkip("Unable to decode image properties at \(url.path)")
    }
    return (width, height)
}

func imageProfileName(at url: URL) throws -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        throw XCTSkip("Unable to decode image properties at \(url.path)")
    }
    return properties[kCGImagePropertyProfileName] as? String
}

private func testCGImage(width: Int, height: Int) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        throw XCTSkip("Unable to create test image context")
    }

    context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: max(1, width / 2), height: max(1, height / 2)))

    guard let image = context.makeImage() else {
        throw XCTSkip("Unable to finalize test image")
    }
    return image
}

private func typeIdentifier(for fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "png":
        return UTType.png.identifier
    case "tif", "tiff":
        return UTType.tiff.identifier
    default:
        return UTType.jpeg.identifier
    }
}
