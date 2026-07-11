import Darwin
import XCTest
@testable import AISidecarCore

final class ScannerTests: XCTestCase {
    func testSupportedImageTypeMatchesExtensionsCaseInsensitively() {
        let supported = [
            "NEF", "NRW", "CR3", "CR2", "ARW", "RAF", "ORF", "RW2",
            "DNG", "JPG", "JPEG", "TIF", "TIFF", "HEIC", "PNG"
        ]

        for fileExtension in supported {
            XCTAssertNotNil(SupportedImageType(fileExtension: fileExtension))
            XCTAssertNotNil(SupportedImageType(fileExtension: fileExtension.lowercased()))
        }

        XCTAssertNil(SupportedImageType(fileExtension: "txt"))
    }

    func testSingleFileInputRecordsSourceMetadataAndRelativePath() throws {
        let root = try temporaryDirectory()
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let file = try writeFile("Bird.NEF", data: Data("raw-data".utf8), in: root)
        try setModifiedAt(modifiedAt, for: file)

        let result = try ImageScanner().scan(inputPath: file.path, recursive: false, identityPolicy: .sha256)

        XCTAssertEqual(result.schemaVersion, "ai-sidecar-scan/1.0")
        XCTAssertEqual(result.inputPath, file.standardizedFileURL.path)
        XCTAssertEqual(result.scanRoot, root.standardizedFileURL.path)
        XCTAssertFalse(result.recursive)
        XCTAssertEqual(result.identityPolicy, .sha256)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.images.count, 1)

        let image = try XCTUnwrap(result.images.first)
        XCTAssertEqual(image.path, file.standardizedFileURL.path)
        XCTAssertEqual(image.relativePath, "Bird.NEF")
        XCTAssertEqual(image.fileName, "Bird.NEF")
        XCTAssertEqual(image.fileExtension, "NEF")
        XCTAssertEqual(image.fileSize, 8)
        XCTAssertEqual(image.modifiedAt.timeIntervalSince1970, modifiedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(image.detectedType, .nef)
        XCTAssertEqual(image.identity.policy, .sha256)
        XCTAssertEqual(image.identity.sha256.count, 64)
    }

    func testFolderScanRecordsSymbolicLinkAsRecoverableError() throws {
        let root = try temporaryDirectory()
        let target = try writeFile("Bird.NEF", data: Data("raw-data".utf8), in: root)
        let link = root.appendingPathComponent("Linked.NEF")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = try ImageScanner().scan(inputPath: root.path, recursive: false, identityPolicy: .fast)

        XCTAssertEqual(result.images.map(\.relativePath), ["Bird.NEF"])
        let error = try XCTUnwrap(result.errors.first)
        XCTAssertEqual(error.path, link.path)
        XCTAssertEqual(error.relativePath, "Linked.NEF")
        XCTAssertEqual(error.error.code, .validationFailed)
        XCTAssertEqual(error.error.stage, .scan)
        XCTAssertTrue(error.error.recoverable)
        XCTAssertTrue(error.error.message.contains("Symbolic link skipped"))
    }

    func testDirectSymbolicLinkResolvesAndUsesTargetIdentity() throws {
        let root = try temporaryDirectory()
        let target = try writeFile("Bird.NEF", data: Data("raw-data".utf8), in: root)
        let link = root.appendingPathComponent("Linked.NEF")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let targetResult = try ImageScanner().scan(inputPath: target.path, recursive: false, identityPolicy: .fast)
        let linkResult = try ImageScanner().scan(inputPath: link.path, recursive: false, identityPolicy: .fast)

        XCTAssertEqual(linkResult.inputPath, target.path)
        XCTAssertEqual(linkResult.images.first?.path, target.path)
        XCTAssertEqual(linkResult.images.first?.identity, targetResult.images.first?.identity)
        XCTAssertTrue(linkResult.errors.isEmpty)
    }

    func testNonRecursiveFolderScanFiltersImagesAndReportsUnsupportedVisibleFiles() throws {
        let root = try temporaryDirectory()
        _ = try writeFile("B.JPG", data: Data("b".utf8), in: root)
        _ = try writeFile("A.NEF", data: Data("a".utf8), in: root)
        _ = try writeFile("sub/C.NEF", data: Data("c".utf8), in: root)
        _ = try writeFile("notes.txt", data: Data("notes".utf8), in: root)
        _ = try writeFile(".hidden.NEF", data: Data("hidden".utf8), in: root)
        _ = try writeFile("._A.NEF", data: Data("fork".utf8), in: root)
        _ = try writeFile(".DS_Store", data: Data("store".utf8), in: root)
        _ = try writeFile("A.NEF.ai.json", data: Data("{}".utf8), in: root)
        _ = try writeFile("A.xmp", data: Data("xmp".utf8), in: root)

        let result = try ImageScanner().scan(inputPath: root.path, recursive: false, identityPolicy: .sha256)

        XCTAssertEqual(result.images.map(\.relativePath), ["A.NEF", "B.JPG"])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.relativePath, "notes.txt")
        XCTAssertEqual(result.errors.first?.error.code, .unsupportedFormat)
        XCTAssertEqual(result.errors.first?.error.stage, .scan)
        XCTAssertTrue(result.errors.first?.error.recoverable == true)
    }

    func testRecursiveFolderScanKeepsRelativePathsAndDuplicateBasenamesDistinct() throws {
        let root = try temporaryDirectory()
        _ = try writeFile("2026/06/_DSC1234.NEF", data: Data("nef".utf8), in: root)
        _ = try writeFile("2026/07/_DSC1234.JPG", data: Data("jpg".utf8), in: root)
        _ = try writeFile("2026/07/readme.md", data: Data("readme".utf8), in: root)
        _ = try writeFile(".hidden/Hidden.NEF", data: Data("hidden".utf8), in: root)
        _ = try writeFile("visible/.hidden-file.NEF", data: Data("hidden".utf8), in: root)
        _ = try writeFile("visible/.hidden-dir/File.NEF", data: Data("hidden".utf8), in: root)

        let result = try ImageScanner().scan(inputPath: root.path, recursive: true, identityPolicy: .sha256)

        XCTAssertEqual(
            result.images.map(\.relativePath),
            ["2026/06/_DSC1234.NEF", "2026/07/_DSC1234.JPG"]
        )
        XCTAssertEqual(result.images.map(\.fileName), ["_DSC1234.NEF", "_DSC1234.JPG"])
        XCTAssertEqual(result.errors.map(\.relativePath), ["2026/07/readme.md"])
    }

    func testRecursiveScanRecordsUnreadableSubdirectoryAndContinues() throws {
        try XCTSkipIf(getuid() == 0, "chmod 000 is not enforced for root")
        let root = try temporaryDirectory()
        _ = try writeFile("Top.NEF", data: Data("top".utf8), in: root)
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        _ = try writeFile("locked/Hidden.NEF", data: Data("hidden".utf8), in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }

        let result = try ImageScanner().scan(inputPath: root.path, recursive: true, identityPolicy: .fast)

        XCTAssertEqual(result.images.map(\.relativePath), ["Top.NEF"])
        let failure = try XCTUnwrap(result.errors.first { $0.path == locked.standardizedFileURL.path })
        XCTAssertEqual(failure.relativePath, "locked")
        XCTAssertEqual(failure.error.code, .validationFailed)
        XCTAssertEqual(failure.error.stage, .scan)
        XCTAssertTrue(failure.error.recoverable)
    }

    func testScanIgnoresOwnedRunArtifactsWithoutExpandingCleanupScope() throws {
        let root = try temporaryDirectory()
        _ = try writeFile("Bird.NEF", data: Data("raw".utf8), in: root)
        let artifactNames = [
            "batch-progress-2026-07-10T120000Z.jsonl",
            "batch-summary-2026-07-10T120000Z.json",
            "xmp-export-progress-2026-07-10T120000Z.jsonl",
            "xmp-export-report-2026-07-10T120000Z.json",
            "xmp-export-summary-2026-07-10T120000Z.md",
            "normalization-progress-2026-07-10T120000Z.jsonl",
            "normalization-report-2026-07-10T120000Z.json",
            "normalization-summary-2026-07-10T120000Z.md",
            "normalization-session-2026-07-10T120000Z.json",
            "normalization-apply-progress-2026-07-10T120000Z.jsonl",
            "normalization-apply-report-2026-07-10T120000Z.json",
            "normalization-apply-summary-2026-07-10T120000Z.md",
            "model-input-export-2026-07-10T120000Z.json",
            "Bird.xmp.bak-2026-07-10T12:00:00Z",
            "Bird.XMP.bak-2026-07-10T120000Z-a3f2"
        ]
        for name in artifactNames {
            _ = try writeFile(name, data: Data("{}".utf8), in: root)
        }

        let result = try ImageScanner().scan(inputPath: root.path, recursive: false, identityPolicy: .fast)

        XCTAssertEqual(result.images.map(\.relativePath), ["Bird.NEF"])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertNil(ArtifactCleanup.classify(fileName: "normalization-session-2026-07-10T120000Z.json"))
        XCTAssertNil(ArtifactCleanup.classify(fileName: "model-input-export-2026-07-10T120000Z.json"))
        XCTAssertNil(ArtifactCleanup.classify(fileName: "Bird.xmp.bak-2026-07-10T120000Z-a3f2"))
    }

    func testNonRecursiveUnreadableFolderThrowsStructuredValidationError() throws {
        try XCTSkipIf(getuid() == 0, "chmod 000 is not enforced for root")
        let root = try temporaryDirectory()
        _ = try writeFile("Hidden.NEF", data: Data("hidden".utf8), in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        }

        XCTAssertThrowsError(
            try ImageScanner().scan(inputPath: root.path, recursive: false, identityPolicy: .fast)
        ) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .validationFailed)
            XCTAssertEqual(sidecarError.stage, .scan)
            XCTAssertFalse(sidecarError.recoverable)
            XCTAssertTrue(sidecarError.message.contains("Unable to read input folder"))
        }
    }

    func testUnsupportedSingleFileProducesRecoverableScanError() throws {
        let root = try temporaryDirectory()
        let file = try writeFile("notes.txt", data: Data("notes".utf8), in: root)

        let result = try ImageScanner().scan(inputPath: file.path, recursive: false, identityPolicy: .sha256)

        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.path, file.standardizedFileURL.path)
        XCTAssertEqual(result.errors.first?.relativePath, "notes.txt")
        XCTAssertEqual(result.errors.first?.error.code, .unsupportedFormat)
        XCTAssertTrue(result.errors.first?.error.recoverable == true)
    }

    func testIgnoredSingleFileInputsProduceEmptyScanWithoutErrors() throws {
        let root = try temporaryDirectory()
        let sidecar = try writeFile("Bird.NEF.ai.json", data: Data("{}".utf8), in: root)
        let hidden = try writeFile(".hidden.NEF", data: Data("hidden".utf8), in: root)

        let sidecarResult = try ImageScanner().scan(inputPath: sidecar.path, recursive: false, identityPolicy: .sha256)
        let hiddenResult = try ImageScanner().scan(inputPath: hidden.path, recursive: false, identityPolicy: .sha256)

        XCTAssertTrue(sidecarResult.images.isEmpty)
        XCTAssertTrue(sidecarResult.errors.isEmpty)
        XCTAssertTrue(hiddenResult.images.isEmpty)
        XCTAssertTrue(hiddenResult.errors.isEmpty)
    }

    func testMissingInputFailsAsValidationError() throws {
        let root = try temporaryDirectory()
        let missing = root.appendingPathComponent("missing.NEF")

        XCTAssertThrowsError(
            try ImageScanner().scan(inputPath: missing.path, recursive: false, identityPolicy: .sha256)
        ) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .validationFailed)
            XCTAssertEqual(sidecarError.stage, .scan)
            XCTAssertFalse(sidecarError.recoverable)
        }
    }

    private func writeFile(_ relativePath: String, data: Data, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
        return file
    }

    private func setModifiedAt(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
