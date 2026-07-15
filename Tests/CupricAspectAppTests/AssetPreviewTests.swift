import AISidecarCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import CupricAspectApp

/// M3: preview-detail extraction from a real pipeline sidecar, and thumbnail
/// decoding. The fixture is an `.ai.json` written by `AnalyzePipeline` (mode
/// `both`) with only its filesystem paths sanitized, so decode drift from Core
/// fails here.
final class AssetPreviewTests: XCTestCase {
    private final class DecodeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return _count
        }

        func increment() {
            lock.lock()
            _count += 1
            lock.unlock()
        }
    }

    private final class UnreadableSidecarFileManager: FileManager, @unchecked Sendable {
        let unreadablePath: String

        init(unreadablePath: String) {
            self.unreadablePath = unreadablePath
            super.init()
        }

        override func fileExists(atPath path: String) -> Bool {
            path == unreadablePath || super.fileExists(atPath: path)
        }

        override func contents(atPath path: String) -> Data? {
            path == unreadablePath ? nil : super.contents(atPath: path)
        }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeJPEG(_ name: String, width: Int = 48, height: Int = 30) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = root.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    private func loadFixture() throws -> RawJSONSidecar {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "sample-analyzed.ai", withExtension: "json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RawJSONSidecar.self, from: Data(contentsOf: fixtureURL))
    }

    /// Re-point the fixture's derivative cache paths into the test's temp dir
    /// so the test controls which derivatives "exist" regardless of the
    /// machine's real shared cache.
    private func materializeFixture(
        wholeImageExists: Bool,
        subjectExists: Bool
    ) throws -> String {
        var sidecar = try loadFixture()
        for index in sidecar.derivatives.indices {
            let role = sidecar.derivatives[index].role
            let name = "derivative-\(role.rawValue).jpg"
            let url = root.appendingPathComponent(name)
            sidecar.derivatives[index].cachePath = url.path
            if (role == .wholeImage && wholeImageExists) || (role == .subjectIsolated && subjectExists) {
                _ = try writeJPEG(name)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sidecarURL = root.appendingPathComponent("rewritten.ai.json")
        try encoder.encode(sidecar).write(to: sidecarURL)
        return sidecarURL.path
    }

    func testRecordedFixtureUsesMachineNeutralPaths() throws {
        let sidecar = try loadFixture()
        let fixtureRoot = "/nonexistent/aisidecar-fixture"

        XCTAssertEqual(sidecar.source.path, "\(fixtureRoot)/source/DSC_0421.jpg")
        XCTAssertEqual(sidecar.runConfiguration.derivativeCacheDir, "\(fixtureRoot)/cache")
        XCTAssertTrue(sidecar.derivatives.allSatisfy { $0.cachePath.hasPrefix("\(fixtureRoot)/cache/") })
    }

    func testPreviewDetailsDecodeRealPipelineSidecar() throws {
        let sourceURL = try writeJPEG("DSC_0421.jpg")
        let sidecarPath = try materializeFixture(wholeImageExists: false, subjectExists: false)

        let details = AssetPreviewDetails.load(
            sourcePath: sourceURL.path,
            rawSidecarPath: sidecarPath
        )

        XCTAssertEqual(details.modelRunCount, 2)
        XCTAssertEqual(details.instanceCount, 1)
        XCTAssertEqual(details.selectedInstanceIndices, [1])
        XCTAssertEqual(details.isolationStatus, "success")
        XCTAssertEqual(details.sidecarErrors.count, 2)
        XCTAssertTrue(details.sidecarErrors.allSatisfy { $0.hasPrefix("E_MODEL_SCHEMA_VIOLATION") })
        // No derivatives on disk → large preview falls back to the source.
        XCTAssertNotNil(details.fullImage)
        XCTAssertNil(details.subjectImage)
    }

    func testPreviewPrefersCachedDerivativesWhenPresent() throws {
        let sourceURL = try writeJPEG("DSC_0421.jpg")
        let sidecarPath = try materializeFixture(wholeImageExists: true, subjectExists: true)

        let details = AssetPreviewDetails.load(
            sourcePath: sourceURL.path,
            rawSidecarPath: sidecarPath
        )

        XCTAssertNotNil(details.fullImage)
        XCTAssertNotNil(details.subjectImage, "subject panel shows when the cached derivative exists (FR4-014)")
    }

    func testPreviewDetailsWithoutSidecarStillLoadsSource() throws {
        let sourceURL = try writeJPEG("plain.jpg")
        let details = AssetPreviewDetails.load(
            sourcePath: sourceURL.path,
            rawSidecarPath: root.appendingPathComponent("missing.ai.json").path
        )
        XCTAssertNotNil(details.fullImage)
        XCTAssertNil(details.instanceCount)
        XCTAssertEqual(details.modelRunCount, 0)
        XCTAssertEqual(details.sidecarErrors, [])
    }

    func testPreviewReportsMalformedSidecar() throws {
        let sourceURL = try writeJPEG("malformed.jpg")
        let sidecarURL = root.appendingPathComponent("malformed.jpg.ai.json")
        try Data("not json".utf8).write(to: sidecarURL)

        let details = AssetPreviewDetails.load(
            sourcePath: sourceURL.path,
            rawSidecarPath: sidecarURL.path
        )

        XCTAssertNotNil(details.fullImage)
        XCTAssertTrue(details.sidecarErrors.first?.hasPrefix("sidecar malformed:") == true)
    }

    func testPreviewReportsUnreadableSidecar() throws {
        let sourceURL = try writeJPEG("unreadable.jpg")
        let sidecarURL = root.appendingPathComponent("unreadable.jpg.ai.json")
        let fileManager = UnreadableSidecarFileManager(unreadablePath: sidecarURL.path)

        let details = AssetPreviewDetails.load(
            sourcePath: sourceURL.path,
            rawSidecarPath: sidecarURL.path,
            fileManager: fileManager
        )

        XCTAssertNotNil(details.fullImage)
        XCTAssertEqual(details.sidecarErrors, ["sidecar unreadable: unreadable.jpg.ai.json"])
    }

    func testThumbnailDecodeRespectsMaxPixelAndFailsCleanly() throws {
        let sourceURL = try writeJPEG("thumb.jpg", width: 640, height: 400)

        let thumbnail = try XCTUnwrap(
            ThumbnailStore.decodeThumbnail(path: sourceURL.path, maxPixel: 128)
        )
        XCTAssertLessThanOrEqual(max(thumbnail.image.width, thumbnail.image.height), 128)

        XCTAssertNil(ThumbnailStore.decodeThumbnail(path: root.appendingPathComponent("nope.jpg").path, maxPixel: 128))
    }

    @MainActor
    func testUndecodableThumbnailIsNegativelyCachedAndNotRedecoded() async throws {
        let counter = DecodeCounter()
        let store = ThumbnailStore(decodeProvider: { _, _ in
            counter.increment()
            return nil
        })
        let path = root.appendingPathComponent("garbage.jpg").path

        let first = await store.thumbnail(for: path)
        let second = await store.thumbnail(for: path)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(counter.count, 1)
    }
}
