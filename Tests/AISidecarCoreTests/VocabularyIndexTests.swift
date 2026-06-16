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
}
