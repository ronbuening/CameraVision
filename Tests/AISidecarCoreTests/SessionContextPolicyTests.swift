import XCTest

@testable import AISidecarCore

final class SessionContextPolicyTests: XCTestCase {
    func testSessionContextPropagationFlagsAreIndependentByContextType() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .subject,
                        text: "Wildlife",
                        canonicalPath: "Subject|Wildlife",
                        propagationAllowed: false
                    ),
                    phase3SessionContext(
                        .habitat,
                        text: "Wetland",
                        canonicalPath: "Habitat|Wetland",
                        propagationAllowed: true
                    ),
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: false
                    ),
                ],
                decisions: []
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG", "seq/IMG_0002.JPG"]),
            configuration: phase3Configuration()
        )

        XCTAssertEqual(Set(result.perAssetDecisions.map(\.contextType)), [.habitat])
        XCTAssertEqual(result.perAssetDecisions.map(\.canonicalPath), ["Habitat|Wetland", "Habitat|Wetland"])
        XCTAssertEqual(
            result.sessionContext.map(\.exportResult),
            [
                "propagation_not_allowed",
                "applied",
                "propagation_not_allowed",
            ])
    }

    func testSessionContextRecordsDirectConflictsWithoutOverridingModelEvidence() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .subject,
                        text: "Wildlife",
                        canonicalPath: "Subject|Wildlife",
                        propagationAllowed: true
                    )
                ],
                decisions: [
                    phase3DirectDecision(assetID: "asset-000002", canonicalPath: "Subject|Mammals")
                ]
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG", "seq/IMG_0002.JPG"]),
            configuration: phase3Configuration()
        )

        XCTAssertEqual(result.sessionContext.first?.conflictCount, 1)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "applied_with_conflicts")
        XCTAssertTrue(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000001"
                    && $0.stage == .userSessionContext
                    && $0.canonicalPath == "Subject|Wildlife"
            })
        XCTAssertFalse(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000002"
                    && $0.stage == .userSessionContext
                    && $0.canonicalPath == "Subject|Wildlife"
            })
    }

    func testUserOnlyReviewSensitiveContextCanWriteWhenExplicitlySuppliedByUser() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: []
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.stage, .userSessionContext)
        XCTAssertEqual(decision.contextType, .event)
        XCTAssertEqual(decision.directApplyPolicy, .userOnly)
        XCTAssertEqual(decision.status, .accepted)
        XCTAssertEqual(decision.flatKeyword, "Migration")
        XCTAssertEqual(decision.hierarchicalKeyword, "Event|Migration")
        XCTAssertEqual(decision.skipReasons, [.requiresReview])
    }

    func testWithheldDirectObservationDoesNotBlockExplicitUserContext() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: [
                    withheldUserOnlyMigrationDecision()
                ]
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        let context = try XCTUnwrap(
            result.perAssetDecisions.first {
                $0.assetID == "asset-000001"
                    && $0.canonicalPath == "Event|Migration"
                    && $0.stage == .userSessionContext
            })
        XCTAssertEqual(context.status, .accepted)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "applied")
        XCTAssertTrue(
            result.perAssetDecisions.contains {
                $0.assetID == "asset-000001"
                    && $0.canonicalPath == "Event|Migration"
                    && $0.stage == .directModelObservation
                    && $0.status == .withheld
            })
    }

    func testAcceptedDirectObservationStillSuppressesDuplicateUserContext() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: [
                    phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Event|Migration")
                ]
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        let matching = result.perAssetDecisions.filter {
            $0.assetID == "asset-000001" && $0.canonicalPath == "Event|Migration"
        }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.stage, .directModelObservation)
        XCTAssertEqual(matching.first?.status, .accepted)
        XCTAssertEqual(result.sessionContext.first?.conflictCount, 0)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "applied")
    }

    func testSingleImageModeAppliesContextOverWithheldDirectObservation() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: [
                    withheldUserOnlyMigrationDecision()
                ]
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration(normalizationMode: .singleImage)
        )

        let matching = result.perAssetDecisions.filter {
            $0.assetID == "asset-000001" && $0.canonicalPath == "Event|Migration"
        }
        XCTAssertEqual(matching.count, 2)
        XCTAssertTrue(matching.contains { $0.stage == .directModelObservation && $0.status == .withheld })
        XCTAssertTrue(matching.contains { $0.stage == .userSessionContext && $0.status == .accepted })
        XCTAssertEqual(result.sessionContext.first?.exportResult, "applied")
    }

    func testFlatOnlySessionContextHonorsDisabledFlatExport() throws {
        var entries = phase3VocabularyEntries()
        let migrationIndex = try XCTUnwrap(entries.firstIndex { $0.canonicalPath == "Event|Migration" })
        entries[migrationIndex].directApplyPolicy = .flatOnly
        entries[migrationIndex].exportFlatKeyword = false
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary(entries: entries)).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: []
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.status, .withheld)
        XCTAssertNil(decision.flatKeyword)
        XCTAssertFalse(decision.exportFlatKeyword)
        XCTAssertTrue(decision.skipReasons.contains(.disabledFlatExport))
        XCTAssertTrue(decision.skipReasons.contains(.directApplyFlatOnly))
        XCTAssertEqual(result.sessionContext.first?.exportResult, "withheld_by_policy")
    }

    func testSessionContextHonorsGlobalKeywordWriteFlags() throws {
        var configuration = phase3Configuration()
        configuration.writeFlatKeywords = false
        configuration.writeHierarchicalKeywords = false
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: []
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: configuration
        )

        let decision = try XCTUnwrap(result.perAssetDecisions.first)
        XCTAssertEqual(decision.status, .withheld)
        XCTAssertNil(decision.flatKeyword)
        XCTAssertNil(decision.hierarchicalKeyword)
        XCTAssertFalse(decision.exportFlatKeyword)
        XCTAssertFalse(decision.exportHierarchicalKeyword)
        XCTAssertTrue(decision.skipReasons.contains(.disabledFlatExport))
        XCTAssertTrue(decision.skipReasons.contains(.disabledHierarchicalExport))
        XCTAssertEqual(result.sessionContext.first?.exportResult, "withheld_by_policy")
    }

    func testWithholdSessionContextReportsWithheldByPolicy() throws {
        var entries = phase3VocabularyEntries()
        let migrationIndex = try XCTUnwrap(entries.firstIndex { $0.canonicalPath == "Event|Migration" })
        entries[migrationIndex].directApplyPolicy = .withhold
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary(entries: entries)).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: []
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        XCTAssertEqual(result.perAssetDecisions.first?.status, .withheld)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "withheld_by_policy")
    }

    func testAllConflictedSessionContextReportsNotAppliedConflicts() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .subject,
                        text: "Wildlife",
                        canonicalPath: "Subject|Wildlife",
                        propagationAllowed: true
                    )
                ],
                decisions: [
                    phase3DirectDecision(assetID: "asset-000001", canonicalPath: "Subject|Mammals")
                ]
            ),
            input: phase3InputBatch(["seq/IMG_0001.JPG"]),
            configuration: phase3Configuration()
        )

        XCTAssertEqual(result.sessionContext.first?.conflictCount, 1)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "not_applied_conflicts")
        XCTAssertFalse(result.perAssetDecisions.contains { $0.stage == .userSessionContext })
    }

    func testSessionContextWithNoTargetAssetsReportsTerminalResult() throws {
        let result = try BatchConsensusEngine(vocabulary: phase3LoadedVocabulary()).apply(
            canonicalization: phase3Canonicalization(
                sessionContext: [
                    phase3SessionContext(
                        .event,
                        text: "Migration",
                        canonicalPath: "Event|Migration",
                        propagationAllowed: true
                    )
                ],
                decisions: []
            ),
            input: phase3InputBatch([]),
            configuration: phase3Configuration()
        )

        XCTAssertTrue(result.perAssetDecisions.isEmpty)
        XCTAssertEqual(result.sessionContext.first?.exportResult, "no_target_assets")
        XCTAssertNotEqual(result.sessionContext.first?.exportResult, "pending_session_context_decision")
    }

    private func withheldUserOnlyMigrationDecision() -> PerAssetNormalizationDecision {
        PerAssetNormalizationDecision(
            assetID: "asset-000001",
            stage: .directModelObservation,
            status: .withheld,
            candidateKind: .canonicalVocabulary,
            canonicalPath: "Event|Migration",
            sourceText: "migration",
            namespace: .event,
            directApplyPolicy: .userOnly,
            requiresReview: true,
            exportFlatKeyword: false,
            exportHierarchicalKeyword: false,
            supportUnits: 1,
            supportingAssetIDs: ["asset-000001"],
            governingRule: "direct_apply_user_only",
            observationCount: 1,
            skipReasons: [.directApplyWithheld, .requiresReview]
        )
    }
}
