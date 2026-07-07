import XCTest
@testable import AISidecarCore

/// CORE-9: settings write-through must never clobber what it doesn't know
/// (FR4-056, AC4-032 groundwork).
final class ConfigFileEditorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("config-editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func readObject(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
        )
    }

    func testMergeCreatesFileAndDirectoryWhenMissing() throws {
        let path = root.appendingPathComponent("nested/dir/config.json").path
        try ConfigFileEditor.merge(["mode": .string("subject")], atPath: path)
        XCTAssertEqual(try readObject(path)["mode"] as? String, "subject")
    }

    func testMergePreservesUnknownKeysAndRemovesNils() throws {
        let path = root.appendingPathComponent("config.json").path
        try Data(#"{"mode":"whole","hand_edited_key":{"keep":true},"gps_context":"exact"}"#.utf8)
            .write(to: URL(fileURLWithPath: path))

        try ConfigFileEditor.merge(
            ["mode": .string("both"), "gps_context": nil, "model": .string("gemma4:26b-a4b-it-qat")],
            atPath: path
        )

        let object = try readObject(path)
        XCTAssertEqual(object["mode"] as? String, "both")
        XCTAssertEqual(object["model"] as? String, "gemma4:26b-a4b-it-qat")
        XCTAssertNil(object["gps_context"], "nil removes the key")
        XCTAssertEqual((object["hand_edited_key"] as? [String: Any])?["keep"] as? Bool, true, "unknown keys survive")
    }

    func testMergedFileResolvesThroughTheConfigChain() throws {
        let path = root.appendingPathComponent("config.json").path
        try ConfigFileEditor.merge(
            ["mode": .string("subject"), "existing": .string("fail")],
            atPath: path
        )

        let resolved = try ConfigurationResolver.resolve(
            environment: [:],
            defaultConfigPath: path
        )
        XCTAssertEqual(resolved.mode, .subject)
        XCTAssertEqual(resolved.existing, .fail)
    }

    func testMergeRejectsNonObjectConfig() throws {
        let path = root.appendingPathComponent("config.json").path
        try Data("[1,2,3]".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try ConfigFileEditor.merge(["mode": .string("both")], atPath: path))
    }
}
