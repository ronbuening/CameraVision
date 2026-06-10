import XCTest
@testable import AISidecarCore

final class SidecarNamingTests: XCTestCase {
    func testSidecarFileNamePreservesOriginalExtension() {
        let source = makeSource(fileName: "_DSC1234.NEF", relativePath: "_DSC1234.NEF")

        XCTAssertEqual(SidecarNaming.sidecarFileName(for: source), "_DSC1234.NEF.ai.json")
        XCTAssertEqual(SidecarNaming.sidecarRelativePath(for: source), "_DSC1234.NEF.ai.json")
    }

    func testOutputDirectoryMirrorsRelativeTree() throws {
        let output = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let source = makeSource(
            fileName: "_DSC1234.NEF",
            relativePath: "2026/06/_DSC1234.NEF",
            path: "/photos/2026/06/_DSC1234.NEF"
        )

        let path = SidecarNaming.destinationPath(for: source, outputDir: output.path)

        XCTAssertEqual(path, output.appendingPathComponent("2026/06/_DSC1234.NEF.ai.json").path)
    }

    func testDuplicateBasenamesInDifferentFoldersDoNotCollide() throws {
        let output = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let sources = [
            makeSource(
                fileName: "_DSC1234.NEF",
                relativePath: "2026/06/_DSC1234.NEF",
                path: "/photos/2026/06/_DSC1234.NEF"
            ),
            makeSource(
                fileName: "_DSC1234.NEF",
                relativePath: "2026/07/_DSC1234.NEF",
                path: "/photos/2026/07/_DSC1234.NEF"
            )
        ]

        let plan = SidecarNaming.plan(for: sources, outputDir: output.path)

        XCTAssertTrue(plan.collisions.isEmpty)
        XCTAssertEqual(
            plan.entries.map(\.sidecarRelativePath),
            ["2026/06/_DSC1234.NEF.ai.json", "2026/07/_DSC1234.NEF.ai.json"]
        )
    }

    func testCaseInsensitiveDestinationCollisionFailsAffectedSources() throws {
        let output = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let sources = [
            makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF", path: "/photos/Bird.NEF"),
            makeSource(fileName: "bird.NEF", relativePath: "bird.NEF", path: "/photos/bird.NEF")
        ]

        let plan = SidecarNaming.plan(for: sources, outputDir: output.path)

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.collisions.count, 1)
        XCTAssertEqual(plan.collisions.first?.sources.map(\.relativePath), ["Bird.NEF", "bird.NEF"])
        XCTAssertEqual(plan.collisions.first?.error.code, .sidecarCollision)
        XCTAssertEqual(plan.collisions.first?.error.stage, .write)
        XCTAssertTrue(plan.collisions.first?.error.recoverable == true)
    }
}

func makeSource(
    fileName: String,
    relativePath: String,
    path: String = "/photos/source.NEF"
) -> SourceImage {
    SourceImage(
        path: path,
        relativePath: relativePath,
        fileName: fileName,
        fileExtension: URL(fileURLWithPath: fileName).pathExtension,
        fileSize: 1,
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        detectedType: .nef,
        identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
    )
}

func temporaryDirectory(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("aisidecar-tests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
