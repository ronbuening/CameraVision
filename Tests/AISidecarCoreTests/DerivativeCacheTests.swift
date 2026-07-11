import Foundation
import XCTest
@testable import AISidecarCore

final class DerivativeCacheTests: XCTestCase {
    func testContentAddressedStoreAndReuseUpdatesManifestHit() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64)))

        let record = try Self.store(Data("cached".utf8), in: cache, source: source)
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
        let record = try Self.store(Data("good".utf8), in: cache, source: source)

        try FileManager.default.removeItem(atPath: record.cachePath)
        XCTAssertNil(try cache.cachedRecord(
            source: source,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg
        ))

        let rewritten = try Self.store(Data("good".utf8), in: cache, source: source)
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

        let oldRecord = try Self.store(Data("older".utf8), in: oldCache, source: oldSource)
        let newRecord = try Self.store(Data("newer".utf8), in: newCache, source: newSource)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRecord.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newRecord.cachePath))
    }

    func testClearRemovesCacheOwnedArtifactsOnly() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "e", count: 64)))
        let record = try Self.store(Data("cached".utf8), in: cache, source: source)
        let manifest = root.appendingPathComponent("derivative-cache-index.json")
        let orphan = root.appendingPathComponent("\(String(repeating: "f", count: 64))-recipe-v1-subject_isolated.jpg")
        let unrelated = root.appendingPathComponent("notes.txt")
        try Data("orphan".utf8).write(to: orphan)
        try Data("keep".utf8).write(to: unrelated)

        let result = try cache.clear()

        XCTAssertEqual(result.directoryPath, root.path)
        XCTAssertEqual(result.removedFileCount, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.cachePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("derivative-cache-index.lock").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testDebugCopyUsesSourceSidecarDerivativeNaming() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let sourceURL = try writeTestImage("Bird.JPG", in: root)
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 1_024)
        let source = makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: sourceURL.path)
        let record = try Self.store(Data("debug".utf8), in: cache, source: source)

        let copied = try cache.copyDebugArtifact(record: record, source: source)

        XCTAssertEqual(copied.debugPath, root.appendingPathComponent("Bird.JPG.aisidecar.whole_image.jpg").path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: copied.debugPath!)), Data("debug".utf8))
    }

    func testConcurrentStoresForDistinctDerivativesAllLandInManifest() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024 * 1_024)
        let sources = (0..<8).map { index in
            makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(format: "%064x", index + 1)))
        }
        let errors = ConcurrentErrors()

        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            do {
                _ = try Self.store(Data("cached-\(index)".utf8), in: cache, source: sources[index])
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.values.isEmpty, "Unexpected store errors: \(errors.values)")
        for source in sources {
            XCTAssertNotNil(try cache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
        }
    }

    func testTwoCacheInstancesInterleavingStoresLoseNoManifestEntries() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let caches = [
            DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024 * 1_024),
            DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024 * 1_024),
        ]
        let sources = (0..<8).map { index in
            makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(format: "%064x", index + 20)))
        }
        let errors = ConcurrentErrors()

        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            do {
                _ = try Self.store(
                    Data("cached-\(index)".utf8),
                    in: caches[index % caches.count],
                    source: sources[index]
                )
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.values.isEmpty, "Unexpected store errors: \(errors.values)")
        for source in sources {
            XCTAssertNotNil(try caches[0].cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
        }
    }

    func testRepeatedCachedRecordHitsDoNotRereadManifestFile() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "9", count: 64)))
        let writerCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        _ = try Self.store(Data("cached".utf8), in: writerCache, source: source)
        let manifestPath = root.appendingPathComponent("derivative-cache-index.json").path
        let fileManager = CountingFileManager(manifestPath: manifestPath)
        let readerCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024, fileManager: fileManager)

        for _ in 0..<4 {
            XCTAssertNotNil(try readerCache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
        }

        XCTAssertEqual(fileManager.manifestReadCount, 1)
    }

    func testEvictionSkipsRetainedWorkingSetUnderTinyCap() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let firstSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "1", count: 64))
        )
        let secondSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "2", count: 64))
        )
        let thirdSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "3", count: 64))
        )
        let first = try Self.store(Data("first".utf8), in: cache, source: firstSource)
        cache.releaseRetained()
        XCTAssertNotNil(try cache.cachedRecord(
            source: firstSource,
            recipeVersion: "recipe-v1",
            role: .wholeImage,
            format: .jpeg
        ))

        let second = try Self.store(Data("other".utf8), in: cache, source: secondSource)

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.cachePath))

        cache.releaseRetained()
        let third = try Self.store(Data("third".utf8), in: cache, source: thirdSource)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.cachePath))
    }

    private static func store(_ data: Data, in cache: DerivativeCache, source: SourceImage) throws -> DerivativeRecord {
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

private final class ConcurrentErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func append(_ error: Error) {
        lock.withLock {
            storage.append(error)
        }
    }
}

private final class CountingFileManager: FileManager, @unchecked Sendable {
    private let countLock = NSLock()
    private let manifestPath: String
    private var readCount = 0

    init(manifestPath: String) {
        self.manifestPath = manifestPath
        super.init()
    }

    var manifestReadCount: Int {
        countLock.withLock { readCount }
    }

    override func contents(atPath path: String) -> Data? {
        if path == manifestPath {
            countLock.withLock {
                readCount += 1
            }
        }
        return super.contents(atPath: path)
    }
}
