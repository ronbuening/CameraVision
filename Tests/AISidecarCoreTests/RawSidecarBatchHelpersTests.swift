import Foundation
import XCTest

@testable import AISidecarCore

final class RawSidecarBatchHelpersTests: XCTestCase {
    func testRawInputBatchUsesWrittenDocumentsInMemoryAndReadsSkippedSidecars() throws {
        let writtenPath = "/output/Fresh.jpg.ai.json"
        let skippedPath = "/output/Existing.jpg.ai.json"
        let writtenDocument = try sidecarDocument(sourceName: "Fresh.jpg")
        let skippedDocument = try sidecarDocument(sourceName: "Existing.jpg")
        let result = AnalyzeResult(
            scanResult: ScanResult(
                inputPath: "/input",
                scanRoot: "/input",
                recursive: false,
                identityPolicy: .sha256,
                images: [writtenDocument.sidecar.source, skippedDocument.sidecar.source],
                errors: []
            ),
            records: [
                ProgressRecord(
                    sourcePath: writtenDocument.sidecar.source.path,
                    relativePath: writtenDocument.sidecar.source.relativePath,
                    sidecarPath: writtenPath,
                    status: .written,
                    durationMs: 1
                ),
                ProgressRecord(
                    sourcePath: skippedDocument.sidecar.source.path,
                    relativePath: skippedDocument.sidecar.source.relativePath,
                    sidecarPath: skippedPath,
                    status: .skippedExisting,
                    durationMs: 1
                ),
            ],
            progressLogPath: nil,
            summaryPath: nil,
            summary: nil,
            interrupted: false,
            writtenSidecarsByPath: [writtenPath: writtenDocument]
        )
        var readPaths: [String] = []

        let batch = RawSidecarBatchHelpers.rawInputBatch(
            from: result,
            failureContext: "XMP export",
            fileManager: .default,
            readDocument: { url in
                readPaths.append(url.path)
                return skippedDocument
            }
        )

        XCTAssertEqual(readPaths, [skippedPath])
        XCTAssertEqual(batch.failures, [])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: batch.inputs.map { ($0.document.sidecar.source.fileName, $0.document) }),
            ["Fresh.jpg": writtenDocument, "Existing.jpg": skippedDocument]
        )
    }

    func testRawInputBatchFallsBackToDiskForWrittenEntriesMissingFromHandoff() throws {
        let handedOffPath = "/output/Fresh.jpg.ai.json"
        let missingPath = "/output/Missing.jpg.ai.json"
        let handedOffDocument = try sidecarDocument(sourceName: "Fresh.jpg")
        let missingDocument = try sidecarDocument(sourceName: "Missing.jpg")
        let result = AnalyzeResult(
            scanResult: ScanResult(
                inputPath: "/input",
                scanRoot: "/input",
                recursive: false,
                identityPolicy: .sha256,
                images: [handedOffDocument.sidecar.source, missingDocument.sidecar.source],
                errors: []
            ),
            records: [
                ProgressRecord(
                    sourcePath: handedOffDocument.sidecar.source.path,
                    relativePath: handedOffDocument.sidecar.source.relativePath,
                    sidecarPath: handedOffPath,
                    status: .written,
                    durationMs: 1
                ),
                ProgressRecord(
                    sourcePath: missingDocument.sidecar.source.path,
                    relativePath: missingDocument.sidecar.source.relativePath,
                    sidecarPath: missingPath,
                    status: .written,
                    durationMs: 1
                ),
            ],
            progressLogPath: nil,
            summaryPath: nil,
            summary: nil,
            interrupted: false,
            writtenSidecarsByPath: [handedOffPath: handedOffDocument]
        )
        var readPaths: [String] = []

        let batch = RawSidecarBatchHelpers.rawInputBatch(
            from: result,
            failureContext: "XMP export",
            fileManager: .default,
            readDocument: { url in
                readPaths.append(url.path)
                return missingDocument
            }
        )

        XCTAssertEqual(readPaths, [missingPath])
        XCTAssertEqual(batch.failures, [])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: batch.inputs.map { ($0.document.sidecar.source.fileName, $0.document) }),
            ["Fresh.jpg": handedOffDocument, "Missing.jpg": missingDocument]
        )
    }

    func testRawInputBatchPreservesAdapterSpecificFailureMessages() {
        let result = AnalyzeResult(
            scanResult: ScanResult(
                inputPath: "/input",
                scanRoot: "/",
                recursive: false,
                identityPolicy: .sha256,
                images: [],
                errors: []
            ),
            records: [
                ProgressRecord(
                    sourcePath: "/input/Bird.jpg",
                    relativePath: "Bird.jpg",
                    sidecarPath: nil,
                    status: .failed,
                    durationMs: 1
                )
            ],
            progressLogPath: nil,
            summaryPath: nil,
            summary: nil,
            interrupted: false
        )

        let xmpBatch = RawSidecarBatchHelpers.rawInputBatch(
            from: result,
            failureContext: "XMP export",
            fileManager: .default
        )
        let normalizationBatch = RawSidecarBatchHelpers.rawInputBatch(
            from: result,
            failureContext: "normalization",
            fileManager: .default
        )

        XCTAssertEqual(
            xmpBatch.failures.first?.error.message,
            "Analyze did not produce a successful raw sidecar for XMP export."
        )
        XCTAssertEqual(
            normalizationBatch.failures.first?.error.message,
            "Analyze did not produce a successful raw sidecar for normalization."
        )
    }

    private func sidecarDocument(sourceName: String) throws -> RawJSONSidecarDocument {
        let source = SourceImage(
            path: "/input/\(sourceName)",
            relativePath: sourceName,
            fileName: sourceName,
            fileExtension: "jpg",
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
        return try RawJSONSidecarDocument(
            sidecar: RawJSONSidecar(
                source: source,
                runConfiguration: .builtInDefaults,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        )
    }
}
