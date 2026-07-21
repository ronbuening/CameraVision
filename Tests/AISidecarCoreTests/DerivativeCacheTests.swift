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
        XCTAssertNil(
            try cache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))

        let rewritten = try Self.store(Data("good".utf8), in: cache, source: source)
        try Data("bad".utf8).write(to: URL(fileURLWithPath: rewritten.cachePath))

        XCTAssertNil(
            try cache.cachedRecord(
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
        oldCache.releaseRetained()
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
        let manifestLock = root.appendingPathComponent("derivative-cache-index.lock")
        let lockAttributesBefore = try FileManager.default.attributesOfItem(atPath: manifestLock.path)
        let lockIdentifierBefore = lockAttributesBefore[.systemFileNumber]
        let orphan = root.appendingPathComponent("\(String(repeating: "f", count: 64))-recipe-v1-subject_isolated.jpg")
        let unrelated = root.appendingPathComponent("notes.txt")
        try Data("orphan".utf8).write(to: orphan)
        try Data("keep".utf8).write(to: unrelated)

        let result = try cache.clear()

        XCTAssertEqual(result.directoryPath, root.path)
        XCTAssertEqual(result.removedFileCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.cachePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestLock.path))
        let lockAttributesAfter = try FileManager.default.attributesOfItem(atPath: manifestLock.path)
        let lockIdentifierAfter = lockAttributesAfter[.systemFileNumber]
        XCTAssertEqual(lockIdentifierAfter as? NSNumber, lockIdentifierBefore as? NSNumber)
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

    func testDebugCopySkipsExistingDestinationWithMatchingByteCount() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let sourceURL = try writeTestImage("Bird.JPG", in: root)
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 1_024)
        let source = makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG", path: sourceURL.path)
        let record = try Self.store(Data("debug".utf8), in: cache, source: source)
        let first = try cache.copyDebugArtifact(record: record, source: source)
        let debugPath = try XCTUnwrap(first.debugPath)
        let sentinelDate = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: sentinelDate], ofItemAtPath: debugPath)

        let second = try cache.copyDebugArtifact(record: record, source: source)

        let attributes = try FileManager.default.attributesOfItem(atPath: debugPath)
        XCTAssertEqual(second.debugPath, debugPath)
        XCTAssertEqual(attributes[.modificationDate] as? Date, sentinelDate)
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
            XCTAssertNotNil(
                try cache.cachedRecord(
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
            XCTAssertNotNil(
                try caches[0].cachedRecord(
                    source: source,
                    recipeVersion: "recipe-v1",
                    role: .wholeImage,
                    format: .jpeg
                ))
        }
    }

    func testConcurrentStoresEncodeBeforeEnteringManifestCriticalSection() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024 * 1_024)
        let sources = (0..<2).map { index in
            makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(format: "%064x", index + 40)))
        }
        let bothWritersEntered = expectation(description: "both derivative encoders entered")
        let allowWritersToFinish = DispatchSemaphore(value: 0)
        let writerState = ConcurrentWriterState(targetCount: sources.count) {
            bothWritersEntered.fulfill()
        }
        let errors = ConcurrentErrors()
        let group = DispatchGroup()

        for (index, source) in sources.enumerated() {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try cache.store(
                        source: source,
                        recipeVersion: "recipe-v1",
                        role: .wholeImage,
                        format: .jpeg,
                        dimensions: PixelDimensions(width: 10, height: 5),
                        colorSpace: .sRGB,
                        appliedOrientation: AppliedOrientation(exifValue: 1)
                    ) { destination in
                        try Data("cached-\(index)".utf8).write(to: destination)
                        writerState.entered()
                        allowWritersToFinish.wait()
                    }
                } catch {
                    errors.append(error)
                }
            }
        }

        wait(for: [bothWritersEntered], timeout: 2)
        for _ in sources {
            allowWritersToFinish.signal()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(errors.values.isEmpty, "Unexpected store errors: \(errors.values)")
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
            XCTAssertNotNil(
                try readerCache.cachedRecord(
                    source: source,
                    recipeVersion: "recipe-v1",
                    role: .wholeImage,
                    format: .jpeg
                ))
        }

        XCTAssertEqual(fileManager.manifestReadCount, 1)
    }

    func testManifestCacheInvalidatesWhenAtomicReplacementKeepsSizeAndModificationDate() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64)))
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        _ = try Self.store(Data("cached".utf8), in: cache, source: source)

        XCTAssertNotNil(
            try cache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))

        let manifestURL = root.appendingPathComponent("derivative-cache-index.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        let modificationDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let originalData = try Data(contentsOf: manifestURL)
        let originalText = try XCTUnwrap(String(data: originalData, encoding: .utf8))
        let replacedText = originalText.replacingOccurrences(
            of: String(repeating: "a", count: 64),
            with: String(repeating: "b", count: 64)
        )
        let replacedData = Data(replacedText.utf8)
        XCTAssertEqual(replacedData.count, originalData.count)
        try AtomicFileWriter.write(replacedData, to: manifestURL)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: manifestURL.path)

        XCTAssertNil(
            try cache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
    }

    func testActiveArtifactLeaseSurvivesOtherInstanceEvictionUntilRelease() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let firstCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let secondCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let firstSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "4", count: 64))
        )
        let secondSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "5", count: 64))
        )

        let first = try Self.store(Data("first".utf8), in: firstCache, source: firstSource)
        let second = try Self.store(Data("other".utf8), in: secondCache, source: secondSource)

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.cachePath))

        firstCache.releaseRetained()

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.cachePath))
    }

    func testRepeatedLeaseRequiresMatchingReleaseCount() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let firstCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let secondCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let firstSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "c", count: 64))
        )
        let secondSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "d", count: 64))
        )
        let first = try Self.store(Data("first".utf8), in: firstCache, source: firstSource)
        let repeated = try XCTUnwrap(
            firstCache.cachedRecord(
                source: firstSource,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))

        firstCache.release([first])
        let second = try Self.store(Data("other".utf8), in: secondCache, source: secondSource)

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.cachePath))

        firstCache.release([repeated])
        secondCache.releaseRetained()

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.cachePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.cachePath))
    }

    func testPurgePreservesOtherInstanceLeaseAndRemovesItAfterRelease() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let activeCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let purgeCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "6", count: 64)))
        let record = try Self.store(Data("active".utf8), in: activeCache, source: source)

        let whileActive = try purgeCache.purge()

        XCTAssertEqual(whileActive.removedFileCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.cachePath))
        XCTAssertNotNil(
            try purgeCache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))

        purgeCache.releaseRetained()
        activeCache.releaseRetained()
        let afterRelease = try purgeCache.purge()

        XCTAssertEqual(afterRelease.removedFileCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.cachePath))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("derivative-cache-index.lock").path
            ))
    }

    func testStagedStoreRemainsCoherentWhenPurgeRunsBeforeCommit() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let reachedCommitBoundary = expectation(description: "store reached commit boundary")
        let storeCompleted = expectation(description: "store completed")
        let allowCommit = DispatchSemaphore(value: 0)
        let nowState = OneShotDateGate(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            onFirstCall: { reachedCommitBoundary.fulfill() },
            resume: allowCommit
        )
        let storingCache = DerivativeCache(
            directoryPath: root.path,
            sizeCapBytes: 1_024,
            now: { nowState.value() }
        )
        let purgeCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "7", count: 64)))
        let result = ConcurrentRecordResult()

        DispatchQueue.global().async {
            defer { storeCompleted.fulfill() }
            do {
                result.record = try Self.store(Data("staged".utf8), in: storingCache, source: source)
            } catch {
                result.error = error
            }
        }

        wait(for: [reachedCommitBoundary], timeout: 2)
        _ = try purgeCache.purge()
        allowCommit.signal()
        wait(for: [storeCompleted], timeout: 2)

        XCTAssertNil(result.error)
        let record = try XCTUnwrap(result.record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.cachePath))
        XCTAssertEqual(try DerivativeCache.sha256(of: URL(fileURLWithPath: record.cachePath)), record.sha256)
        XCTAssertNotNil(
            try purgeCache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
    }

    func testEvictionFailureKeepsArtifactInManifestAccounting() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let oldSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "8", count: 64))
        )
        let newSource = makeSource(
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "9", count: 64))
        )
        let oldCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 5)
        let oldRecord = try Self.store(Data("older".utf8), in: oldCache, source: oldSource)
        oldCache.releaseRetained()
        let failingFileManager = FailingRemovalFileManager(path: oldRecord.cachePath)
        let newCache = DerivativeCache(
            directoryPath: root.path,
            sizeCapBytes: 5,
            fileManager: failingFileManager
        )

        _ = try Self.store(Data("newer".utf8), in: newCache, source: newSource)

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRecord.cachePath))
        let verifier = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        XCTAssertNotNil(
            try verifier.cachedRecord(
                source: oldSource,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
    }

    func testPurgeRemovesOnlyExpiredCacheAtomicWriterTemps() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let uuid = "123E4567-E89B-12D3-A456-426614174000"
        let base = "\(String(repeating: "a", count: 64))-recipe-v1-whole_image"
        let oldTemp = root.appendingPathComponent(".\(base).\(uuid).jpg")
        let freshTemp = root.appendingPathComponent(".\(base).\(UUID().uuidString).jpg")
        try Data("old".utf8).write(to: oldTemp)
        try Data("fresh".utf8).write(to: freshTemp)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-172_800)],
            ofItemAtPath: oldTemp.path
        )
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: freshTemp.path)
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024, now: { now })

        let result = try cache.purge()

        XCTAssertEqual(result.removedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTemp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshTemp.path))
    }

    func testClearWrapsManifestLockFailureAsStructuredRenderError() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("derivative-cache-index.lock"),
            withIntermediateDirectories: false
        )
        let cache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)

        XCTAssertThrowsError(try cache.clear()) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .renderFailed)
        }
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
        XCTAssertNotNil(
            try cache.cachedRecord(
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

    func testStoreReusesValidLeasedArtifactWhenStagedBytesDiffer() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let holdingCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let storingCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "8", count: 64)))
        let original = try Self.store(Data("encoder-run-one".utf8), in: holdingCache, source: source)

        let reused = try Self.store(Data("encoder-run-two".utf8), in: storingCache, source: source)

        XCTAssertEqual(reused.sha256, original.sha256)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: reused.cachePath)),
            Data("encoder-run-one".utf8)
        )
        holdingCache.releaseRetained()
        storingCache.releaseRetained()
    }

    func testCorruptArtifactLeasedByAnotherInstanceIsMissWithoutRemoval() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let holdingCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let readingCache = DerivativeCache(directoryPath: root.path, sizeCapBytes: 1_024)
        let source = makeSource(identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "9", count: 64)))
        let record = try Self.store(Data("good".utf8), in: holdingCache, source: source)
        // Non-atomic in-place write keeps the inode the active lease pins.
        try Data("bad!".utf8).write(to: URL(fileURLWithPath: record.cachePath))

        XCTAssertNil(
            try readingCache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.cachePath))

        holdingCache.releaseRetained()

        XCTAssertNil(
            try readingCache.cachedRecord(
                source: source,
                recipeVersion: "recipe-v1",
                role: .wholeImage,
                format: .jpeg
            ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.cachePath))
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

private final class ConcurrentWriterState: @unchecked Sendable {
    private let lock = NSLock()
    private let targetCount: Int
    private let onTarget: () -> Void
    private var count = 0

    init(targetCount: Int, onTarget: @escaping () -> Void) {
        self.targetCount = targetCount
        self.onTarget = onTarget
    }

    func entered() {
        let reachedTarget = lock.withLock { () -> Bool in
            count += 1
            return count == targetCount
        }
        if reachedTarget {
            onTarget()
        }
    }
}

private final class OneShotDateGate: @unchecked Sendable {
    private let lock = NSLock()
    private let date: Date
    private let onFirstCall: () -> Void
    private let resume: DispatchSemaphore
    private var firstCall = true

    init(date: Date, onFirstCall: @escaping () -> Void, resume: DispatchSemaphore) {
        self.date = date
        self.onFirstCall = onFirstCall
        self.resume = resume
    }

    func value() -> Date {
        let shouldWait = lock.withLock { () -> Bool in
            defer { firstCall = false }
            return firstCall
        }
        if shouldWait {
            onFirstCall()
            resume.wait()
        }
        return date
    }
}

private final class ConcurrentRecordResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecord: DerivativeRecord?
    private var storedError: Error?

    var record: DerivativeRecord? {
        get { lock.withLock { storedRecord } }
        set { lock.withLock { storedRecord = newValue } }
    }

    var error: Error? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }
}

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    private let failingPath: String

    init(path: String) {
        self.failingPath = path
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL.path == failingPath {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
