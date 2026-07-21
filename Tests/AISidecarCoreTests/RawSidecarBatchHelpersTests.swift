import Foundation
import XCTest

@testable import AISidecarCore

final class RawSidecarBatchHelpersTests: XCTestCase {
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
}
