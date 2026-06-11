import XCTest
@testable import AISidecarCore

final class RawJSONSidecarWriterTests: XCTestCase {
    func testAtomicWriteCreatesCompleteJSONAndParentDirectories() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF", path: root.appendingPathComponent("Bird.NEF").path)
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: .builtInDefaults,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destination = root.appendingPathComponent("nested/Bird.NEF.ai.json")

        let outcome = try RawJSONSidecarWriter().write(
            sidecar,
            to: destination.path,
            existingPolicy: .fail
        )

        XCTAssertEqual(outcome.status, .written)
        let data = try Data(contentsOf: destination)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RawJSONSidecar.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, "ai-sidecar-json/1.2")
        XCTAssertEqual(decoded.source.relativePath, "Bird.NEF")
        XCTAssertTrue(decoded.derivatives.isEmpty)
        XCTAssertTrue(decoded.modelRuns.isEmpty)
        XCTAssertTrue(decoded.errors.isEmpty)
    }

    func testExistingPoliciesSkipFailAndOverwrite() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Bird.NEF.ai.json")
        let writer = RawJSONSidecarWriter()
        let original = RawJSONSidecar(
            source: makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF"),
            runConfiguration: .builtInDefaults,
            errors: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let replacement = RawJSONSidecar(
            source: makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF"),
            runConfiguration: .builtInDefaults,
            errors: [
                SidecarError(
                    code: .writeFailed,
                    stage: .write,
                    message: "replacement",
                    recoverable: true
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        _ = try writer.write(original, to: destination.path, existingPolicy: .fail)
        let skip = try writer.write(replacement, to: destination.path, existingPolicy: .skip)
        XCTAssertEqual(skip.status, .skippedExisting)
        XCTAssertTrue(try decodedSidecar(at: destination).errors.isEmpty)

        XCTAssertThrowsError(try writer.write(replacement, to: destination.path, existingPolicy: .fail)) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .sidecarExists)
            XCTAssertEqual(sidecarError.stage, .write)
        }

        let overwrite = try writer.write(replacement, to: destination.path, existingPolicy: .overwrite)
        XCTAssertEqual(overwrite.status, .written)
        XCTAssertEqual(try decodedSidecar(at: destination).errors.first?.message, "replacement")
    }

    func testWriteFailureUsesStructuredWriteError() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let parentFile = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: parentFile)
        let sidecar = RawJSONSidecar(
            source: makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF"),
            runConfiguration: .builtInDefaults
        )

        XCTAssertThrowsError(
            try RawJSONSidecarWriter().write(
                sidecar,
                to: parentFile.appendingPathComponent("Bird.NEF.ai.json").path,
                existingPolicy: .fail
            )
        ) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .writeFailed)
            XCTAssertEqual(sidecarError.stage, .write)
            XCTAssertTrue(sidecarError.recoverable)
        }
    }

    private func decodedSidecar(at url: URL) throws -> RawJSONSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RawJSONSidecar.self, from: Data(contentsOf: url))
    }
}
