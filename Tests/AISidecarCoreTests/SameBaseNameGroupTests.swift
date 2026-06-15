import Foundation
import XCTest
@testable import AISidecarCore

final class SameBaseNameGroupTests: XCTestCase {
    func testRawJPEGPairProducesOneUnionedTargetPlan() throws {
        let raw = try input(fileName: "Bird.NEF", type: .nef)
        let jpeg = try input(fileName: "Bird.JPG", type: .jpg)
        let document = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [raw, jpeg], failures: []),
            extractionResults: [
                extraction(for: raw, terms: ["bird", "wetland"]),
                extraction(for: jpeg, terms: ["Bird", "portrait"])
            ],
            configuration: .builtInDefaults
        )

        XCTAssertTrue(document.inputFailures.isEmpty)
        XCTAssertEqual(document.targetPlans.count, 1)
        let plan = try XCTUnwrap(document.targetPlans.first)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertEqual(plan.targetRelativePath, "Bird.xmp")
        XCTAssertEqual(plan.sourceMembers.map(\.sourceRelativePath), ["Bird.JPG", "Bird.NEF"])
        XCTAssertEqual(plan.sourceMembers.filter(\.selected).count, 2)
        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["Bird", "portrait", "wetland"])
        XCTAssertEqual(plan.flatKeywordsToAdd.first { $0.normalizedKey == "bird" }?.candidates.count, 2)
        XCTAssertEqual(plan.hierarchicalKeywordsToAdd.map(\.term), plan.flatKeywordsToAdd.map(\.term))
        XCTAssertEqual(plan.groupWarnings.count, 1)
    }

    func testRawOnlyPairScopeSelectsOnlyRawLikeMembers() throws {
        let raw = try input(fileName: "Bird.NEF", type: .nef)
        let jpeg = try input(fileName: "Bird.JPG", type: .jpg)
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.pairScope = .rawOnly

        let plan = try XCTUnwrap(XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [raw, jpeg], failures: []),
            extractionResults: [
                extraction(for: raw, terms: ["raw term"]),
                extraction(for: jpeg, terms: ["jpeg term"])
            ],
            configuration: configuration
        ).targetPlans.first)

        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["raw term"])
        XCTAssertEqual(plan.sourceMembers.filter(\.selected).map(\.sourceRelativePath), ["Bird.NEF"])
        XCTAssertEqual(plan.sourceMembers.filter { !$0.selected }.map(\.skipReason), [.pairScopeRawOnly])
        XCTAssertEqual(plan.status, .planned)
    }

    func testJPEGOnlyPairScopeSelectsOnlyJPEGMembers() throws {
        let raw = try input(fileName: "Bird.NEF", type: .nef)
        let jpeg = try input(fileName: "Bird.JPG", type: .jpeg)
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.pairScope = .jpegOnly

        let plan = try XCTUnwrap(XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [raw, jpeg], failures: []),
            extractionResults: [
                extraction(for: raw, terms: ["raw term"]),
                extraction(for: jpeg, terms: ["jpeg term"])
            ],
            configuration: configuration
        ).targetPlans.first)

        XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), ["jpeg term"])
        XCTAssertEqual(plan.sourceMembers.filter(\.selected).map(\.sourceRelativePath), ["Bird.JPG"])
        XCTAssertEqual(plan.sourceMembers.filter { !$0.selected }.map(\.skipReason), [.pairScopeJPEGOnly])
        XCTAssertEqual(plan.status, .planned)
    }

    func testRestrictiveScopeWithNoSelectedMembersFailsGroup() throws {
        let tiff = try input(fileName: "Bird.TIF", type: .tif)
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.pairScope = .rawOnly

        let plan = try XCTUnwrap(XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [tiff], failures: []),
            extractionResults: [extraction(for: tiff, terms: ["tiff term"])],
            configuration: configuration
        ).targetPlans.first)

        XCTAssertEqual(plan.status, .failed)
        XCTAssertEqual(plan.failures.map(\.code), [.validationFailed])
        XCTAssertTrue(plan.flatKeywordsToAdd.isEmpty)
    }

    func testCaseInsensitiveTargetCollisionFailsAffectedGroups() throws {
        let upper = try input(fileName: "Bird.NEF", type: .nef)
        let lower = try input(fileName: "bird.JPG", type: .jpg)
        let document = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [upper, lower], failures: []),
            extractionResults: [
                extraction(for: upper, terms: ["upper"]),
                extraction(for: lower, terms: ["lower"])
            ],
            configuration: .builtInDefaults
        )

        XCTAssertEqual(document.targetPlans.count, 2)
        XCTAssertEqual(document.targetPlans.map(\.status), [.failed, .failed])
        XCTAssertEqual(document.targetPlans.flatMap(\.failures).map(\.code), [.sidecarCollision, .sidecarCollision])
    }

    private func input(fileName: String, type: SupportedImageType) throws -> ResolvedRawSidecarInput {
        let source = SourceImage(
            path: "/photos/\(fileName)",
            relativePath: fileName,
            fileName: fileName,
            fileExtension: URL(fileURLWithPath: fileName).pathExtension,
            fileSize: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: type,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
        return ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: "/sidecars/\(fileName).ai.json"),
            document: try RawJSONSidecarDocument(sidecar: RawJSONSidecar(
                source: source,
                runConfiguration: .builtInDefaults
            )),
            sourcePath: URL(fileURLWithPath: source.path),
            sourceIdentityStatus: .skipped,
            relativePath: "\(fileName).ai.json",
            warnings: []
        )
    }

    private func extraction(for input: ResolvedRawSidecarInput, terms: [String]) -> CandidateExtractionResult {
        let keywords = terms.map { term in
            let normalized = KeywordTextNormalizer.normalize(term)
            let key = KeywordTextNormalizer.deduplicationKey(for: normalized)
            return ExportableKeyword(
                term: normalized,
                normalizedKey: key,
                candidates: [
                    ExtractedCandidate(
                        term: term,
                        normalizedTerm: normalized,
                        confidence: .high,
                        evidence: "fixture",
                        provenance: CandidateProvenance(
                            sourceField: .proposedKeywords,
                            inputRole: .wholeImage,
                            sourceSidecar: input.sidecarPath.standardizedFileURL.path,
                            sourceImage: input.document.sidecar.source.path,
                            modelRunIndex: 0
                        )
                    )
                ]
            )
        }
        return CandidateExtractionResult(
            sourceSidecar: input.sidecarPath.standardizedFileURL.path,
            sourceImage: input.document.sidecar.source.path,
            extractedCandidates: keywords.flatMap(\.candidates),
            flatKeywords: keywords,
            hierarchicalKeywords: keywords,
            skippedCandidates: [],
            issues: []
        )
    }
}
