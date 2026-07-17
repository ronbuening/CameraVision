import Foundation
import XCTest

@testable import AISidecarCore

final class XMPQualityConflictMatrixTests: XCTestCase {
    func testRatingConflictPolicyMatrix() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let rows: [ConflictRow] = [
            ConflictRow(
                name: "preserve absent",
                policy: .preserve,
                existingRating: nil,
                stampedRating: nil,
                expectedAction: .write
            ),
            ConflictRow(
                name: "preserve equal",
                policy: .preserve,
                existingRating: "4",
                stampedRating: nil,
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "preserve different foreign",
                policy: .preserve,
                existingRating: "3",
                stampedRating: "2",
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "preserve different matches stamp",
                policy: .preserve,
                existingRating: "3",
                stampedRating: "3",
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "preserve different stamp missing",
                policy: .preserve,
                existingRating: "3",
                stampedRating: nil,
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "refresh absent",
                policy: .refresh,
                existingRating: nil,
                stampedRating: nil,
                expectedAction: .write
            ),
            ConflictRow(
                name: "refresh equal",
                policy: .refresh,
                existingRating: "4",
                stampedRating: nil,
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "refresh different foreign",
                policy: .refresh,
                existingRating: "3",
                stampedRating: "2",
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "refresh different matches stamp",
                policy: .refresh,
                existingRating: "3",
                stampedRating: "3",
                expectedAction: .overwrite
            ),
            ConflictRow(
                name: "refresh different stamp missing",
                policy: .refresh,
                existingRating: "3",
                stampedRating: nil,
                expectedAction: .skipExisting
            ),
            ConflictRow(
                name: "refresh absent stamp present",
                policy: .refresh,
                existingRating: nil,
                stampedRating: "3",
                expectedAction: .write
            ),
            ConflictRow(
                name: "overwrite absent",
                policy: .overwrite,
                existingRating: nil,
                stampedRating: nil,
                expectedAction: .overwrite
            ),
            ConflictRow(
                name: "overwrite equal",
                policy: .overwrite,
                existingRating: "4",
                stampedRating: nil,
                expectedAction: .overwrite
            ),
            ConflictRow(
                name: "overwrite different foreign",
                policy: .overwrite,
                existingRating: "3",
                stampedRating: "2",
                expectedAction: .overwrite
            ),
            ConflictRow(
                name: "overwrite different matches stamp",
                policy: .overwrite,
                existingRating: "3",
                stampedRating: "3",
                expectedAction: .overwrite
            ),
            ConflictRow(
                name: "overwrite different stamp missing",
                policy: .overwrite,
                existingRating: "3",
                stampedRating: nil,
                expectedAction: .overwrite
            ),
        ]

        for (index, row) in rows.enumerated() {
            let input = try qualityInput(stampedRating: row.stampedRating)
            let targetPath = "/photos/Bird.xmp"
            let snapshot = XMPMetadataSnapshot(
                targetPath: targetPath,
                exists: true,
                flatKeywords: [],
                hierarchicalKeywords: [],
                unmanagedContentFingerprint: .empty(),
                rating: row.existingRating
            )
            var configuration = ResolvedXMPExportConfiguration.builtInDefaults
            configuration.qualityGrading = ResolvedQualityGradingConfiguration(
                enabled: true,
                conflictPolicy: row.policy,
                policy: QualityGradingPolicy(
                    writeRating: true,
                    writeLabel: false,
                    writeUrgency: false,
                    writeKeywords: false
                )
            )

            let document = XMPChangePlanner().plan(
                inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
                extractionResults: [emptyExtraction(for: input)],
                configuration: configuration,
                snapshotReader: { requestedPath in
                    guard requestedPath == targetPath else {
                        throw SidecarError(
                            code: .validationFailed,
                            stage: .write,
                            message: "Unexpected snapshot path: \(requestedPath)",
                            recoverable: false
                        )
                    }
                    return snapshot
                }
            )

            XCTAssertTrue(document.inputFailures.isEmpty, row.name)
            let plan = try XCTUnwrap(document.targetPlans.first, row.name)
            XCTAssertEqual(plan.status, .planned, row.name)
            XCTAssertEqual(plan.qualityTier, .good, row.name)
            let write = try XCTUnwrap(plan.ratingWrite, row.name)
            XCTAssertEqual(write.field, "xmp:Rating", row.name)
            XCTAssertEqual(write.plannedValue, "4", row.name)
            XCTAssertEqual(write.existingValue, row.existingRating, row.name)
            XCTAssertEqual(write.action, row.expectedAction, row.name)
            XCTAssertNil(plan.labelWrite, row.name)
            XCTAssertNil(plan.urgencyWrite, row.name)

            let target = root.appendingPathComponent("Matrix-\(index).xmp")
            try Data(ratingXMP(row.existingRating).utf8).write(to: target)
            var executablePlan = plan
            executablePlan.targetXMPPath = target.path
            executablePlan.targetRelativePath = target.lastPathComponent
            let writeResult = try OwnedXMPSidecarEngine().apply(XMPWriteRequest(plan: executablePlan))
            let expectedRating = row.expectedAction == .skipExisting ? row.existingRating : "4"
            XCTAssertEqual(writeResult.postWriteSnapshot.rating, expectedRating, row.name)
            XCTAssertEqual(
                try OwnedXMPSidecarEngine().readSnapshot(at: target.path).rating,
                expectedRating,
                row.name
            )
        }
    }

    func testDisabledGradingKeepsPlanBytesStableAndNeverReadsXMP() throws {
        let inputWithQualityAssociation = try qualityInput(stampedRating: "3")
        var inputWithoutQualityAssociation = inputWithQualityAssociation
        inputWithoutQualityAssociation.qualitySidecarPath = nil
        inputWithoutQualityAssociation.qualityDocument = nil
        let counter = SnapshotReadCounter()

        let withAssociation = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [inputWithQualityAssociation], failures: []),
            extractionResults: [emptyExtraction(for: inputWithQualityAssociation)],
            configuration: .builtInDefaults,
            snapshotReader: { path in
                counter.increment()
                return .empty(targetPath: path, exists: false)
            }
        )
        let withoutAssociation = XMPChangePlanner().plan(
            inputBatch: RawJSONSidecarInputBatch(inputs: [inputWithoutQualityAssociation], failures: []),
            extractionResults: [emptyExtraction(for: inputWithoutQualityAssociation)],
            configuration: .builtInDefaults
        )

        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(withAssociation, withoutAssociation)
        let encoder = JSONCoding.documentEncoder()
        let encoded = try encoder.encode(withAssociation)
        XCTAssertEqual(encoded, try encoder.encode(withoutAssociation))
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("quality_sidecar_path"))
        XCTAssertFalse(text.contains("quality_explanation"))
        XCTAssertFalse(text.contains("quality_tier"))
        XCTAssertFalse(text.contains("rating_write"))
    }

    func testPreservedForeignLabelSuppressesCorrespondingUrgencyWrite() throws {
        let input = try qualityInput(stampedRating: nil)
        var policy = QualityGradingPolicy(
            writeRating: false,
            writeLabel: true,
            writeUrgency: true,
            writeKeywords: false
        )
        policy.labelMap[.good] = "Green"
        policy.urgencyMap[.good] = 2
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .preserve,
            policy: policy
        )

        let plan = try XCTUnwrap(
            XMPChangePlanner().plan(
                inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
                extractionResults: [emptyExtraction(for: input)],
                configuration: configuration,
                snapshotReader: { path in
                    XMPMetadataSnapshot(
                        targetPath: path,
                        exists: true,
                        flatKeywords: [],
                        hierarchicalKeywords: [],
                        unmanagedContentFingerprint: .empty(),
                        label: "Blue"
                    )
                }
            ).targetPlans.first
        )

        XCTAssertEqual(plan.labelWrite?.action, .skipExisting)
        XCTAssertEqual(plan.labelWrite?.existingValue, "Blue")
        XCTAssertEqual(plan.urgencyWrite?.action, .skipExisting)
        XCTAssertNil(plan.urgencyWrite?.existingValue)
        XCTAssertTrue(plan.qualityExplanation?.contains(where: { $0.hasPrefix("urgency suppressed:") }) == true)
    }

    func testRefreshFailsClosedForNewestWrongTargetAndAmbiguousTimestampTie() throws {
        let cases = [
            StampTrustCase(
                name: "newest targets another sidecar",
                primaryRating: "3",
                primaryTarget: "/photos/Bird.xmp",
                primaryDate: "2027-01-15T08:00:00Z",
                qualityRating: "3",
                qualityTarget: "/photos/Other.xmp",
                qualityDate: "2027-02-15T08:00:00Z",
                expectedAction: .skipExisting,
                explanationFragment: "newest export stamp targets another XMP sidecar"
            ),
            StampTrustCase(
                name: "equal timestamp ratings disagree",
                primaryRating: "3",
                primaryTarget: "/photos/Bird.xmp",
                primaryDate: "2027-01-15T08:00:00Z",
                qualityRating: "2",
                qualityTarget: "/photos/Bird.xmp",
                qualityDate: "2027-01-15T08:00:00Z",
                expectedAction: .skipExisting,
                explanationFragment: "newest export stamps disagree on rating"
            ),
            StampTrustCase(
                name: "newest matching stamp wins over older wrong target",
                primaryRating: "2",
                primaryTarget: "/photos/Other.xmp",
                primaryDate: "2027-01-15T08:00:00Z",
                qualityRating: "3",
                qualityTarget: "/photos/Bird.xmp",
                qualityDate: "2027-02-15T08:00:00Z",
                expectedAction: .overwrite,
                explanationFragment: nil
            ),
            StampTrustCase(
                name: "equal timestamp missing and present ratings disagree",
                primaryRating: "3",
                primaryTarget: "/photos/Bird.xmp",
                primaryDate: "2027-01-15T08:00:00Z",
                qualityRating: nil,
                qualityTarget: "/photos/Bird.xmp",
                qualityDate: "2027-01-15T08:00:00Z",
                expectedAction: .skipExisting,
                explanationFragment: "newest export stamps disagree on rating"
            ),
        ]
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .refresh,
            policy: QualityGradingPolicy(
                writeRating: true,
                writeLabel: false,
                writeUrgency: false,
                writeKeywords: false
            )
        )

        for trustCase in cases {
            let input = try twoContributorInput(for: trustCase)
            let plan = try XCTUnwrap(
                XMPChangePlanner().plan(
                    inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
                    extractionResults: [emptyExtraction(for: input)],
                    configuration: configuration,
                    snapshotReader: { path in
                        XMPMetadataSnapshot(
                            targetPath: path,
                            exists: true,
                            flatKeywords: [],
                            hierarchicalKeywords: [],
                            unmanagedContentFingerprint: .empty(),
                            rating: "3"
                        )
                    }
                ).targetPlans.first,
                trustCase.name
            )

            XCTAssertEqual(plan.ratingWrite?.action, trustCase.expectedAction, trustCase.name)
            if let explanationFragment = trustCase.explanationFragment {
                XCTAssertTrue(
                    plan.qualityExplanation?.contains(where: { $0.contains(explanationFragment) }) == true,
                    trustCase.name
                )
            }
        }
    }

    func testQualityKeywordRoutesNormalizeComponentsAndRejectUnsafeTerms() throws {
        let input = try qualityInput(stampedRating: nil)
        let cases: [(root: String, flat: [String], hierarchical: [String])] = [
            ("  AI   Quality  ", ["AI Quality good"], ["AI Quality|good"]),
            ("GPS Data", [], []),
        ]

        for keywordCase in cases {
            var configuration = ResolvedXMPExportConfiguration.builtInDefaults
            configuration.qualityGrading = ResolvedQualityGradingConfiguration(
                enabled: true,
                conflictPolicy: .preserve,
                policy: QualityGradingPolicy(
                    writeRating: false,
                    writeLabel: false,
                    writeUrgency: false,
                    writeKeywords: true,
                    keywordRoot: keywordCase.root
                )
            )
            let plan = try XCTUnwrap(
                XMPChangePlanner().plan(
                    inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
                    extractionResults: [emptyExtraction(for: input)],
                    configuration: configuration
                ).targetPlans.first
            )

            XCTAssertEqual(plan.flatKeywordsToAdd.map(\.term), keywordCase.flat)
            XCTAssertEqual(plan.hierarchicalKeywordsToAdd.map(\.term), keywordCase.hierarchical)
        }
    }

    func testScalarGradeWithoutSnapshotReaderFailsTargetClosed() throws {
        let input = try qualityInput(stampedRating: nil)
        var configuration = ResolvedXMPExportConfiguration.builtInDefaults
        configuration.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .preserve,
            policy: QualityGradingPolicy(
                writeRating: true,
                writeLabel: false,
                writeUrgency: false,
                writeKeywords: false
            )
        )

        let plan = try XCTUnwrap(
            XMPChangePlanner().plan(
                inputBatch: RawJSONSidecarInputBatch(inputs: [input], failures: []),
                extractionResults: [emptyExtraction(for: input)],
                configuration: configuration
            ).targetPlans.first
        )

        XCTAssertEqual(plan.status, .failed)
        XCTAssertEqual(plan.failures.first?.code, .validationFailed)
        XCTAssertNil(plan.ratingWrite)
    }

    private struct ConflictRow {
        let name: String
        let policy: ScalarConflictPolicy
        let existingRating: String?
        let stampedRating: String?
        let expectedAction: PlannedScalarWrite.Action
    }

    private struct StampTrustCase {
        let name: String
        let primaryRating: String?
        let primaryTarget: String
        let primaryDate: String
        let qualityRating: String?
        let qualityTarget: String
        let qualityDate: String
        let expectedAction: PlannedScalarWrite.Action
        let explanationFragment: String?
    }

    private func qualityInput(stampedRating: String?) throws -> ResolvedRawSidecarInput {
        let source = SourceImage(
            path: "/photos/Bird.JPG",
            relativePath: "Bird.JPG",
            fileName: "Bird.JPG",
            fileExtension: "JPG",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedType: .jpg,
            identity: SourceIdentity(policy: .sha256, sha256: String(repeating: "a", count: 64))
        )
        let qualityAssessment: JSONValue = .object([
            "composition": .string("strong"),
            "confidence": .string("high"),
            "concerns": .array([]),
            "focus": .string("strong"),
            "overall_effectiveness": .string("acceptable"),
            "strengths": .array([]),
        ])
        let run = ModelRunRecord(
            inputRole: .wholeImage,
            model: "test:model",
            modelDigest: "sha256:test",
            runtime: "test",
            runtimeVersion: "1",
            promptVersion: "prompt.whole_image.quality",
            promptSHA256: String(repeating: "b", count: 64),
            responseSchemaVersion: "schema.test",
            requestOptions: .default,
            inputDerivativeSHA256: String(repeating: "c", count: 64),
            rawResponseText: "fixture",
            parsedResponseJSON: .object(["quality_assessment": qualityAssessment]),
            jsonValid: true,
            durationMs: 1,
            error: nil
        )
        let sidecar = RawJSONSidecar(
            source: source,
            runConfiguration: ResolvedRunConfiguration.builtInDefaults.with(taskProfile: .qualityOnly),
            modelRuns: [run],
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        var document = try RawJSONSidecarDocument(sidecar: sidecar)
        if let stampedRating {
            var object = try XCTUnwrap(try document.jsonValue().objectValue)
            object[RawSidecarExportStamp.key] = .object([
                "engine_version": .string("test-engine"),
                "exported_at": .string("2027-01-15T08:00:00Z"),
                "rating": .string(stampedRating),
                "target_xmp_path": .string("/photos/Bird.xmp"),
                "writer_recipe_version": .string("test-recipe"),
                "xmp_sha256": .string(String(repeating: "d", count: 64)),
            ])
            let data = try JSONCoding.documentEncoder(iso8601Dates: false).encode(JSONValue.object(object))
            document = try RawJSONSidecarDocument(data: data)
        }

        return ResolvedRawSidecarInput(
            sidecarPath: URL(fileURLWithPath: "/sidecars/Bird.JPG.quality.ai.json"),
            document: document,
            qualitySidecarPath: URL(fileURLWithPath: "/sidecars/Bird.JPG.quality.ai.json"),
            qualityDocument: document,
            sourcePath: URL(fileURLWithPath: source.path),
            sourceIdentityStatus: .matched,
            relativePath: "Bird.JPG.quality.ai.json",
            warnings: []
        )
    }

    private func emptyExtraction(for input: ResolvedRawSidecarInput) -> CandidateExtractionResult {
        CandidateExtractionResult(
            sourceSidecar: input.sidecarPath.standardizedFileURL.path,
            sourceImage: input.document.sidecar.source.path,
            extractedCandidates: [],
            flatKeywords: [],
            hierarchicalKeywords: [],
            skippedCandidates: [],
            issues: []
        )
    }

    private func twoContributorInput(for trustCase: StampTrustCase) throws -> ResolvedRawSidecarInput {
        let base = try qualityInput(stampedRating: nil)
        let primaryPath = URL(fileURLWithPath: "/sidecars/Bird.JPG.ai.json")
        let qualityPath = URL(fileURLWithPath: "/sidecars/Bird.JPG.quality.ai.json")
        return ResolvedRawSidecarInput(
            sidecarPath: primaryPath,
            document: try stampedDocument(
                base.document,
                rating: trustCase.primaryRating,
                target: trustCase.primaryTarget,
                exportedAt: trustCase.primaryDate
            ),
            qualitySidecarPath: qualityPath,
            qualityDocument: try stampedDocument(
                base.document,
                rating: trustCase.qualityRating,
                target: trustCase.qualityTarget,
                exportedAt: trustCase.qualityDate
            ),
            sourcePath: base.sourcePath,
            sourceIdentityStatus: .matched,
            relativePath: primaryPath.lastPathComponent,
            warnings: []
        )
    }

    private func stampedDocument(
        _ document: RawJSONSidecarDocument,
        rating: String?,
        target: String,
        exportedAt: String
    ) throws -> RawJSONSidecarDocument {
        var object = try XCTUnwrap(try document.jsonValue().objectValue)
        var stamp: [String: JSONValue] = [
            "engine_version": .string("test-engine"),
            "exported_at": .string(exportedAt),
            "target_xmp_path": .string(target),
            "writer_recipe_version": .string("test-recipe"),
            "xmp_sha256": .string(String(repeating: "d", count: 64)),
        ]
        if let rating {
            stamp["rating"] = .string(rating)
        }
        object[RawSidecarExportStamp.key] = .object(stamp)
        return try RawJSONSidecarDocument(
            data: JSONCoding.documentEncoder(iso8601Dates: false).encode(JSONValue.object(object))
        )
    }

    private func ratingXMP(_ rating: String?) -> String {
        let namespace = rating == nil ? "" : " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""
        let attribute = rating.map { " xmp:Rating=\"\($0)\"" } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"\(namespace)>
              <rdf:Description rdf:about=""\(attribute)/>
            </rdf:RDF>
            """
    }
}

private final class SnapshotReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
