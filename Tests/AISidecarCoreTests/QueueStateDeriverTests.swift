import Foundation
import XCTest

@testable import AISidecarCore

final class QueueStateDeriverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("queue-state-deriver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFiveStateTruthTable() throws {
        let discovered = try makeEntry("discovered/Bird.NEF")
        XCTAssertEqual(derive(discovered), .discovered)

        let analyzed = try makeEntry("analyzed/Bird.NEF")
        try write("analyzed/Bird.NEF.ai.json", #"{"schema_version":"1"}"#)
        XCTAssertEqual(derive(analyzed), .analyzed)

        let external = try makeEntry("external/Bird.NEF")
        try write("external/Bird.xmp")
        XCTAssertEqual(derive(external), .xmpPresentExternal)

        let externalWithRawSidecar = try makeEntry("external-with-sidecar/Bird.NEF")
        try write("external-with-sidecar/Bird.NEF.ai.json", #"{"schema_version":"1"}"#)
        try write("external-with-sidecar/Bird.xmp")
        XCTAssertEqual(derive(externalWithRawSidecar), .xmpPresentExternal)

        let exported = try makeEntry("exported/Bird.NEF")
        try write("exported/Bird.NEF.ai.json", #"{"xmp_export":{"target":"Bird.xmp"}}"#)
        try write("exported/Bird.xmp")
        XCTAssertEqual(derive(exported), .exported)

        let missingExport = try makeEntry("missing-export/Bird.NEF")
        try write("missing-export/Bird.NEF.ai.json", #"{"xmp_export":{"target":"Bird.xmp"}}"#)
        XCTAssertEqual(derive(missingExport), .xmpMissingWasExported)
    }

    func testTopLevelExportProbeTreatsEveryNonNullValueAsPresent() throws {
        let values = [
            #"{"target":"Bird.xmp"}"#,
            #"["Bird.xmp"]"#,
            #""recorded""#,
            "17",
            "true",
        ]
        let deriver = QueueStateDeriver()

        for (index, value) in values.enumerated() {
            let path = try write("probe/present-\(index).ai.json", "{\"xmp_export\":\(value)}")
            XCTAssertTrue(deriver.hasXMPExportBlock(atPath: path.path), "value: \(value)")
        }
    }

    func testTopLevelExportProbeRejectsNullMissingMalformedAndNestedText() throws {
        let absentDocuments = [
            #"{"xmp_export":null}"#,
            #"{"schema_version":"1"}"#,
            "not json",
            #"{"other":{"xmp_export":{"target":"Bird.xmp"}}}"#,
            #"{"raw_response_text":"{\"xmp_export\":{\"target\":\"Bird.xmp\"}}"}"#,
        ]
        let deriver = QueueStateDeriver()

        for (index, document) in absentDocuments.enumerated() {
            let path = try write("probe/absent-\(index).ai.json", document)
            XCTAssertFalse(deriver.hasXMPExportBlock(atPath: path.path), "document: \(document)")
        }
        XCTAssertFalse(deriver.hasXMPExportBlock(atPath: root.appendingPathComponent("missing.ai.json").path))
    }

    func testMirroredOutputUsesNestedCanonicalArtifactPaths() throws {
        let entry = try makeEntry("photos/2026/07/Bird.NEF", relativePath: "2026/07/Bird.NEF")
        let output = root.appendingPathComponent("output", isDirectory: true)
        try write("output/2026/07/Bird.NEF.ai.json", #"{"xmp_export":true}"#)
        try write("output/2026/07/Bird.xmp")

        XCTAssertEqual(
            SidecarNaming.destinationPath(for: entry, outputDir: output.path),
            output.appendingPathComponent("2026/07/Bird.NEF.ai.json").path
        )
        XCTAssertEqual(
            XMPNaming.destinationPath(for: entry, outputDir: output.path, fileManager: .default),
            output.appendingPathComponent("2026/07/Bird.xmp").path
        )
        XCTAssertEqual(QueueStateDeriver().derive(for: entry, outputDir: output.path), .exported)
    }

    func testRawAndJPEGPairShareXMPButKeepDistinctRawSidecars() throws {
        let raw = try makeEntry("pairs/Bird.NEF")
        let jpeg = try makeEntry("pairs/Bird.JPG", detectedType: .jpg)

        XCTAssertNotEqual(
            SidecarNaming.destinationPath(for: raw, outputDir: nil),
            SidecarNaming.destinationPath(for: jpeg, outputDir: nil)
        )
        XCTAssertEqual(
            XMPNaming.destinationPath(for: raw, outputDir: nil, fileManager: .default),
            XMPNaming.destinationPath(for: jpeg, outputDir: nil, fileManager: .default)
        )
    }

    func testDerivedStateIsSendableAndEquatable() {
        func requireSendable<T: Sendable>(_: T) {}

        let state = QueueDerivedState.analyzed
        requireSendable(state)
        XCTAssertEqual(state, .analyzed)
        XCTAssertNotEqual(state, .discovered)
    }

    private func derive(_ entry: ScanInventoryEntry) -> QueueDerivedState {
        QueueStateDeriver().derive(for: entry, outputDir: nil)
    }

    @discardableResult
    private func write(_ relativePath: String, _ contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(contents.data(using: .utf8)).write(to: url)
        return url
    }

    private func makeEntry(
        _ path: String,
        relativePath: String? = nil,
        detectedType: SupportedImageType = .nef
    ) throws -> ScanInventoryEntry {
        let url = try write(path)
        return ScanInventoryEntry(
            path: url.path,
            relativePath: relativePath ?? path,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: detectedType
        )
    }
}
