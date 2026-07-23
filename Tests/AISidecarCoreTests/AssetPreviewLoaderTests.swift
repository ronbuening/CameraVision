import Foundation
import XCTest

@testable import AISidecarCore

final class AssetPreviewLoaderTests: XCTestCase {
    private final class VirtualSidecarFileManager: FileManager, @unchecked Sendable {
        private let sidecarPath: String
        private let sidecarData: Data?
        private let lock = NSLock()
        private var _readCount = 0

        var readCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _readCount
        }

        init(sidecarPath: String, sidecarData: Data?) {
            self.sidecarPath = sidecarPath
            self.sidecarData = sidecarData
            super.init()
        }

        override func fileExists(atPath path: String) -> Bool {
            path == sidecarPath
        }

        override func contents(atPath path: String) -> Data? {
            guard path == sidecarPath else {
                return nil
            }
            lock.lock()
            _readCount += 1
            lock.unlock()
            return sidecarData
        }
    }

    func testPresentationIsSendableAndEquatable() {
        requireSendable(AssetPreviewPresentation.self)
        let presentation = AssetPreviewPresentation(
            sourcePath: "/photos/Bird.jpg",
            rawSidecarPath: "/photos/Bird.jpg.ai.json"
        )

        XCTAssertEqual(presentation, presentation)
    }

    func testLoaderUsesCanonicalOutputPathAndLastExistingDerivativePerRole() throws {
        let root = try temporaryDirectory()
        let sourcePath = root.appendingPathComponent("source/Bird.JPG").path
        let outputDir = root.appendingPathComponent("output", isDirectory: true)
        let sidecarURL = outputDir.appendingPathComponent("nested/Bird.JPG.ai.json")
        let wholeFirst = root.appendingPathComponent("whole-first.jpg")
        let wholeLast = root.appendingPathComponent("whole-last.jpg")
        let wholeMissing = root.appendingPathComponent("whole-missing.jpg")
        let fullResolution = root.appendingPathComponent("full-resolution.jpg")
        let subjectFirst = root.appendingPathComponent("subject-first.jpg")
        let subjectLast = root.appendingPathComponent("subject-last.jpg")
        let subjectMissing = root.appendingPathComponent("subject-missing.jpg")
        for url in [wholeFirst, wholeLast, fullResolution, subjectFirst, subjectLast] {
            try Data().write(to: url)
        }

        let sidecar = makeSidecar(
            sourcePath: sourcePath,
            derivatives: [
                derivative(role: .wholeImage, path: wholeFirst.path),
                derivative(role: .wholeImage, path: wholeLast.path),
                derivative(role: .wholeImage, path: wholeMissing.path),
                derivative(role: .fullResolution, path: fullResolution.path),
                derivative(role: .subjectIsolated, path: subjectFirst.path),
                derivative(role: .subjectIsolated, path: subjectLast.path),
                derivative(role: .subjectIsolated, path: subjectMissing.path),
            ],
            subjectIsolation: subjectIsolation(),
            modelRuns: [modelRun(), modelRun()],
            errors: [
                SidecarError(
                    code: .modelSchemaViolation,
                    stage: .model,
                    message: "fixture schema violation",
                    recoverable: true
                )
            ]
        )
        try FileManager.default.createDirectory(
            at: sidecarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONCoding.documentEncoder().encode(sidecar).write(to: sidecarURL)

        let presentation = AssetPreviewLoader().load(
            sourcePath: sourcePath,
            relativePath: "nested/Bird.JPG",
            outputDir: outputDir.path
        )

        XCTAssertEqual(presentation.sourcePath, sourcePath)
        XCTAssertEqual(presentation.rawSidecarPath, sidecarURL.standardizedFileURL.path)
        XCTAssertEqual(presentation.wholeImageDerivativePath, wholeLast.path)
        XCTAssertEqual(presentation.subjectImageDerivativePath, subjectLast.path)
        XCTAssertNotEqual(presentation.wholeImageDerivativePath, fullResolution.path)
        XCTAssertNotEqual(presentation.subjectImageDerivativePath, fullResolution.path)
        XCTAssertEqual(presentation.instanceCount, 2)
        XCTAssertEqual(presentation.selectedInstanceIndices, [1])
        XCTAssertEqual(presentation.isolationStatus, "success")
        XCTAssertEqual(presentation.modelRunCount, 2)
        XCTAssertNil(presentation.keywordCandidateCount)
        XCTAssertEqual(
            presentation.sidecarErrors,
            ["E_MODEL_SCHEMA_VIOLATION: fixture schema violation"]
        )
    }

    func testLoaderKeepsIsolationFactsAfterDerivativeCachePurge() throws {
        let root = try temporaryDirectory()
        let sourcePath = root.appendingPathComponent("Bird.jpg").path
        let sidecarURL = URL(fileURLWithPath: sourcePath + SidecarNaming.taggingSuffix)
        let purgedPath = root.appendingPathComponent("purged-subject.jpg").path
        let sidecar = makeSidecar(
            sourcePath: sourcePath,
            derivatives: [derivative(role: .subjectIsolated, path: purgedPath)],
            subjectIsolation: subjectIsolation()
        )
        try JSONCoding.documentEncoder().encode(sidecar).write(to: sidecarURL)

        let presentation = AssetPreviewLoader().load(
            sourcePath: sourcePath,
            relativePath: "Bird.jpg",
            outputDir: nil
        )

        XCTAssertNil(presentation.subjectImageDerivativePath)
        XCTAssertEqual(presentation.instanceCount, 2)
        XCTAssertEqual(presentation.selectedInstanceIndices, [1])
        XCTAssertEqual(presentation.isolationStatus, "success")
    }

    func testMissingSidecarIsAnEmptyPresentation() {
        let presentation = AssetPreviewLoader().load(
            sourcePath: "/missing/Bird.jpg",
            relativePath: "Bird.jpg",
            outputDir: nil
        )

        XCTAssertEqual(presentation.rawSidecarPath, "/missing/Bird.jpg.ai.json")
        XCTAssertEqual(presentation.modelRunCount, 0)
        XCTAssertEqual(presentation.sidecarErrors, [])
    }

    func testUnreadableSidecarRetainsPreviewErrorAndReadsOnce() {
        let sourcePath = "/virtual/Unreadable.jpg"
        let sidecarPath = "\(sourcePath)\(SidecarNaming.taggingSuffix)"
        let fileManager = VirtualSidecarFileManager(sidecarPath: sidecarPath, sidecarData: nil)

        let presentation = AssetPreviewLoader(fileManager: fileManager).load(
            sourcePath: sourcePath,
            relativePath: "Unreadable.jpg",
            outputDir: nil
        )

        XCTAssertEqual(presentation.sidecarErrors, ["sidecar unreadable: Unreadable.jpg.ai.json"])
        XCTAssertEqual(fileManager.readCount, 1)
    }

    func testMalformedSidecarMatchesLegacyDirectDecodeError() {
        let sourcePath = "/virtual/Malformed.jpg"
        let sidecarPath = "\(sourcePath)\(SidecarNaming.taggingSuffix)"
        let sidecarData = Data("not json".utf8)
        let fileManager = VirtualSidecarFileManager(
            sidecarPath: sidecarPath,
            sidecarData: sidecarData
        )

        let presentation = AssetPreviewLoader(fileManager: fileManager).load(
            sourcePath: sourcePath,
            relativePath: "Malformed.jpg",
            outputDir: nil
        )

        let expectedMessage: String
        do {
            _ = try JSONCoding.decoder().decode(RawJSONSidecar.self, from: sidecarData)
            XCTFail("Malformed fixture unexpectedly decoded")
            expectedMessage = ""
        } catch {
            expectedMessage = "sidecar malformed: \(error.localizedDescription)"
        }
        XCTAssertEqual(presentation.sidecarErrors, [expectedMessage])
        XCTAssertEqual(fileManager.readCount, 1)
    }

    func testFutureMajorSchemaRetainsPreviewDecodeTolerance() throws {
        let sourcePath = "/virtual/Future.jpg"
        let sidecarPath = "\(sourcePath)\(SidecarNaming.taggingSuffix)"
        var sidecar = makeSidecar(sourcePath: sourcePath)
        sidecar.schemaVersion = "ai-sidecar-json/2.0"
        let fileManager = VirtualSidecarFileManager(
            sidecarPath: sidecarPath,
            sidecarData: try JSONCoding.documentEncoder().encode(sidecar)
        )

        let presentation = AssetPreviewLoader(fileManager: fileManager).load(
            sourcePath: sourcePath,
            relativePath: "Future.jpg",
            outputDir: nil
        )

        XCTAssertEqual(presentation.modelRunCount, 0)
        XCTAssertEqual(presentation.sidecarErrors, [])
        XCTAssertEqual(fileManager.readCount, 1)
    }

    func testValidVirtualSidecarIsReadExactlyOnce() throws {
        let sourcePath = "/virtual/Bird.jpg"
        let sidecarPath = "\(sourcePath)\(SidecarNaming.taggingSuffix)"
        let fileManager = VirtualSidecarFileManager(
            sidecarPath: sidecarPath,
            sidecarData: try JSONCoding.documentEncoder().encode(makeSidecar(sourcePath: sourcePath))
        )

        let presentation = AssetPreviewLoader(fileManager: fileManager).load(
            sourcePath: sourcePath,
            relativePath: "Bird.jpg",
            outputDir: nil
        )

        XCTAssertEqual(presentation.sidecarErrors, [])
        XCTAssertEqual(fileManager.readCount, 1)
    }

    private func makeSidecar(
        sourcePath: String,
        derivatives: [DerivativeRecord] = [],
        subjectIsolation: SubjectIsolationRecord? = nil,
        modelRuns: [ModelRunRecord] = [],
        errors: [SidecarError] = []
    ) -> RawJSONSidecar {
        RawJSONSidecar(
            source: source(for: sourcePath),
            runConfiguration: .builtInDefaults,
            derivatives: derivatives,
            subjectIsolation: subjectIsolation,
            modelRuns: modelRuns,
            errors: errors,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func source(for path: String) -> SourceImage {
        SourceImage(
            path: path,
            relativePath: URL(fileURLWithPath: path).lastPathComponent,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            fileExtension: "jpg",
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: sourceIdentity
        )
    }

    private func derivative(role: DerivativeRole, path: String) -> DerivativeRecord {
        DerivativeRecord(
            role: role,
            cachePath: path,
            format: .jpeg,
            width: 64,
            height: 32,
            colorSpace: .sRGB,
            appliedOrientation: AppliedOrientation(exifValue: 1),
            recipeVersion: "preview-test",
            sha256: String(repeating: "b", count: 64),
            sourceIdentity: sourceIdentity
        )
    }

    private func subjectIsolation() -> SubjectIsolationRecord {
        SubjectIsolationRecord(
            status: .success,
            instanceCount: 2,
            selectedInstanceIndices: [1],
            mergedInstances: false,
            instances: [],
            analysisResolution: PixelDimensions(width: 32, height: 24),
            fullResolution: PixelDimensions(width: 64, height: 48),
            scaleFactors: SubjectIsolationScaleFactors(x: 2, y: 2),
            selectedBoundingBox: nil,
            cropBoundingBox: nil,
            cropMarginFraction: 0.08,
            cropMarginPixels: 4,
            mergeDominanceThreshold: 0.72,
            selectedToUnionAreaRatio: nil,
            matteRGB: [128, 128, 128],
            finalDimensions: PixelDimensions(width: 32, height: 32),
            upscaled: false
        )
    }

    private func modelRun() -> ModelRunRecord {
        ModelRunRecord(
            inputRole: .wholeImage,
            model: "fixture",
            modelDigest: "sha256:fixture",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "preview-test/1",
            promptSHA256: String(repeating: "c", count: 64),
            responseSchemaVersion: "preview-response/1",
            requestOptions: ModelRunOptions(seed: 1),
            inputDerivativeSHA256: String(repeating: "b", count: 64),
            rawResponseText: "{}",
            parsedResponseJSON: .object([:]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
    }

    private var sourceIdentity: SourceIdentity {
        SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-preview-loader-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.standardizedFileURL
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
