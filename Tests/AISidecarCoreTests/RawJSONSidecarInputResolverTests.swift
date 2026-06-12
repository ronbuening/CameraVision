import Foundation
import XCTest
@testable import AISidecarCore

final class RawJSONSidecarInputResolverTests: XCTestCase {
    func testReaderAcceptsSupportedMajorOneVersions() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: root)
        let sourceImage = try makeSourceImage(for: source)
        let reader = RawJSONSidecarReader()

        for schemaVersion in ["ai-sidecar-json/1.0", "ai-sidecar-json/1.2", "ai-sidecar-json/1.99"] {
            let sidecar = try writeSidecar(
                makeSidecar(source: sourceImage, schemaVersion: schemaVersion),
                named: "Bird-\(schemaVersion.replacingOccurrences(of: "/", with: "-")).JPG.ai.json",
                in: root
            )

            let document = try reader.read(from: sidecar)

            XCTAssertEqual(document.sidecar.schemaVersion, schemaVersion)
        }
    }

    func testReaderRejectsUnsupportedMajorVersion() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: root)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source), schemaVersion: "ai-sidecar-json/2.0"),
            named: "Bird.JPG.ai.json",
            in: root
        )

        try assertSidecarError(code: .schemaUnsupported, stage: .scan) {
            _ = try RawJSONSidecarReader().read(from: sidecar)
        }
    }

    func testDirectFromJSONResolvesSingleFile() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: root)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source)),
            named: "Bird.JPG.ai.json",
            in: root
        )

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration()
        )

        XCTAssertEqual(batch.inputs.count, 1)
        XCTAssertTrue(batch.failures.isEmpty)
        XCTAssertEqual(batch.inputs.first?.sidecarPath, sidecar.standardizedFileURL)
        XCTAssertEqual(batch.inputs.first?.sourcePath, source.standardizedFileURL)
        XCTAssertEqual(batch.inputs.first?.sourceIdentityStatus, .matched)
        XCTAssertEqual(batch.inputs.first?.relativePath, "Bird.JPG.ai.json")
    }

    func testDirectFromJSONRejectsNonSidecarFile() throws {
        let root = try temporaryDirectory()
        let file = try writeSource("Bird.JPG", data: Data("source".utf8), in: root)

        try assertSidecarError(code: .validationFailed, stage: .scan) {
            _ = try RawJSONSidecarInputResolver().resolve(fromJSONPath: file.path, configuration: configuration())
        }
    }

    func testFlatFolderScanFiltersRawSidecarsOnly() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("A.JPG", data: Data("a".utf8), in: root)
        _ = try writeSidecar(makeSidecar(source: try makeSourceImage(for: source)), named: "A.JPG.ai.json", in: root)
        _ = try writeSource("notes.txt", data: Data("notes".utf8), in: root)
        _ = try writeSource("A.xmp", data: Data("xmp".utf8), in: root)
        _ = try writeSidecar(makeSidecar(source: try makeSourceImage(for: source)), named: ".Hidden.JPG.ai.json", in: root)
        _ = try writeSidecar(makeSidecar(source: try makeSourceImage(for: source)), named: "nested/B.JPG.ai.json", in: root)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: root.path,
            configuration: configuration(recursive: false)
        )

        XCTAssertEqual(batch.inputs.map(\.relativePath), ["A.JPG.ai.json"])
        XCTAssertTrue(batch.failures.isEmpty)
    }

    func testRecursiveMirroredTreeScanUsesSourceRoot() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let source = try writeSource("2026/06/Bird.JPG", data: Data("source".utf8), in: sourceRoot)
        let sourceImage = try makeSourceImage(for: source, relativePath: "2026/06/Bird.JPG")
        _ = try writeSidecar(makeSidecar(source: sourceImage), named: "2026/06/Bird.JPG.ai.json", in: jsonRoot)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: jsonRoot.path,
            configuration: configuration(recursive: true, sourceRoot: sourceRoot.path)
        )

        XCTAssertEqual(batch.inputs.map(\.relativePath), ["2026/06/Bird.JPG.ai.json"])
        XCTAssertEqual(batch.inputs.first?.sourcePath, source.standardizedFileURL)
        XCTAssertTrue(batch.failures.isEmpty)
    }

    func testSourceRootTakesPrecedenceOverRecordedPathAndSibling() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let preferredSource = try writeSource("Bird.JPG", data: Data("preferred".utf8), in: sourceRoot)
        let wrongRecordedSource = try writeSource("Wrong.JPG", data: Data("wrong".utf8), in: jsonRoot)
        _ = try writeSource("Bird.JPG", data: Data("sibling".utf8), in: jsonRoot)

        var sourceImage = try makeSourceImage(for: preferredSource, relativePath: "Bird.JPG")
        sourceImage.path = wrongRecordedSource.path
        let sidecar = try writeSidecar(makeSidecar(source: sourceImage), named: "Bird.JPG.ai.json", in: jsonRoot)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration(sourceRoot: sourceRoot.path)
        )

        XCTAssertEqual(batch.inputs.first?.sourcePath, preferredSource.standardizedFileURL)
        XCTAssertEqual(batch.inputs.first?.sourceIdentityStatus, .matched)
    }

    func testRecordedAbsolutePathFallbackWorks() throws {
        let jsonRoot = try temporaryDirectory()
        let sourceRoot = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: sourceRoot)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source, relativePath: "missing/Bird.JPG")),
            named: "Bird.JPG.ai.json",
            in: jsonRoot
        )

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration()
        )

        XCTAssertEqual(batch.inputs.first?.sourcePath, source.standardizedFileURL)
    }

    func testSiblingSourceFallbackWorks() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("source".utf8), in: root)
        var sourceImage = try makeSourceImage(for: source, relativePath: "missing/Bird.JPG")
        sourceImage.path = "/missing/Bird.JPG"
        let sidecar = try writeSidecar(makeSidecar(source: sourceImage), named: "Bird.JPG.ai.json", in: root)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration()
        )

        XCTAssertEqual(batch.inputs.first?.sourcePath, source.standardizedFileURL)
    }

    func testUnresolvedSourceFailsExceptSkipWithOutputDir() throws {
        let root = try temporaryDirectory()
        let sidecar = try writeSidecar(
            makeSidecar(source: makeMissingSourceImage(relativePath: "missing/Bird.JPG")),
            named: "Bird.JPG.ai.json",
            in: root
        )

        try assertSidecarError(code: .sourceMissing, stage: .scan) {
            _ = try RawJSONSidecarInputResolver().resolve(fromJSONPath: sidecar.path, configuration: configuration())
        }

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration(sourceVerification: .skip, outputDir: root.appendingPathComponent("out").path)
        )

        XCTAssertNil(batch.inputs.first?.sourcePath)
        XCTAssertEqual(batch.inputs.first?.sourceIdentityStatus, .skipped)
        XCTAssertTrue(batch.inputs.first?.warnings.isEmpty == true)
    }

    func testDefaultIdentityVerificationFailsStaleSource() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("original".utf8), in: root)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source)),
            named: "Bird.JPG.ai.json",
            in: root
        )
        try Data("changed".utf8).write(to: source)

        try assertSidecarError(code: .sourceIdentityMismatch, stage: .scan) {
            _ = try RawJSONSidecarInputResolver().resolve(fromJSONPath: sidecar.path, configuration: configuration())
        }
    }

    func testWarnPolicyReturnsWarningForStaleSource() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("original".utf8), in: root)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source)),
            named: "Bird.JPG.ai.json",
            in: root
        )
        try Data("changed".utf8).write(to: source)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration(sourceVerification: .warn)
        )

        XCTAssertEqual(batch.inputs.first?.sourceIdentityStatus, .mismatched)
        XCTAssertEqual(batch.inputs.first?.warnings.map(\.code), [.sourceIdentityMismatch])
    }

    func testSkipPolicyToleratesChangedSourceWithoutWarning() throws {
        let root = try temporaryDirectory()
        let source = try writeSource("Bird.JPG", data: Data("original".utf8), in: root)
        let sidecar = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: source)),
            named: "Bird.JPG.ai.json",
            in: root
        )
        try Data("changed".utf8).write(to: source)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: sidecar.path,
            configuration: configuration(sourceVerification: .skip)
        )

        XCTAssertEqual(batch.inputs.first?.sourceIdentityStatus, .skipped)
        XCTAssertTrue(batch.inputs.first?.warnings.isEmpty == true)
    }

    func testFolderBatchContinuesPastUnsupportedSchemaAndStaleHash() throws {
        let root = try temporaryDirectory()
        let goodSource = try writeSource("Good.JPG", data: Data("good".utf8), in: root)
        let staleSource = try writeSource("Stale.JPG", data: Data("stale".utf8), in: root)
        let unsupportedSource = try writeSource("Unsupported.JPG", data: Data("unsupported".utf8), in: root)

        _ = try writeSidecar(makeSidecar(source: try makeSourceImage(for: goodSource)), named: "Good.JPG.ai.json", in: root)
        _ = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: unsupportedSource), schemaVersion: "ai-sidecar-json/2.0"),
            named: "Unsupported.JPG.ai.json",
            in: root
        )
        _ = try writeSidecar(
            makeSidecar(source: try makeSourceImage(for: staleSource)),
            named: "Stale.JPG.ai.json",
            in: root
        )
        try Data("changed".utf8).write(to: staleSource)

        let batch = try RawJSONSidecarInputResolver().resolve(
            fromJSONPath: root.path,
            configuration: configuration()
        )

        XCTAssertEqual(batch.inputs.map(\.relativePath), ["Good.JPG.ai.json"])
        XCTAssertEqual(
            batch.failures.map(\.error.code).sorted { $0.rawValue < $1.rawValue },
            [.schemaUnsupported, .sourceIdentityMismatch].sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func configuration(
        recursive: Bool = false,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy = .fail,
        outputDir: String? = nil
    ) -> ResolvedXMPExportConfiguration {
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.recursive = recursive
        configuration.sourceRoot = sourceRoot
        configuration.sourceVerification = sourceVerification
        configuration.outputDir = outputDir
        return configuration
    }

    private func makeSidecar(
        source: SourceImage,
        schemaVersion: String = "ai-sidecar-json/1.2"
    ) -> RawJSONSidecar {
        RawJSONSidecar(
            schemaVersion: schemaVersion,
            source: source,
            runConfiguration: .builtInDefaults,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeSourceImage(for url: URL, relativePath: String? = nil) throws -> SourceImage {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = try XCTUnwrap(SupportedImageType(fileExtension: url.pathExtension))
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
        let modifiedAt = try XCTUnwrap(attributes[.modificationDate] as? Date)
        return SourceImage(
            path: url.standardizedFileURL.path,
            relativePath: relativePath ?? url.lastPathComponent,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: size,
            modifiedAt: modifiedAt,
            detectedType: type,
            identity: try SourceIdentityCalculator.compute(for: url, policy: .sha256)
        )
    }

    private func makeMissingSourceImage(relativePath: String) -> SourceImage {
        SourceImage(
            path: "/missing/\(relativePath)",
            relativePath: relativePath,
            fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
            fileExtension: "JPG",
            fileSize: 0,
            modifiedAt: Date(timeIntervalSince1970: 0),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "0", count: 64))
        )
    }

    private func writeSource(_ relativePath: String, data: Data, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
        return file.standardizedFileURL
    }

    private func writeSidecar(_ sidecar: RawJSONSidecar, named relativePath: String, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(sidecar).write(to: file)
        return file.standardizedFileURL
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.standardizedFileURL
    }

    private func assertSidecarError(
        code: SidecarErrorCode,
        stage: SidecarErrorStage,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            XCTFail("Expected \(code.rawValue)")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, code)
            XCTAssertEqual(error.stage, stage)
        }
    }
}
