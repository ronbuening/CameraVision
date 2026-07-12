import XCTest

@testable import AISidecarCore

final class StarterVocabularyTests: XCTestCase {
    func testBundledStarterVocabularyLoadsThroughDefaultPath() throws {
        let vocabulary = try DefaultVocabulary.load()

        XCTAssertEqual(vocabulary.identity.path, "bundle://Vocabularies/default-vocabulary.json")
        XCTAssertEqual(vocabulary.identity.schemaVersion, NormalizationSchemaIdentifiers.vocabulary)
        XCTAssertEqual(vocabulary.identity.sha256, "a6d968a64ce68eae18e571188ff4fc921b7a2ebb30b1464cc641d4b1f8838553")
        XCTAssertEqual(vocabulary.entries.count, 7_777)
    }

    func testAppendixARequiredEntriesArePresent() throws {
        let vocabulary = try DefaultVocabulary.load()
        let required = [
            "Subject|Wildlife",
            "Subject|Wildlife|Birds",
            "Subject|Wildlife|Birds|Herons and Egrets",
            "Subject|Wildlife|Birds|Raptors",
            "Subject|Wildlife|Mammals",
            "Subject|Wildlife|Reptiles and Amphibians",
            "Subject|Plants",
            "Subject|Plants|Flowers",
            "Subject|Architecture",
            "Subject|Landscape",
            "Subject|People",
            "Habitat|Wetland",
            "Habitat|Beach",
            "Habitat|Forest",
            "Habitat|Urban",
            "Habitat|Garden",
            "Scene|Outdoor",
            "Scene|Indoor",
            "Behavior|Flying",
            "Behavior|Perching",
            "Behavior|Feeding",
            "Behavior|Resting",
            "Objects|Vehicle",
            "Objects|Building",
            "Workflow|Needs Review",
            "Workflow|AI Suggested",
        ]

        for canonicalPath in required {
            XCTAssertNotNil(vocabulary.index.entry(canonicalPath: canonicalPath), canonicalPath)
        }
    }

    func testStarterVocabularyRepresentativePolicies() throws {
        let vocabulary = try DefaultVocabulary.load()

        let birds = try XCTUnwrap(vocabulary.index.entry(canonicalPath: "Subject|Wildlife|Birds"))
        XCTAssertEqual(birds.directApplyPolicy, .allow)
        XCTAssertTrue(birds.autoApplyAllowed)
        XCTAssertEqual(birds.propagationScope, .local)
        XCTAssertEqual(birds.specificity, .broad)

        let greatEgret = try XCTUnwrap(
            vocabulary.index.entry(canonicalPath: "Species / Taxonomy|Birds|Herons and Egrets|Great Egret")
        )
        XCTAssertTrue(greatEgret.requiresReview)
        XCTAssertEqual(greatEgret.directApplyPolicy, .userOnly)
        XCTAssertFalse(greatEgret.autoApplyAllowed)

        let wetland = try XCTUnwrap(vocabulary.index.entry(canonicalPath: "Habitat|Wetland"))
        XCTAssertEqual(wetland.directApplyPolicy, .allow)
        XCTAssertEqual(wetland.propagationScope, .local)

        let needsReview = try XCTUnwrap(vocabulary.index.entry(canonicalPath: "Workflow|Needs Review"))
        XCTAssertEqual(needsReview.propagationScope, .global)
        XCTAssertEqual(needsReview.specificity, .broad)
    }

    func testBundledSharedFlatLabelRemainsAmbiguousBeforeNumberFallbacks() throws {
        let vocabulary = try DefaultVocabulary.load()

        XCTAssertNil(vocabulary.index.entry(matching: "Birds"))
        XCTAssertEqual(
            vocabulary.index.entry(matching: "bird")?.canonicalPath,
            "Subject|Wildlife|Birds"
        )
        XCTAssertEqual(
            vocabulary.index.entry(matching: "Species / Taxonomy|Birds")?.canonicalPath,
            "Species / Taxonomy|Birds"
        )
    }
}
