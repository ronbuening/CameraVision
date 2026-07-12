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

    func testAbsoluteFileListEntriesOutsideListDirectoryStayInSeparateGroups() throws {
        let root = try temporaryDirectory()
        let listDirectory = root.appendingPathComponent("lists")
        let firstDirectory = root.appendingPathComponent("first-shoot")
        let secondDirectory = root.appendingPathComponent("second-shoot")
        try FileManager.default.createDirectory(at: listDirectory, withIntermediateDirectories: true)
        let firstImage = try writeTestImage("IMG_0001.JPG", in: firstDirectory)
        let secondImage = try writeTestImage("IMG_0001.JPG", in: secondDirectory)
        let list = listDirectory.appendingPathComponent("images.txt")
        try "\(firstImage.path)\n\(secondImage.path)\n".write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(batch.sameBaseNameGroups.count, 2)
        XCTAssertEqual(Set(batch.sameBaseNameGroups.map(\.targetRelativePath)).count, 2)
        XCTAssertEqual(batch.sameBaseNameGroups.map(\.memberAssetIDs.count), [1, 1])

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.outputDir = root.appendingPathComponent("output").path
        let plans = try NormalizedXMPChangePlanner().plan(
            input: batch,
            decisions: [],
            candidateSkips: [],
            configuration: configuration
        )
        XCTAssertEqual(Set(plans.changePlan.targetPlans.map(\.targetXMPPath)).count, 2)
    }

    func testAbsoluteRawAndJPEGEntriesInSameExternalDirectoryStillPair() throws {
        let root = try temporaryDirectory()
        let listDirectory = root.appendingPathComponent("lists")
        let imageDirectory = root.appendingPathComponent("external-shoot")
        try FileManager.default.createDirectory(at: listDirectory, withIntermediateDirectories: true)
        let raw = try writeTestImage("Bird.NEF", in: imageDirectory)
        let jpeg = try writeTestImage("Bird.JPG", in: imageDirectory)
        let list = listDirectory.appendingPathComponent("images.txt")
        try "\(raw.path)\n\(jpeg.path)\n".write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(batch.sameBaseNameGroups.count, 1)
        XCTAssertEqual(batch.sameBaseNameGroups[0].memberAssetIDs.count, 2)
        XCTAssertEqual(batch.sameBaseNameGroups[0].selectedAssetIDs.count, 2)
        XCTAssertTrue(batch.sameBaseNameGroups[0].targetRelativePath.hasSuffix("/external-shoot/Bird.xmp"))
    }

    func testAbsoluteEntryDoesNotPairWithMirroredRelativePath() throws {
        let root = try temporaryDirectory()
        let listDirectory = root.appendingPathComponent("lists")
        let externalDirectory = try temporaryDirectory().appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: listDirectory, withIntermediateDirectories: true)
        let externalImage = try writeTestImage("Bird.JPG", in: externalDirectory)
        let mirroredRelativePath = externalImage.path.drop(while: { $0 == "/" })
            .replacingOccurrences(of: "Bird.JPG", with: "Bird.NEF")
        _ = try writeTestImage(mirroredRelativePath, in: listDirectory)
        let list = listDirectory.appendingPathComponent("images.txt")
        try "\(mirroredRelativePath)\n\(externalImage.path)\n"
            .write(to: list, atomically: true, encoding: .utf8)

        let batch = try NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )

        XCTAssertEqual(batch.sameBaseNameGroups.count, 2)
        XCTAssertEqual(Set(batch.sameBaseNameGroups.map(\.targetRelativePath)).count, 2)
        XCTAssertEqual(batch.sameBaseNameGroups.map(\.memberAssetIDs.count), [1, 1])

        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.outputDir = root.appendingPathComponent("mirrored-output").path
        let plans = try NormalizedXMPChangePlanner().plan(
            input: batch,
            decisions: [],
            candidateSkips: [],
            configuration: configuration
        )
        XCTAssertEqual(Set(plans.changePlan.targetPlans.map(\.targetXMPPath)).count, 2)
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
