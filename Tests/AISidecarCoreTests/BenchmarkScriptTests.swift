import Foundation
import XCTest

final class BenchmarkScriptTests: XCTestCase {
    func testBenchmarkManifestAndSelfTestScriptArePresent() throws {
        let root = packageRoot()
        let manifestURL = root.appendingPathComponent("benchmarks/samples/manifest.json")
        let scriptURL = root.appendingPathComponent("benchmarks/run-milestone9a.swift")

        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        XCTAssertEqual(manifest?["schema_version"] as? String, "aisidecar-benchmark-samples/1.0")
        XCTAssertNotNil(manifest?["samples"] as? [Any])

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("--self-test"))
        XCTAssertTrue(script.contains("--spec"))
        XCTAssertTrue(script.contains("aggregateSidecars"))
        XCTAssertTrue(script.contains("\"clear_derivative_cache_after_success\": true"))
        XCTAssertTrue(script.contains("cleanupScratchInputs"))
        XCTAssertTrue(script.contains("removeIfExists(cacheDir)"))
        XCTAssertTrue(script.contains("yyyy-MM-dd-HHmmss"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
