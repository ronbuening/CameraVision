import XCTest

@testable import AISidecarCore

final class SidecarNamingTests: XCTestCase {
    func testSidecarFileNamePreservesOriginalExtension() {
        let source = makeSource(fileName: "_DSC1234.NEF", relativePath: "_DSC1234.NEF")

        XCTAssertEqual(SidecarNaming.sidecarFileName(for: source), "_DSC1234.NEF.ai.json")
        XCTAssertEqual(SidecarNaming.sidecarRelativePath(for: source), "_DSC1234.NEF.ai.json")
    }

    func testQualitySidecarUsesDistinctSuffix() {
        let source = makeSource(fileName: "_DSC1234.NEF", relativePath: "2026/06/_DSC1234.NEF")

        XCTAssertEqual(
            SidecarNaming.sidecarFileName(for: source, kind: .quality),
            "_DSC1234.NEF.quality.ai.json"
        )
        XCTAssertEqual(
            SidecarNaming.sidecarRelativePath(for: source, kind: .quality),
            "2026/06/_DSC1234.NEF.quality.ai.json"
        )
        XCTAssertNotEqual(
            SidecarNaming.destinationPath(for: source, outputDir: nil),
            SidecarNaming.destinationPath(for: source, outputDir: nil, kind: .quality)
        )
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
            ),
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
            makeSource(fileName: "bird.NEF", relativePath: "bird.NEF", path: "/photos/bird.NEF"),
        ]

        let plan = SidecarNaming.plan(for: sources, outputDir: output.path)

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.collisions.count, 1)
        XCTAssertEqual(plan.collisions.first?.sources.map(\.relativePath), ["Bird.NEF", "bird.NEF"])
        XCTAssertEqual(plan.collisions.first?.error.code, .sidecarCollision)
        XCTAssertEqual(plan.collisions.first?.error.stage, .write)
        XCTAssertTrue(plan.collisions.first?.error.recoverable == true)
    }

    func testUnicodeNormalizationVariantsCollide() throws {
        let output = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let composed = "Café.NEF"
        let decomposed = "Cafe\u{301}.NEF"
        let sources = [
            makeSource(fileName: composed, relativePath: composed, path: "/photos/\(composed)"),
            makeSource(fileName: decomposed, relativePath: decomposed, path: "/photos/\(decomposed)"),
        ]

        let plan = SidecarNaming.plan(for: sources, outputDir: output.path)

        XCTAssertTrue(plan.entries.isEmpty)
        XCTAssertEqual(plan.collisions.count, 1)
        XCTAssertEqual(plan.collisions.first?.error.code, .sidecarCollision)
    }

    func testRawSidecarClassificationRecognizesMixedCaseSuffixesAndPrefersQuality() {
        let tagging = URL(fileURLWithPath: "/archive/Bird.JpG.AI.JSON")
        let quality = URL(fileURLWithPath: "/archive/Bird.JpG.QuAlItY.Ai.JsOn")
        let unrelated = URL(fileURLWithPath: "/archive/Bird.JpG.json")

        if case .tagging? = SidecarNaming.sidecarKind(for: tagging) {
            // Expected.
        } else {
            XCTFail("Expected a tagging raw sidecar")
        }
        if case .quality? = SidecarNaming.sidecarKind(for: quality) {
            // Expected.
        } else {
            XCTFail("Expected a quality raw sidecar")
        }
        XCTAssertNil(SidecarNaming.sidecarKind(for: unrelated))
    }

    func testRawSidecarBaseNameAndPairingKeyPreserveOriginalCase() {
        let tagging = URL(fileURLWithPath: "/archive/Bird.JpG.AI.JSON")
        let quality = URL(fileURLWithPath: "/archive/Bird.JpG.QuAlItY.Ai.JsOn")
        let caseVariant = URL(fileURLWithPath: "/archive/bird.JpG.quality.ai.json")

        XCTAssertEqual(SidecarNaming.sidecarBaseFileName(for: tagging), "Bird.JpG")
        XCTAssertEqual(SidecarNaming.sidecarBaseFileName(for: quality), "Bird.JpG")
        XCTAssertEqual(
            SidecarNaming.sidecarPairingKey(for: tagging),
            SidecarNaming.sidecarPairingKey(for: quality)
        )
        XCTAssertNotEqual(
            SidecarNaming.sidecarPairingKey(for: tagging),
            SidecarNaming.sidecarPairingKey(for: caseVariant)
        )
    }

    func testMixedCaseRawSidecarSiblingPathsPreserveBaseSpelling() {
        let tagging = URL(fileURLWithPath: "/archive/Bird.JpG.AI.JSON")
        let quality = URL(fileURLWithPath: "/archive/Bird.JpG.QuAlItY.Ai.JsOn")

        XCTAssertEqual(
            SidecarNaming.siblingSourceURL(for: quality),
            URL(fileURLWithPath: "/archive/Bird.JpG").standardizedFileURL
        )
        XCTAssertEqual(
            SidecarNaming.siblingSidecarURL(for: tagging),
            URL(fileURLWithPath: "/archive/Bird.JpG.quality.ai.json").standardizedFileURL
        )
        XCTAssertEqual(
            SidecarNaming.siblingSidecarURL(for: quality),
            URL(fileURLWithPath: "/archive/Bird.JpG.ai.json").standardizedFileURL
        )
    }

    func testGroupedSidecarInputsPreservesPrimaryWarningAndIdentitySemantics() throws {
        let taggingWarning = namingTestError(message: "tagging warning")
        let qualityWarning = namingTestError(message: "quality warning")
        let qualityOnlyWarning = namingTestError(message: "quality-only warning")
        let tagging = try namingTestInput(
            path: "/archive/z/Bird.JPG.ai.json",
            relativePath: "z/Bird.JPG.ai.json",
            taskProfile: .tagging,
            sourceIdentityStatus: .matched,
            warnings: [taggingWarning]
        )
        let quality = try namingTestInput(
            path: "/archive/z/Bird.JPG.quality.ai.json",
            relativePath: "z/Bird.JPG.quality.ai.json",
            taskProfile: .qualityOnly,
            sourceIdentityStatus: .mismatched,
            warnings: [qualityWarning]
        )
        let qualityOnly = try namingTestInput(
            path: "/archive/a/Only.JPG.quality.ai.json",
            relativePath: "a/Only.JPG.quality.ai.json",
            taskProfile: .qualityOnly,
            sourceIdentityStatus: .mismatched,
            warnings: [qualityOnlyWarning]
        )

        let grouped = SidecarNaming.groupedSidecarInputs([quality, tagging, qualityOnly])

        XCTAssertEqual(grouped.map(\.relativePath), ["a/Only.JPG.quality.ai.json", "z/Bird.JPG.ai.json"])
        XCTAssertEqual(grouped[0].qualitySidecarPath, qualityOnly.sidecarPath)
        XCTAssertEqual(grouped[0].warnings, [qualityOnlyWarning])
        XCTAssertEqual(grouped[0].sourceIdentityStatus, .mismatched)
        XCTAssertEqual(grouped[1].sidecarPath, tagging.sidecarPath)
        XCTAssertEqual(grouped[1].qualitySidecarPath, quality.sidecarPath)
        XCTAssertEqual(grouped[1].warnings, [taggingWarning, qualityWarning])
        XCTAssertEqual(grouped[1].sourceIdentityStatus, .mismatched)
    }
}

private func namingTestInput(
    path: String,
    relativePath: String,
    taskProfile: ModelTaskProfile,
    sourceIdentityStatus: SourceIdentityStatus,
    warnings: [SidecarError]
) throws -> ResolvedRawSidecarInput {
    let source = makeSource(fileName: "Bird.JPG", relativePath: "Bird.JPG")
    let document = try RawJSONSidecarDocument(
        sidecar: RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: taskProfile),
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    )
    return ResolvedRawSidecarInput(
        sidecarPath: URL(fileURLWithPath: path).standardizedFileURL,
        document: document,
        sourcePath: URL(fileURLWithPath: source.path).standardizedFileURL,
        sourceIdentityStatus: sourceIdentityStatus,
        relativePath: relativePath,
        warnings: warnings
    )
}

private func namingTestError(message: String) -> SidecarError {
    SidecarError(
        code: .sourceIdentityMismatch,
        stage: .scan,
        message: message,
        recoverable: true
    )
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
