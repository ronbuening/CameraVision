import Foundation
import XCTest
@testable import AISidecarCore

final class ImageRendererTests: XCTestCase {
    func testRendersJPEGDerivativesWithProfileConformingProvenance() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("Bird.JPG", width: 400, height: 200, in: root)
        let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

        let result = try renderer.renderWholeImageSet(
            source: try sourceImage(for: image),
            profile: .defaultProfile,
            debugDerivatives: false
        )

        XCTAssertEqual(result.derivatives.map(\.role), [.fullResolution, .wholeImage])
        XCTAssertEqual(result.derivatives.map(\.colorSpace), [.sRGB, .sRGB])
        XCTAssertEqual(result.derivatives.map(\.appliedOrientation.exifValue), [1, 1])
        XCTAssertEqual(result.derivatives.first?.format, .tiff)
        XCTAssertEqual(result.derivatives.last?.format, .jpeg)
        XCTAssertEqual(result.derivatives.first?.width, 400)
        XCTAssertEqual(result.derivatives.first?.height, 200)
        XCTAssertEqual(result.derivatives.last?.width, 400)
        XCTAssertEqual(result.derivatives.last?.height, 200)
        XCTAssertTrue(result.derivatives.allSatisfy { FileManager.default.fileExists(atPath: $0.cachePath) })
        XCTAssertTrue(try XCTUnwrap(imageProfileName(at: URL(fileURLWithPath: result.derivatives.last!.cachePath))).contains("sRGB"))
    }

    func testImageIOFormatsRenderOffline() throws {
        for fileName in ["Bird.JPG", "Bird.PNG", "Bird.TIFF"] {
            let root = try temporaryDirectory()
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let image = try writeTestImage(fileName, width: 48, height: 24, in: root)
            let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

            let result = try renderer.renderWholeImageSet(
                source: try sourceImage(for: image),
                profile: .defaultProfile,
                debugDerivatives: false
            )

            XCTAssertEqual(result.derivatives.count, 2, fileName)
            XCTAssertEqual(result.derivatives.last?.width, 48, fileName)
            XCTAssertEqual(result.derivatives.last?.height, 24, fileName)
        }
    }

    func testAllEightOrientationsAreBakedIntoDerivativeDimensions() throws {
        for orientation in 1...8 {
            let root = try temporaryDirectory()
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let image = try writeTestImage("Bird-\(orientation).JPG", width: 40, height: 20, orientation: orientation, in: root)
            let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

            let result = try renderer.renderWholeImageSet(
                source: try sourceImage(for: image),
                profile: .defaultProfile,
                debugDerivatives: false
            )
            let full = try XCTUnwrap(result.derivatives.first)

            XCTAssertEqual(full.appliedOrientation.exifValue, orientation)
            if [5, 6, 7, 8].contains(orientation) {
                XCTAssertEqual(full.width, 20)
                XCTAssertEqual(full.height, 40)
            } else {
                XCTAssertEqual(full.width, 40)
                XCTAssertEqual(full.height, 20)
            }
        }
    }

    func testSecondRenderReusesCachedDerivatives() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("Bird.JPG", width: 64, height: 32, in: root)
        let source = try sourceImage(for: image)
        let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

        let first = try renderer.renderWholeImageSet(source: source, profile: .defaultProfile, debugDerivatives: false)
        try FileManager.default.removeItem(at: image)
        let second = try renderer.renderWholeImageSet(source: source, profile: .defaultProfile, debugDerivatives: false)

        XCTAssertEqual(second.derivatives, first.derivatives)
    }

    func testDecodeFailureIsStructured() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Broken.JPG")
        try Data("not an image".utf8).write(to: image)
        let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

        XCTAssertThrowsError(
            try renderer.renderWholeImageSet(
                source: try sourceImage(for: image),
                profile: .defaultProfile,
                debugDerivatives: false
            )
        ) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .decodeFailed)
            XCTAssertEqual(sidecarError.stage, .render)
        }
    }

    private func sourceImage(for url: URL) throws -> SourceImage {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        return SourceImage(
            path: url.standardizedFileURL.path,
            relativePath: fileName,
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0),
            detectedType: SupportedImageType(fileExtension: fileExtension)!,
            identity: try SourceIdentityCalculator.compute(for: url, policy: .sha256)
        )
    }
}
