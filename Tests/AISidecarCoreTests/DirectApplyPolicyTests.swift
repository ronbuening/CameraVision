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
}
