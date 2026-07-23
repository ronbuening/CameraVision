import XCTest

@testable import AISidecarCore

final class AssetAffinityInputTests: XCTestCase {
    func testBuilderPersistsFilenameListAndPrivacySafeIdentitySignals() {
        let asset = phase3Asset(
            index: 12,
            relativePath: "2026/06/IMG_0042.JPG",
            fileListIndex: 5,
            camera: "nikon z8",
            lens: "nikkor 500pf"
        )
        let inputs = asset.affinityInputs

        XCTAssertEqual(inputs.assetID, "asset-000012")
        XCTAssertEqual(inputs.sourceIdentityHash, asset.sourceIdentity.sha256)
        XCTAssertEqual(inputs.relativeDirectory, "2026/06")
        XCTAssertEqual(inputs.fileName, "IMG_0042.JPG")
        XCTAssertEqual(inputs.filenameStem, "IMG_0042")
        XCTAssertEqual(inputs.parsedSequenceNumber, 42)
        XCTAssertEqual(inputs.fileListIndex, 5)
        XCTAssertEqual(inputs.captureTimeStatus, .missing)
        XCTAssertEqual(inputs.gpsStatus, .missing)
        XCTAssertEqual(inputs.cameraIdentityClass, "nikon z8")
        XCTAssertEqual(inputs.lensIdentityClass, "nikkor 500pf")
    }

    func testGPSPresenceIsRecordedWithoutPersistingCoordinates() async throws {
        let root = try temporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        _ = try writeTestImage("GPSBird.JPG", gps: (latitude: 40.7128, longitude: -74.0060), in: root)
        let list = root.appendingPathComponent("images.txt")
        try "GPSBird.JPG\n".write(to: list, atomically: true, encoding: .utf8)

        let batch = try await NormalizationInputResolver().resolve(
            mode: .fileList(path: list.path),
            configuration: .builtInDefaults
        )
        let inputs = try XCTUnwrap(batch.sourceAssets.first?.affinityInputs)
        let encoded = String(decoding: try JSONEncoder().encode(inputs), as: UTF8.self)

        XCTAssertEqual(inputs.gpsStatus, .present)
        XCTAssertTrue(encoded.contains(#""gps_status":"present""#))
        XCTAssertFalse(encoded.contains("40.7128"))
        XCTAssertFalse(encoded.contains("-74.006"))
    }

    func testCameraSerialHashIsStableAndDoesNotExposeRawSerial() {
        let rawSerial = "camera-serial-12345"
        let hash = AssetAffinityInputBuilder.stableSessionHash(rawSerial)

        XCTAssertEqual(hash.count, 64)
        XCTAssertNotEqual(hash, rawSerial)
        XCTAssertFalse(hash.contains(rawSerial))
        XCTAssertEqual(hash, AssetAffinityInputBuilder.stableSessionHash(rawSerial))
    }
}
