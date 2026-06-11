import CoreGraphics
import XCTest
@testable import AISidecarCore

final class SubjectIsolationServiceTests: XCTestCase {
    func testSmallSubjectUsesFullResolutionCropBeforeDownsize() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("SmallSubject.JPG", width: 1_000, height: 500, in: root)
        let source = try testSourceImage(for: image)
        let profile = smallAnalysisProfile()
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 20_000_000)
        let prepared = try ImageRenderer(cache: cache).prepareSourceRender(source: source, profile: profile)
        XCTAssertEqual(prepared.analysisDimensions.width, 200)
        XCTAssertEqual(prepared.analysisDimensions.height, 100)

        let service = SubjectIsolationService(
            cache: cache,
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 92, y: 45, width: 16, height: 10))
            ])
        )
        let result = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile)
        )

        let crop = try XCTUnwrap(result.record.cropBoundingBox)
        let derivative = try XCTUnwrap(result.derivative)
        XCTAssertEqual(result.record.status, .success)
        XCTAssertEqual(result.record.scaleFactors.x, 5)
        XCTAssertEqual(result.record.scaleFactors.y, 5)
        XCTAssertGreaterThan(crop.width, 20)
        XCTAssertGreaterThan(derivative.width, 20)
        XCTAssertEqual(derivative.role, .subjectIsolated)
        XCTAssertFalse(result.record.upscaled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.artifactURL(
            source: source,
            recipeVersion: prepared.recipeVersion,
            role: .wholeImage,
            format: profile.preferredWholeImageFormat
        ).path))
    }

    func testMultiInstanceMergeRecordsSelectionAndBoxes() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("MergedSubject.JPG", width: 400, height: 200, in: root)
        let source = try testSourceImage(for: image)
        let profile = ModelInputProfile.defaultProfile
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 20_000_000)
        let prepared = try ImageRenderer(cache: cache).prepareSourceRender(source: source, profile: profile)
        let service = SubjectIsolationService(
            cache: cache,
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 40, y: 40, width: 200, height: 100)),
                StaticMaskSpec(index: 2, rect: CGRect(x: 230, y: 85, width: 10, height: 10))
            ])
        )

        let result = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile)
        )

        XCTAssertEqual(result.record.instanceCount, 2)
        XCTAssertEqual(result.record.selectedInstanceIndices, [1, 2])
        XCTAssertTrue(result.record.mergedInstances)
        XCTAssertEqual(result.record.instances.map(\.index), [1, 2])
        XCTAssertNotNil(result.record.selectedToUnionAreaRatio)
    }

    func testCropMarginClampsAtImageEdges() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("EdgeSubject.JPG", width: 200, height: 100, in: root)
        let source = try testSourceImage(for: image)
        let profile = ModelInputProfile.defaultProfile
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 20_000_000)
        let prepared = try ImageRenderer(cache: cache).prepareSourceRender(source: source, profile: profile)
        let service = SubjectIsolationService(
            cache: cache,
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 0, y: 0, width: 20, height: 20))
            ])
        )

        let result = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile)
        )

        let crop = try XCTUnwrap(result.record.cropBoundingBox)
        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.y, 0)
        XCTAssertGreaterThan(crop.width, 20)
        XCTAssertGreaterThan(crop.height, 20)
    }

    func testNoForegroundReturnsRecoverableIsolationError() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("NoSubject.JPG", width: 200, height: 100, in: root)
        let source = try testSourceImage(for: image)
        let profile = ModelInputProfile.defaultProfile
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 20_000_000)
        let prepared = try ImageRenderer(cache: cache).prepareSourceRender(source: source, profile: profile)
        let service = SubjectIsolationService(cache: cache, maskProvider: StaticForegroundMaskProvider([]))

        let result = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile)
        )

        XCTAssertNil(result.derivative)
        XCTAssertEqual(result.record.status, .noForeground)
        XCTAssertEqual(result.error?.code, .subjectIsolationNoForeground)
        XCTAssertEqual(result.error?.stage, .isolate)
    }

    func testSubjectDerivativeCacheSeparatesMarginSettings() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let image = try writeTestImage("CacheSubject.JPG", width: 300, height: 200, in: root)
        let source = try testSourceImage(for: image)
        let profile = ModelInputProfile.defaultProfile
        let cache = DerivativeCache(directoryPath: root.appendingPathComponent("cache").path, sizeCapBytes: 20_000_000)
        let prepared = try ImageRenderer(cache: cache).prepareSourceRender(source: source, profile: profile)
        let service = SubjectIsolationService(
            cache: cache,
            maskProvider: StaticForegroundMaskProvider([
                StaticMaskSpec(index: 1, rect: CGRect(x: 100, y: 60, width: 40, height: 30))
            ])
        )

        let first = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile, margin: 0.08)
        )
        let second = try await service.isolate(
            source: source,
            prepared: prepared,
            profile: profile,
            configuration: config(profile: profile, margin: 0.20)
        )

        XCTAssertNotEqual(first.derivative?.cachePath, second.derivative?.cachePath)
        XCTAssertNotEqual(first.record.cropBoundingBox?.width, second.record.cropBoundingBox?.width)
    }

    private func smallAnalysisProfile() -> ModelInputProfile {
        ModelInputProfile(
            name: "small-test-profile",
            maxLongEdge: 200,
            maxTotalPixels: 20_000,
            colorSpace: .sRGB,
            preferredWholeImageFormat: .jpeg,
            jpegQuality: 0.9,
            preferredSubjectFormat: "jpeg-neutral-matte",
            matteRGB: [128, 128, 128],
            allowUpscaleSubjectByDefault: false
        )
    }

    private func config(profile: ModelInputProfile, margin: Double = 0.08) -> ResolvedRunConfiguration {
        ResolvedRunConfiguration(
            mode: .subject,
            existing: .skip,
            recursive: false,
            outputDir: nil,
            model: ResolvedRunConfiguration.builtInDefaults.model,
            modelEndpoint: ResolvedRunConfiguration.builtInDefaults.modelEndpoint,
            profile: profile.name,
            logLevel: .debug,
            logFormat: .json,
            dryRun: false,
            debugDerivatives: false,
            sourceIdentityPolicy: .sha256,
            derivativeCacheDir: DerivativeCache.defaultDirectoryPath(),
            derivativeCacheSizeBytes: 20_000_000,
            subjectCropMarginFraction: margin
        )
    }
}
