import XCTest
@testable import AISidecarCore

final class VocabularyIndexTests: XCTestCase {
    func testIndexesCanonicalSynonymAncestorsDescendantsAndGroups() throws {
        let vocabulary = try VocabularyLoader.load(
            data: vocabularyData(entries: minimalVocabularyEntries()),
            sourcePath: "memory://index.json"
        )

        XCTAssertEqual(vocabulary.index.entry(matching: "  AVIAN ")?.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(vocabulary.index.entry(matching: "Birds")?.canonicalPath, "Subject|Wildlife|Birds")
        XCTAssertEqual(vocabulary.index.entry(canonicalPath: "Subject|Wildlife")?.flatKeyword, "Wildlife")

        XCTAssertEqual(
            vocabulary.index.ancestors(of: "Subject|Wildlife|Birds").map(\.canonicalPath),
            ["Subject|Wildlife", "Subject"]
        )
        XCTAssertEqual(
            vocabulary.index.descendants(of: "Subject|Wildlife").map(\.canonicalPath),
            ["Subject|Wildlife|Birds", "Subject|Wildlife|Mammals"]
        )
        XCTAssertEqual(
            vocabulary.index.siblings(of: "Subject|Wildlife|Birds").map(\.canonicalPath),
            ["Subject|Wildlife|Mammals"]
        )
        XCTAssertEqual(vocabulary.index.entries(in: .subject).count, 4)
        XCTAssertEqual(vocabulary.index.entries(mutuallyExclusiveGroup: "subject-kind").count, 3)
    }

    func testSeparatorInsensitiveMatchingHandlesModelPunctuationVariants() throws {
        var entries = minimalVocabularyEntries()
        entries.append(contentsOf: [
            VocabularyEntry(
                canonicalPath: "Subject|Still Life",
                flatKeyword: "Still Life",
                namespace: .subject,
                parentPath: "Subject",
                synonyms: ["bird photography", "cat eye bokeh"]
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife|Birds|Herons and Egrets",
                flatKeyword: "Herons and Egrets",
                namespace: .subject,
                parentPath: "Subject|Wildlife|Birds",
                synonyms: ["egret"]
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Wildlife|Birds|Wing",
                flatKeyword: "Bird Wing",
                namespace: .subject,
                parentPath: "Subject|Wildlife|Birds",
                synonyms: ["bird wing"]
            ),
            VocabularyEntry(
                canonicalPath: "Subject|Cargo Containers",
                flatKeyword: "Cargo Containers",
                namespace: .subject,
                parentPath: "Subject"
            )
        ])
        let vocabulary = try VocabularyLoader.load(
            data: vocabularyData(entries: entries),
            sourcePath: "memory://separator-index.json"
        )

        XCTAssertEqual(vocabulary.index.entry(matching: "still_life")?.canonicalPath, "Subject|Still Life")
        XCTAssertEqual(vocabulary.index.entry(matching: "still-life")?.canonicalPath, "Subject|Still Life")
        XCTAssertEqual(vocabulary.index.entry(matching: "bird_photography")?.canonicalPath, "Subject|Still Life")
        XCTAssertEqual(vocabulary.index.entry(matching: "cat\u{2011}eye bokeh")?.canonicalPath, "Subject|Still Life")
        XCTAssertEqual(
            vocabulary.index.entry(matching: "Herons & Egrets")?.canonicalPath,
            "Subject|Wildlife|Birds|Herons and Egrets"
        )
        XCTAssertEqual(
            vocabulary.index.entry(matching: "egrets")?.canonicalPath,
            "Subject|Wildlife|Birds|Herons and Egrets"
        )
        XCTAssertEqual(vocabulary.index.entry(matching: "cargo_container")?.canonicalPath, "Subject|Cargo Containers")
        XCTAssertEqual(vocabulary.index.entry(matching: "bird's wing")?.canonicalPath, "Subject|Wildlife|Birds|Wing")
        XCTAssertEqual(vocabulary.index.entry(matching: "bird\u{2019}s wing")?.canonicalPath, "Subject|Wildlife|Birds|Wing")
    }

    func testSeparatorInsensitiveFallbackDoesNotResolveAmbiguousAliases() throws {
        let entries = [
            VocabularyEntry(
                canonicalPath: "Subject",
                flatKeyword: "Subject",
                namespace: .subject,
                parentPath: nil,
                synonyms: [],
                requiresReview: false,
                autoApplyAllowed: false,
                directApplyPolicy: .withhold,
                propagationScope: PropagationScope.none,
                specificity: .broad
            ),
            VocabularyEntry(
                canonicalPath: "Subject|A-B",
                flatKeyword: "A-B",
                namespace: .subject,
                parentPath: "Subject"
            ),
            VocabularyEntry(
                canonicalPath: "Subject|A B",
                flatKeyword: "A B",
                namespace: .subject,
                parentPath: "Subject"
            )
        ]
        let vocabulary = try VocabularyLoader.load(
            data: vocabularyData(entries: entries),
            sourcePath: "memory://separator-ambiguity.json"
        )

        XCTAssertEqual(vocabulary.index.entry(matching: "A-B")?.canonicalPath, "Subject|A-B")
        XCTAssertEqual(vocabulary.index.entry(matching: "A B")?.canonicalPath, "Subject|A B")
        XCTAssertNil(vocabulary.index.entry(matching: "A_B"))
    }
}
