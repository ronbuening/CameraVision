import Foundation
import XCTest
@testable import AISidecarCore

final class FileListInputResolverTests: XCTestCase {
    func testFileListResolvesRelativePathsCommentsDuplicatesAndUnsupportedEntries() throws {
        let root = try temporaryDirectory()
        _ = try writeTestImage("seq/IMG_0001.JPG", in: root)
        _ = try writeTestImage("seq/IMG_0002.JPG", in: root)
        try Data("not an image".utf8).write(to: root.appendingPathComponent("seq/readme.txt"))
        let list = root.appendingPathComponent("images.txt")
        try """
        # fixture list
        seq/IMG_0001.JPG

        seq/IMG_0001.JPG
        seq/readme.txt
        seq/missing.JPG
        seq/IMG_0002.JPG
        """.write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(batch.workflow, .fileList)
        XCTAssertEqual(batch.sourceAssets.map(\.sourceRelativePath), ["seq/IMG_0001.JPG", "seq/IMG_0002.JPG"])
        XCTAssertEqual(batch.sourceAssets.map(\.fileListIndex), [0, 3])
        XCTAssertEqual(batch.sourceAssets.map(\.affinityInputs.parsedSequenceNumber), [1, 2])
        XCTAssertEqual(batch.warnings.count, 1)
        XCTAssertTrue(batch.warnings[0].message.contains("Duplicate file-list entry ignored"))
        XCTAssertEqual(batch.failures.map(\.error.code), [.unsupportedFormat, .sourceMissing])
        XCTAssertEqual(batch.sameBaseNameGroups.map(\.targetRelativePath), ["seq/IMG_0001.xmp", "seq/IMG_0002.xmp"])
    }

    func testFileListCollapsesSameBaseNameGroupsWithoutDoubleVoting() throws {
        let root = try temporaryDirectory()
        _ = try writeTestImage("Bird.JPG", in: root)
        _ = try writeTestImage("Bird.jpeg", in: root)
        let list = root.appendingPathComponent("images.txt")
        try "Bird.JPG\nBird.jpeg\n".write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(batch.sourceAssets.count, 2)
        XCTAssertEqual(batch.sameBaseNameGroups.count, 1)
        XCTAssertEqual(Set(batch.sameBaseNameGroups[0].memberAssetIDs), Set(["asset-000001", "asset-000002"]))
        XCTAssertEqual(Set(batch.sameBaseNameGroups[0].selectedAssetIDs), Set(["asset-000001", "asset-000002"]))
        XCTAssertEqual(
            Set(batch.sourceAssets.map(\.affinityInputs.sameBaseNameGroupID)),
            Set(["group-000001"])
        )
    }

    func testFileListPersistsGPSPresenceWithoutCoordinates() throws {
        let root = try temporaryDirectory()
        _ = try writeTestImage("GPSBird.JPG", gps: (latitude: 40.7128, longitude: -74.0060), in: root)
        let list = root.appendingPathComponent("images.txt")
        try "GPSBird.JPG\n".write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        let inputs = try XCTUnwrap(batch.sourceAssets.first?.affinityInputs)
        XCTAssertEqual(inputs.gpsStatus, .present)
        XCTAssertNil(inputs.cameraSerialHash)
        XCTAssertNil(inputs.cameraIdentityClass)
        XCTAssertNil(inputs.lensIdentityClass)
    }
}
