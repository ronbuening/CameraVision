import XCTest
@testable import AISidecarCore

final class DirectApplyPolicyTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(DirectApplyPolicy.allow.rawValue, "allow")
        XCTAssertEqual(DirectApplyPolicy.withhold.rawValue, "withhold")
        XCTAssertEqual(DirectApplyPolicy.flatOnly.rawValue, "flat_only")
        XCTAssertEqual(DirectApplyPolicy.userOnly.rawValue, "user_only")
        XCTAssertEqual(PropagationScope.directOnly.rawValue, "direct_only")
        XCTAssertEqual(VocabularySpecificity.specific.rawValue, "specific")
    }

    func testDefaultDirectApplyPolicyIsIndependentFromPropagation() throws {
        let data = try vocabularyData(entries: [
            VocabularyEntry(
                canonicalPath: "Subject",
                flatKeyword: "Subject",
                namespace: .subject,
                parentPath: nil
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife",
                flatKeyword: "Wildlife",
                namespace: .subject,
                parentPath: "Subject",
                autoApplyAllowed: true,
                propagationScope: .local
            ),
            VocabularyEntry(
                canonicalPath: "Species / Taxonomy",
                flatKeyword: "Species / Taxonomy",
                namespace: .speciesTaxonomy,
                parentPath: nil
            ),
            VocabularyEntry(
                canonicalPath: "Species / Taxonomy|Birds",
                flatKeyword: "Birds",
                namespace: .speciesTaxonomy,
                parentPath: "Species / Taxonomy"
            ),
            VocabularyEntry(
                canonicalPath: "Species / Taxonomy|Birds|Great Egret",
                flatKeyword: "Great Egret",
                namespace: .speciesTaxonomy,
                parentPath: "Species / Taxonomy|Birds"
            )
        ])
        let vocabulary = try VocabularyLoader.load(data: data, sourcePath: "memory://defaults.json")

        let wildlife = try XCTUnwrap(vocabulary.index.entry(canonicalPath: "Subject|Wildlife"))
        XCTAssertEqual(wildlife.directApplyPolicy, .allow)
        XCTAssertTrue(wildlife.autoApplyAllowed)
        XCTAssertEqual(wildlife.propagationScope, .local)

        let species = try XCTUnwrap(vocabulary.index.entry(canonicalPath: "Species / Taxonomy|Birds|Great Egret"))
        XCTAssertEqual(species.directApplyPolicy, .withhold)
        XCTAssertFalse(species.autoApplyAllowed)
        XCTAssertEqual(species.propagationScope, .none)
        XCTAssertTrue(species.requiresReview)
    }

    func testModelEvidenceObeysUserOnlyAndAllowSpecificTagsCannotOverrideVocabularyPolicy() throws {
        let vocabulary = try VocabularyLoader.load(data: vocabularyData(entries: [
            VocabularyEntry(
                canonicalPath: "Subject",
                flatKeyword: "Subject",
                namespace: .subject,
                parentPath: nil,
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .withhold,
                propagationScope: PropagationScope.none,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|User Only",
                flatKeyword: "User Only",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["user-only"],
                requiresReview: false,
                directApplyPolicy: .userOnly
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Review Specific",
                flatKeyword: "Review Specific",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["review-specific"],
                requiresReview: true,
                directApplyPolicy: .withhold
            )
        ]), sourcePath: "memory://direct-apply-policy.json")
        var configuration = phase3Configuration(normalizationMode: .singleImage)
        configuration.allowSpecificTags = true

        let result = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: [extractionResult(terms: ["user-only", "review-specific"])],
            input: phase3InputBatch(["Bird.JPG"]),
            configuration: configuration
        )

        let userOnly: PerAssetNormalizationDecision = try XCTUnwrap(result.perAssetDecisions.first {
            $0.canonicalPath == "Subject|User Only"
        })
        XCTAssertEqual(userOnly.status, NormalizationDecisionStatus.withheld)
        XCTAssertEqual(userOnly.directApplyPolicy, DirectApplyPolicy.userOnly)
        XCTAssertEqual(userOnly.skipReasons, [NormalizationCandidateSkipReason.directApplyWithheld])

        let review: PerAssetNormalizationDecision = try XCTUnwrap(result.perAssetDecisions.first {
            $0.canonicalPath == "Subject|Review Specific"
        })
        XCTAssertEqual(review.status, NormalizationDecisionStatus.withheld)
        XCTAssertEqual(review.skipReasons, [
            NormalizationCandidateSkipReason.directApplyWithheld,
            NormalizationCandidateSkipReason.requiresReview
        ])
        XCTAssertNil(review.flatKeyword)
        XCTAssertNil(review.hierarchicalKeyword)
    }

    private func extractionResult(terms: [String]) -> CandidateExtractionResult {
        let candidates = terms.map { term in
            ExtractedCandidate(
                term: term,
                normalizedTerm: term,
                confidence: .high,
                evidence: "fixture evidence",
                provenance: CandidateProvenance(
                    sourceField: .proposedKeywords,
                    inputRole: .wholeImage,
                    sourceSidecar: "/sidecars/Bird.JPG.ai.json",
                    sourceImage: "/photos/Bird.JPG",
                    modelRunIndex: 0
                )
            )
        }
        return CandidateExtractionResult(
            sourceSidecar: "/sidecars/Bird.JPG.ai.json",
            sourceImage: "/photos/Bird.JPG",
            extractedCandidates: candidates,
            flatKeywords: [],
            hierarchicalKeywords: [],
            skippedCandidates: [],
            issues: []
        )
    }
}
