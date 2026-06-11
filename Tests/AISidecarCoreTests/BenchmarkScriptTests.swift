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
        XCTAssertTrue(script.contains("\"swift\", \"run\", \"aisidecar\", \"benchmark\""))
        XCTAssertTrue(script.contains("CommandLine.arguments.dropFirst()"))
        XCTAssertTrue(script.contains("process.currentDirectoryURL = repoRoot"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
