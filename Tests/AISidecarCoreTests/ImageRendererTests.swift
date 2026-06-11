import Foundation
import XCTest
@testable import AISidecarCore

final class ImageRendererTests: XCTestCase {
    func testRendersJPEGDerivativesWithProfileConformingProvenance() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("Bird.JPG", width: 400, height: 200, in: root)
        let source = try sourceImage(for: image)
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000)
        let renderer = ImageRenderer(cache: cache)

        let result = try renderer.renderWholeImage(
            source: source,
            profile: .defaultProfile,
            debugDerivatives: false
        )

        XCTAssertEqual(result.derivatives.map(\.role), [.wholeImage])
        XCTAssertEqual(result.derivatives.map(\.colorSpace), [.sRGB])
        XCTAssertEqual(result.derivatives.map(\.appliedOrientation.exifValue), [1])
        XCTAssertEqual(result.wholeImage.format, .jpeg)
        XCTAssertEqual(result.wholeImage.width, 400)
        XCTAssertEqual(result.wholeImage.height, 200)
        XCTAssertTrue(result.derivatives.allSatisfy { FileManager.default.fileExists(atPath: $0.cachePath) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.artifactURL(
            source: source,
            recipeVersion: RenderRecipe(profile: .defaultProfile).version,
            role: .fullResolution,
            format: .tiff
        ).path))
        XCTAssertTrue(try XCTUnwrap(imageProfileName(at: URL(fileURLWithPath: result.wholeImage.cachePath))).contains("sRGB"))
    }

    func testImageIOFormatsRenderOffline() throws {
        for fileName in ["Bird.JPG", "Bird.PNG", "Bird.TIFF"] {
            let root = try temporaryDirectory()
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let image = try writeTestImage(fileName, width: 48, height: 24, in: root)
            let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

            let result = try renderer.renderWholeImage(
                source: try sourceImage(for: image),
                profile: .defaultProfile,
                debugDerivatives: false
            )

            XCTAssertEqual(result.derivatives.count, 1, fileName)
            XCTAssertEqual(result.wholeImage.width, 48, fileName)
            XCTAssertEqual(result.wholeImage.height, 24, fileName)
        }
    }

    func testAllEightOrientationsAreBakedIntoDerivativeDimensions() throws {
        for orientation in 1...8 {
            let root = try temporaryDirectory()
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let image = try writeTestImage("Bird-\(orientation).JPG", width: 40, height: 20, orientation: orientation, in: root)
            let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

            let result = try renderer.renderWholeImage(
                source: try sourceImage(for: image),
                profile: .defaultProfile,
                debugDerivatives: false
            )
            let whole = result.wholeImage

            XCTAssertEqual(whole.appliedOrientation.exifValue, orientation)
            if [5, 6, 7, 8].contains(orientation) {
                XCTAssertEqual(whole.width, 20)
                XCTAssertEqual(whole.height, 40)
            } else {
                XCTAssertEqual(whole.width, 40)
                XCTAssertEqual(whole.height, 20)
            }
        }
    }

    func testSecondRenderReusesCachedDerivatives() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("Bird.JPG", width: 64, height: 32, in: root)
        let source = try sourceImage(for: image)
        let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

        let first = try renderer.renderWholeImage(source: source, profile: .defaultProfile, debugDerivatives: false)
        try FileManager.default.removeItem(at: image)
        let second = try renderer.renderWholeImage(source: source, profile: .defaultProfile, debugDerivatives: false)

        XCTAssertEqual(second.derivatives, first.derivatives)
    }

    func testDecodeFailureIsStructured() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Broken.JPG")
        try Data("not an image".utf8).write(to: image)
        let renderer = ImageRenderer(cache: DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 10_000_000))

        XCTAssertThrowsError(
            try renderer.renderWholeImage(
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
