import Foundation
import XCTest
@testable import AISidecarCore

final class DerivativeCacheTests: XCTestCase {
    func testContentAddressedStoreAndReuseUpdatesManifestHit() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64)))

        let record = try store(Data("cached".utf8), in: cache, source: source)
        let cached = try cache.cachedRecord(
            source: source,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg
        )

        XCTAssertEqual(cached, record)
    }

    func testMissingAndCorruptArtifactsAreCacheMisses() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "b", count: 64)))
        let record = try store(Data("good".utf8), in: cache, source: source)

        try FileManager.default.removeItem(atPath: record.cachePath)
        XCTAssertNil(try cache.cachedRecord(
            source: source,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg
        ))

        let rewritten = try store(Data("good".utf8), in: cache, source: source)
        try Data("bad".utf8).write(to: URL(fileURLWithPath: rewritten.cachePath))

        XCTAssertNil(try cache.cachedRecord(
            source: source,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rewritten.cachePath))
    }

    func testLRUEvictionRemovesOlderArtifactsUnderCap() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let oldSource = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "c", count: 64)))
        let newSource = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "d", count: 64)))
        let oldCache = DerivativeCache(
            directoryPath: root.path,
            sizeCapBytes: 8,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let newCache = DerivativeCache(
            directoryPath: root.path,
            sizeCapBytes: 8,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let oldRecord = try store(Data("older".utf8), in: oldCache, source: oldSource)
        let newRecord = try store(Data("newer".utf8), in: newCache, source: newSource)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRecord.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newRecord.cachePath))
    }

    func testDebugCopyUsesSourceSidecarDerivativeNaming() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let sourceURL = try writeTestImage("Bird.JPG", in: root)
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 1_024)
        let source = makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: sourceURL.path)
        let record = try store(Data("debug".utf8), in: cache, source: source)

        let copied = try cache.copyDebugArtifact(record: record, source: source)

        XCTAssertEqual(copied.debugPath, root.appendingPathComponent("Bird.JPG.aisidecar.whole_image.jpg").path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: copied.debugPath!)), Data("debug".utf8))
    }

    private func store(_ data: Data, in cache: DerivativeCache, source: SourceImage) throws -> DerivativeRecord {
        try cache.store(
            source: source,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg,
            dimensions: PixelDimensions(width: 10, height: 5),
            colorSpace: .sRGB,
            appliedOrientation: AppliedOrientation(exifValue: 1)
        ) { destination in
            try data.write(to: destination)
        }
    }

    private func makeSource(
        fileName: String = "Bird.JPG",
        relativePath: String = "Bird.JPG",
        path: String = "/photos/Bird.JPG",
        identity: SourceIdentity = SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
    ) -> SourceImage {
        SourceImage(
            path: path,
            relativePath: relativePath,
            fileName: fileName,
            fileExtension: URL(fileURLWithPath: fileName).pathExtension,
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: identity
        )
    }
}
