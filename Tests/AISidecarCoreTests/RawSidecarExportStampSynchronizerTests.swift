import Foundation
import XCTest

@testable import AISidecarCore

final class RawSidecarExportStampSynchronizerTests: XCTestCase {
    func testContributorPathsAreSelectedStandardizedDedupedFilteredAndSorted() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("nested/../A.JPG.ai.json").path
        let second = root.appendingPathComponent("B.JPG.QUALITY.AI.JSON").path
        let ignored = root.appendingPathComponent("ignored.json").path
        let unselected = root.appendingPathComponent("C.JPG.ai.json").path
        let plan = makePlan(
            targetPath: root.appendingPathComponent("Bird.xmp").path,
            members: [
                makeMember(sidecarPath: first, qualitySidecarPath: second, selected: true),
                makeMember(sidecarPath: first, qualitySidecarPath: ignored, selected: true),
                makeMember(sidecarPath: unselected, selected: false),
            ]
        )

        let paths = RawSidecarExportStampSynchronizer().selectedContributorSidecarPaths(for: plan)

        XCTAssertEqual(
            paths,
            [
                URL(fileURLWithPath: first).standardizedFileURL.path,
                URL(fileURLWithPath: second).standardizedFileURL.path,
            ].sorted(by: comparePaths)
        )
    }

    func testEnabledGradingClaimsPlannedScalarAndSemanticMatchAvoidsTimestampChurn() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Bird.xmp")
        let sidecar = try writeSidecar(named: "Bird.JPG.ai.json", in: root)
        try Data("xmp bytes".utf8).write(to: target)
        let plan = makePlan(
            targetPath: target.path,
            members: [makeMember(sidecarPath: sidecar.path)],
            ratingWrite: PlannedScalarWrite(
                field: "xmp:Rating",
                plannedValue: "4",
                existingValue: nil,
                action: .write
            ),
            qualityTier: .good
        )
        let report = makeReport(plan: plan, postWriteRating: "4")

        RawSidecarExportStampSynchronizer(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        ).synchronize(report: report, context: context, gradingEnabled: true)
        let firstContents = try XCTUnwrap(RawSidecarExportStamp.contents(sidecarPath: sidecar.path))
        let firstBytes = try Data(contentsOf: sidecar)
        XCTAssertEqual(firstContents.rating, "4")
        XCTAssertEqual(firstContents.qualityTier, .good)

        RawSidecarExportStampSynchronizer(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_900_000_000) }
        ).synchronize(report: report, context: context, gradingEnabled: true)

        XCTAssertEqual(try Data(contentsOf: sidecar), firstBytes)
        XCTAssertEqual(RawSidecarExportStamp.contents(sidecarPath: sidecar.path)?.exportedAt, firstContents.exportedAt)
    }

    func testDisabledGradingTrustsNewestMatchingCohortAndRequiresCommonValidOwnership() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Bird.xmp")
        let first = try writeSidecar(named: "A.JPG.ai.json", in: root)
        let second = try writeSidecar(named: "B.JPG.ai.json", in: root)
        try Data("xmp bytes".utf8).write(to: target)
        let plan = makePlan(
            targetPath: target.path,
            members: [
                makeMember(sidecarPath: first.path),
                makeMember(sidecarPath: second.path),
            ]
        )
        let report = makeReport(plan: plan, postWriteRating: "4")

        try stamp(first, targetPath: "/older/Other.xmp", exportedAt: 1_700_000_000, rating: "3")
        try stamp(second, targetPath: target.path, exportedAt: 1_800_000_000, rating: "4")
        let synchronizer = RawSidecarExportStampSynchronizer(
            logger: Logger(sink: { _ in }),
            now: { Date(timeIntervalSince1970: 1_900_000_000) }
        )
        synchronizer.synchronize(report: report, context: context, gradingEnabled: false)
        XCTAssertEqual(RawSidecarExportStamp.contents(sidecarPath: first.path)?.rating, "4")
        XCTAssertEqual(RawSidecarExportStamp.contents(sidecarPath: second.path)?.rating, "4")

        try stamp(first, targetPath: target.path, exportedAt: 2_000_000_000, rating: "4")
        try stamp(second, targetPath: "/other/Bird.xmp", exportedAt: 2_000_000_000, rating: "4")
        synchronizer.synchronize(report: report, context: context, gradingEnabled: false)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: first.path)?.rating)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: second.path)?.rating)

        try stamp(first, targetPath: target.path, exportedAt: 2_000_000_000, rating: "4")
        try stamp(second, targetPath: target.path, exportedAt: 2_000_000_000, rating: "3")
        synchronizer.synchronize(report: report, context: context, gradingEnabled: false)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: first.path)?.rating)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: second.path)?.rating)

        try stamp(first, targetPath: target.path, exportedAt: 2_100_000_000, rating: "4")
        try stamp(second, targetPath: target.path, exportedAt: 2_100_000_000, rating: "4")
        try mutateStamp(at: second) { $0["rating"] = 4 }
        synchronizer.synchronize(report: report, context: context, gradingEnabled: false)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: first.path)?.rating)
        XCTAssertNil(RawSidecarExportStamp.contents(sidecarPath: second.path)?.rating)
    }

    func testStampFailuresAndMissingContributorsLogBestEffortWarningsInCallOrder() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Bird.xmp")
        let missingSidecar = root.appendingPathComponent("Missing.JPG.ai.json")
        try Data("xmp bytes".utf8).write(to: target)
        let sink = StampLogSink()
        let synchronizer = RawSidecarExportStampSynchronizer(logger: Logger(sink: sink.append))

        let missingReport = makeReport(
            plan: makePlan(
                targetPath: target.path,
                members: [makeMember(sidecarPath: missingSidecar.path)]
            )
        )
        synchronizer.synchronize(report: missingReport, context: context, gradingEnabled: false)

        let emptyReport = makeReport(plan: makePlan(targetPath: target.path, members: []))
        synchronizer.synchronize(report: emptyReport, context: context, gradingEnabled: false)

        XCTAssertEqual(sink.lines.count, 2)
        XCTAssertTrue(sink.lines[0].contains("write_xmp.stamp_failed"))
        XCTAssertTrue(
            sink.lines[0].contains("XMP was written, but its raw-sidecar export stamp failed: ")
        )
        XCTAssertTrue(sink.lines[1].contains("write_xmp.stamp_skipped"))
        XCTAssertTrue(
            sink.lines[1].contains("Skipped export stamp because this target has no contributing raw .ai.json sidecar.")
        )
    }

    private var context: MetadataWriteEngineContext {
        MetadataWriteEngineContext(
            engineName: "test-engine",
            engineVersion: "engine-v1",
            writerRecipeVersion: "writer-v1"
        )
    }

    private func makePlan(
        targetPath: String,
        members: [SourceMemberPlan],
        ratingWrite: PlannedScalarWrite? = nil,
        qualityTier: QualityTier? = nil
    ) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: targetPath,
            targetRelativePath: URL(fileURLWithPath: targetPath).lastPathComponent,
            pairScope: .union,
            sourceMembers: members,
            flatKeywordsToAdd: [],
            hierarchicalKeywordsToAdd: [],
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .backupAndMerge,
            backupPlan: BackupPlan(
                backupSidecars: true,
                backupRequiredBeforeMerge: true,
                conflictPolicy: .backupAndMerge
            ),
            validationPlan: .phase2Default,
            failures: [],
            ratingWrite: ratingWrite,
            qualityTier: qualityTier
        )
    }

    private func makeMember(
        sidecarPath: String?,
        qualitySidecarPath: String? = nil,
        selected: Bool = true
    ) -> SourceMemberPlan {
        SourceMemberPlan(
            sourcePath: "/photos/Bird.JPG",
            sourceRelativePath: "Bird.JPG",
            sourceFileName: "Bird.JPG",
            sourceType: .jpg,
            sourceSidecarPath: sidecarPath,
            sourceSidecarRelativePath: sidecarPath.map { URL(fileURLWithPath: $0).lastPathComponent },
            sourceIdentityStatus: .matched,
            pairKind: .jpeg,
            selected: selected,
            skipReason: nil,
            flatKeywordContributionCount: 0,
            hierarchicalKeywordContributionCount: 0,
            qualitySidecarPath: qualitySidecarPath
        )
    }

    private func makeReport(
        plan: XMPChangePlan,
        postWriteRating: String? = nil
    ) -> XMPExportTargetReport {
        let preWrite = XMPMetadataSnapshot.empty(targetPath: plan.targetXMPPath, exists: false)
        let postWrite = XMPMetadataSnapshot(
            targetPath: plan.targetXMPPath,
            exists: true,
            flatKeywords: [],
            hierarchicalKeywords: [],
            unmanagedContentFingerprint: .empty(),
            rating: postWriteRating
        )
        let writeResult = XMPWriteResult(
            targetXMPPath: plan.targetXMPPath,
            created: true,
            modified: true,
            preWriteSnapshot: preWrite,
            postWriteSnapshot: postWrite,
            addedFlatKeywords: [],
            addedHierarchicalKeywords: [],
            resultingRating: postWriteRating
        )
        return XMPExportTargetReport(
            plan: plan,
            status: .created,
            writeResult: writeResult,
            durationMs: 0
        )
    }

    private func writeSidecar(named name: String, in root: URL) throws -> URL {
        let destination = root.appendingPathComponent(name)
        let sidecar = RawJSONSidecar(
            source: makeSource(
                fileName: name.replacingOccurrences(of: ".ai.json", with: ""),
                relativePath: name.replacingOccurrences(of: ".ai.json", with: ""),
                path: root.appendingPathComponent(name.replacingOccurrences(of: ".ai.json", with: "")).path
            ),
            runConfiguration: .builtInDefaults,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try RawJSONSidecarWriter().write(sidecar, to: destination.path, existingPolicy: .fail)
        return destination
    }

    private func stamp(
        _ sidecar: URL,
        targetPath: String,
        exportedAt: TimeInterval,
        rating: String
    ) throws {
        try RawSidecarExportStamp.stamp(
            sidecarPath: sidecar.path,
            contents: RawSidecarExportStamp.Contents(
                targetXMPPath: targetPath,
                xmpSHA256: String(repeating: "a", count: 64),
                writerRecipeVersion: context.writerRecipeVersion,
                engineVersion: context.engineVersion,
                exportedAt: Date(timeIntervalSince1970: exportedAt),
                rating: rating,
                qualityTier: .good
            )
        )
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

private final class StampLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLines: [String] = []

    var lines: [String] {
        lock.withLock { storedLines }
    }

    func append(_ line: String) {
        lock.withLock { storedLines.append(line) }
    }
}
