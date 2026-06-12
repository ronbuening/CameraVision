import Foundation
import XCTest
@testable import AISidecarCore

final class XMPNamingTests: XCTestCase {
    func testXMPFileNameReplacesSupportedImageExtensions() {
        let cases: [(String, SupportedImageType, String)] = [
            ("Bird.NEF", .nef, "Bird.xmp"),
            ("Bird.JPG", .jpg, "Bird.xmp"),
            ("Bird.JPEG", .jpeg, "Bird.xmp"),
            ("Bird.TIF", .tif, "Bird.xmp"),
            ("Bird.HEIC", .heic, "Bird.xmp"),
            ("Bird.PNG", .png, "Bird.xmp"),
            ("Bird.DNG", .dng, "Bird.xmp")
        ]

        for (fileName, type, expected) in cases {
            XCTAssertEqual(XMPNaming.xmpFileName(for: source(fileName: fileName, detectedType: type)), expected)
        }
    }

    func testOutputDirectoryMirrorsSourceRelativeTree() throws {
        let output = try temporaryDirectory()
        let input = try resolvedInput(
            source: source(
                fileName: "_DSC1234.NEF",
                relativePath: "2026/06/_DSC1234.NEF",
                path: "/photos/2026/06/_DSC1234.NEF"
            ),
            sourcePath: URL(fileURLWithPath: "/photos/2026/06/_DSC1234.NEF")
        )
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = output.path

        let destination = try XMPNaming().destination(for: input, configuration: configuration)

        XCTAssertEqual(destination.targetRelativePath, "2026/06/_DSC1234.xmp")
        XCTAssertEqual(destination.targetXMPPath, output.appendingPathComponent("2026/06/_DSC1234.xmp").path)
    }

    func testBesideSourceDestinationUsesResolvedSourcePath() throws {
        let sourceURL = URL(fileURLWithPath: "/photos/live/Bird.JPG")
        let input = try resolvedInput(
            source: source(fileName: "Bird.JPG", relativePath: "archive/Bird.JPG", path: "/stale/Bird.JPG"),
            sourcePath: sourceURL
        )

        let destination = try XMPNaming().destination(
            for: input,
            configuration: .builtInDefaults
        )

        XCTAssertEqual(destination.targetRelativePath, "archive/Bird.xmp")
        XCTAssertEqual(destination.targetXMPPath, "/photos/live/Bird.xmp")
    }

    func testStagingDestinationCanUseUnresolvedSourcePathWithOutputDirectory() throws {
        let output = try temporaryDirectory()
        let input = try resolvedInput(
            source: source(fileName: "Bird.JPG", relativePath: "missing/Bird.JPG", path: "/missing/Bird.JPG"),
            sourcePath: nil
        )
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.outputDir = output.path
        configuration.sourceVerification = .skip

        let destination = try XMPNaming().destination(for: input, configuration: configuration)

        XCTAssertEqual(destination.targetRelativePath, "missing/Bird.xmp")
        XCTAssertEqual(destination.targetXMPPath, output.appendingPathComponent("missing/Bird.xmp").path)
    }

    private func resolvedInput(source: SourceImage, sourcePath: URL?) throws -> ResolvedRawSidecarInput {
        ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: "/sidecars/\(source.fileName).ai.json"),
            document: try RawJSONSidecarDocument(sidecar: RawJSONSidecar(
                source: source,
                runConfiguration: .builtInDefaults
            )),
            sourcePath: sourcePath,
            sourceIdentityStatus: .skipped,
            relativePath: "\(source.fileName).ai.json",
            warnings: []
        )
    }

    private func source(
        fileName: String,
        relativePath: String? = nil,
        path: String = "/photos/source.NEF",
        detectedType: SupportedImageType = .nef
    ) -> SourceImage {
        SourceImage(
            path: path,
            relativePath: relativePath ?? fileName,
            fileName: fileName,
            fileExtension: URL(fileURLWithPath: fileName).pathExtension,
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: detectedType,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
    }
}
