import Foundation
import XCTest
@testable import AISidecarCore

final class BenchmarkRunnerTests: XCTestCase {
    func testSelfTestWritesResultDocumentsAndCleansScratchArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aisidecar-benchmark-runner-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let result = try Milestone9BenchmarkRunner().run(options: BenchmarkOptions(
            outputDir: root.path,
            selfTest: true
        ))

        XCTAssertTrue(result.selfTest)
        XCTAssertTrue(result.outputRootPath.hasPrefix(root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.jsonPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.markdownPath))

        let document = try JSONDecoder().decode(
            BenchmarkDocument.self,
            from: Data(contentsOf: URL(fileURLWithPath: result.jsonPath))
        )
        XCTAssertEqual(document.schemaVersion, "aisidecar-benchmark-results/1.0")
        XCTAssertEqual(document.runs.first?.name, "self-test")
        XCTAssertEqual(document.runs.first?.metrics.sidecarCount, 1)
        XCTAssertEqual(document.runs.first?.metrics.validModelRunCount, 1)
        XCTAssertEqual(document.runs.first?.metrics.totalOllamaLoadDurationNs, 1_000)

        let outputRoot = URL(fileURLWithPath: result.outputRootPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("input-samples").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("hash-input-3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("iter-1-test/cache").path))
    }
}
