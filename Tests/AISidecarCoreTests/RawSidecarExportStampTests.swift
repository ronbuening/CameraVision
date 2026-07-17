import Foundation
import XCTest

@testable import AISidecarCore

final class RawSidecarExportStampTests: XCTestCase {
    func testLegacyStampOmitsQualityFieldsAndParsesWithNilOptionals() throws {
        let fixture = try makeFixture()
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)

        try RawSidecarExportStamp.stamp(
            sidecarPath: fixture.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "b", count: 64),
                writerRecipeVersion: "writer-v1",
                engineVersion: "engine-v1",
                exportedAt: exportedAt
            )
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any]
        )
        let stamp = try XCTUnwrap(object[RawSidecarExportStamp.key] as? [String: Any])
        XCTAssertEqual(
            Set(stamp.keys),
            ["engine_version", "exported_at", "target_xmp_path", "writer_recipe_version", "xmp_sha256"]
        )

        let parsed = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: fixture.path))
        XCTAssertEqual(parsed.targetXMPPath, "/exports/Bird.xmp")
        XCTAssertEqual(parsed.xmpSHA256, String(repeating: "b", count: 64))
        XCTAssertEqual(parsed.writerRecipeVersion, "writer-v1")
        XCTAssertEqual(parsed.engineVersion, "engine-v1")
        XCTAssertEqual(parsed.exportedAt, exportedAt)
        XCTAssertNil(parsed.rating)
        XCTAssertNil(parsed.label)
        XCTAssertNil(parsed.urgency)
        XCTAssertNil(parsed.qualityTier)
    }

    func testQualityFieldsRoundTripFromPathAndDecodedDocument() throws {
        let fixture = try makeFixture()
        let expected = RawSidecarExportStamp.Contents(
            targetXMPPath: "/exports/Bird.xmp",
            xmpSHA256: String(repeating: "c", count: 64),
            writerRecipeVersion: "writer-v1",
            engineVersion: "engine-v1",
            exportedAt: Date(timeIntervalSince1970: 1_800_000_100),
            rating: "4",
            label: "Green",
            urgency: "2",
            qualityTier: .good
        )

        try RawSidecarExportStamp.stamp(sidecarPath: fixture.path, contents: expected)

        XCTAssertEqual(RawSidecarExportStamp.contents(sidecarPath: fixture.path), expected)
        let document = try RawJSONSidecarDocument(data: Data(contentsOf: fixture))
        XCTAssertEqual(RawSidecarExportStamp.contents(from: document), expected)

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any]
        )
        let stamp = try XCTUnwrap(object[RawSidecarExportStamp.key] as? [String: Any])
        XCTAssertEqual(stamp["rating"] as? String, "4")
        XCTAssertEqual(stamp["label"] as? String, "Green")
        XCTAssertEqual(stamp["urgency"] as? String, "2")
        XCTAssertEqual(stamp["quality_tier"] as? String, "good")
    }

    func testParserRejectsMalformedRequiredAndPresentOptionalFields() throws {
        let fixture = try makeFixture()
        try RawSidecarExportStamp.stamp(
            sidecarPath: fixture.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "d", count: 64),
                writerRecipeVersion: "writer-v1",
                engineVersion: "engine-v1",
                exportedAt: Date(timeIntervalSince1970: 1_800_000_200),
                rating: "4"
            )
        )

        try mutateStamp(at: fixture) { $0["exported_at"] = "not-a-date" }
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: fixture.path))

        try RawSidecarExportStamp.stamp(
            sidecarPath: fixture.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "d", count: 64),
                writerRecipeVersion: "writer-v1",
                engineVersion: "engine-v1",
                exportedAt: Date(timeIntervalSince1970: 1_800_000_200),
                qualityTier: .good
            )
        )
        try mutateStamp(at: fixture) { $0["quality_tier"] = "future-tier" }
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: fixture.path))

        let malformedScalars: [(field: String, value: Any)] = [
            ("rating", 4),
            ("rating", ""),
            ("rating", "6"),
            ("rating", "04"),
            ("rating", "+4"),
            ("label", "   "),
            ("label", "Green|Owned"),
            ("urgency", "0"),
            ("urgency", "9"),
            ("urgency", "02"),
        ]
        for malformed in malformedScalars {
            try RawSidecarExportStamp.stamp(
                sidecarPath: fixture.path,
                contents: RawSidecarExportStamp.Contents(
                    targetXMPPath: "/exports/Bird.xmp",
                    xmpSHA256: String(repeating: "d", count: 64),
                    writerRecipeVersion: "writer-v1",
                    engineVersion: "engine-v1",
                    exportedAt: Date(timeIntervalSince1970: 1_800_000_200)
                )
            )
            try mutateStamp(at: fixture) { $0[malformed.field] = malformed.value }
            XCTAssertNil(
                RawSidecarExportStamp.contents(sidecarPath: fixture.path),
                "Expected malformed \(malformed.field)=\(malformed.value) to fail closed"
            )
        }
    }

    func testRestampPreservesUnknownNestedFieldsWhileClearingKnownOptionals() throws {
        let fixture = try makeFixture()
        try RawSidecarExportStamp.stamp(
            sidecarPath: fixture.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "e", count: 64),
                writerRecipeVersion: "writer-v1",
                engineVersion: "engine-v1",
                exportedAt: Date(timeIntervalSince1970: 1_800_000_300),
                rating: "4",
                label: "Green",
                urgency: "2",
                qualityTier: .good
            )
        )
        try mutateStamp(at: fixture) {
            $0["future_provenance"] = ["source": "future-writer", "version": 2]
        }

        try RawSidecarExportStamp.stamp(
            sidecarPath: fixture.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: "/exports/Bird.xmp",
                xmpSHA256: String(repeating: "f", count: 64),
                writerRecipeVersion: "writer-v2",
                engineVersion: "engine-v2",
                exportedAt: Date(timeIntervalSince1970: 1_800_000_400)
            )
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any]
        )
        let stamp = try XCTUnwrap(object[RawSidecarExportStamp.key] as? [String: Any])
        XCTAssertEqual(
            stamp["future_provenance"] as? [String: AnyHashable],
            ["source": "future-writer", "version": 2]
        )
        XCTAssertNil(stamp["rating"])
        XCTAssertNil(stamp["label"])
        XCTAssertNil(stamp["urgency"])
        XCTAssertNil(stamp["quality_tier"])
    }

    private func makeFixture() throws -> URL {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Bird.JPG.ai.json")
        let sidecar = RawJSONSidecar(
            source: makeSource(
                fileName: "Bird.JPG",
                relativePath: "Bird.JPG",
                path: root.appendingPathComponent("Bird.JPG").path
            ),
            runConfiguration: .builtInDefaults,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try RawJSONSidecarWriter().write(sidecar, to: destination.path, existingPolicy: .fail)
        return destination
    }

    private func mutateStamp(
        at sidecar: URL,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any]
        )
        var stamp = try XCTUnwrap(object[RawSidecarExportStamp.key] as? [String: Any])
        mutation(&stamp)
        object[RawSidecarExportStamp.key] = stamp
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: sidecar)
    }
}
