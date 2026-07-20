import XCTest

@testable import CupricAspectApp

/// M1: the file→state derivation table from the plan, exercised against real
/// temp-dir layouts (AC4-028 read side). No database, no network, no images.
final class AssetQueueDerivationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("queue-derivation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ contents: String = "x") throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.data(using: .utf8)!.write(to: url)
        return url.path
    }

    private func derive(_ sourceRelative: String, outputDir: String? = nil) -> AssetRecord.StateKind {
        AssetQueueDerivation.deriveState(
            sourcePath: root.appendingPathComponent(sourceRelative).path,
            relativePath: sourceRelative,
            outputDir: outputDir
        )
    }

    func testImageOnlyIsDiscovered() throws {
        _ = try write("a.nef")
        XCTAssertEqual(derive("a.nef"), .discovered)
    }

    func testImageWithRawSidecarIsAnalyzed() throws {
        _ = try write("a.nef")
        _ = try write("a.nef.ai.json", #"{"schema_version":"1"}"#)
        XCTAssertEqual(derive("a.nef"), .analyzed)
    }

    func testPreexistingXMPWithoutExportBlockIsExternal() throws {
        _ = try write("a.nef")
        _ = try write("a.xmp")
        XCTAssertEqual(derive("a.nef"), .xmpPresentExternal, "AC4-028: never 'exported' without the block")

        _ = try write("a.nef.ai.json", #"{"schema_version":"1"}"#)
        XCTAssertEqual(derive("a.nef"), .xmpPresentExternal)
    }

    func testExportBlockPlusXMPIsExported() throws {
        _ = try write("a.nef")
        _ = try write("a.nef.ai.json", #"{"schema_version":"1","xmp_export":{"target":"a.xmp"}}"#)
        _ = try write("a.xmp")
        XCTAssertEqual(derive("a.nef"), .exported)
    }

    func testExportBlockWithMissingXMPIsWasExported() throws {
        _ = try write("a.nef")
        _ = try write("a.nef.ai.json", #"{"schema_version":"1","xmp_export":{"target":"a.xmp"}}"#)
        XCTAssertEqual(derive("a.nef"), .xmpMissingWasExported)
    }

    func testHasXMPExportBlockViaPartialDecode() throws {
        let withBlock = try write("with.ai.json", #"{"schema_version":"1","xmp_export":{"target":"a.xmp"}}"#)
        let withoutBlock = try write("without.ai.json", #"{"schema_version":"1"}"#)
        let malformed = try write("malformed.ai.json", "not json")

        XCTAssertTrue(AssetQueueDerivation.hasXMPExportBlock(rawSidecarPath: withBlock))
        XCTAssertFalse(AssetQueueDerivation.hasXMPExportBlock(rawSidecarPath: withoutBlock))
        XCTAssertFalse(AssetQueueDerivation.hasXMPExportBlock(rawSidecarPath: malformed))
    }

    func testHasXMPExportBlockIgnoresKeyNestedInStrings() throws {
        let sidecar = try write(
            "nested.ai.json",
            #"{"schema_version":"1","raw_response_text":"{\"xmp_export\":{\"target\":\"a.xmp\"}}"}"#
        )

        XCTAssertFalse(AssetQueueDerivation.hasXMPExportBlock(rawSidecarPath: sidecar))
    }

    func testOutputDirMirrorsCoreNaming() throws {
        let out = root.appendingPathComponent("staging").path
        _ = try write("sub/a.nef")
        _ = try write("staging/sub/a.nef.ai.json", #"{"schema_version":"1"}"#)
        XCTAssertEqual(derive("sub/a.nef", outputDir: out), .analyzed)

        XCTAssertEqual(
            AssetQueueDerivation.rawSidecarPath(
                sourcePath: "/x/sub/a.nef", relativePath: "sub/a.nef", outputDir: "/out"),
            "/out/sub/a.nef.ai.json"
        )
        XCTAssertEqual(
            AssetQueueDerivation.xmpTargetPath(sourcePath: "/x/sub/a.nef", relativePath: "sub/a.nef", outputDir: nil),
            "/x/sub/a.xmp"
        )
        XCTAssertEqual(
            AssetQueueDerivation.xmpTargetPath(
                sourcePath: "/x/sub/a.nef", relativePath: "sub/a.nef", outputDir: "/out"),
            "/out/sub/a.xmp"
        )
    }

    func testSameBaseNamePairSharesOneXMPTarget() {
        let raw = AssetQueueDerivation.xmpTargetPath(sourcePath: "/x/a.nef", relativePath: "a.nef", outputDir: nil)
        let jpeg = AssetQueueDerivation.xmpTargetPath(sourcePath: "/x/a.jpg", relativePath: "a.jpg", outputDir: nil)
        XCTAssertEqual(raw, jpeg, "RAW+JPEG pairs collapse onto one XMP target (Phase 2 naming)")
    }
}
