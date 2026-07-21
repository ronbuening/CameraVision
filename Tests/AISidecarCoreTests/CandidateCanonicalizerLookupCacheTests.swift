import XCTest

@testable import AISidecarCore

final class CandidateCanonicalizerLookupCacheTests: XCTestCase {
    func testRepeatedFoldAndVocabularyLookupHitsUseOneUnderlyingOperation() throws {
        var foldCalls = 0
        var lookupCalls = 0
        let entry = ResolvedVocabularyEntry(
            canonicalPath: "Subject|Wildlife|Birds",
            flatKeyword: "Birds",
            namespace: .subject,
            parentPath: "Subject|Wildlife",
            synonyms: [],
            requiresReview: false,
            autoApplyAllowed: true,
            directApplyPolicy: .allow,
            mutuallyExclusiveGroup: nil,
            exportFlatKeyword: true,
            exportHierarchicalKeyword: true,
            propagationScope: .global,
            specificity: .broad,
            notes: nil
        )
        let cache = CandidateCanonicalizerLookupCache(
            foldText: { text in
                foldCalls += 1
                return text.lowercased()
            },
            lookupEntry: { text in
                lookupCalls += 1
                return text == "bird" ? entry : nil
            }
        )

        XCTAssertEqual(cache.fold("Bird"), "bird")
        XCTAssertEqual(cache.fold("Bird"), "bird")
        XCTAssertEqual(cache.entry(matching: "bird"), entry)
        XCTAssertEqual(cache.entry(matching: "bird"), entry)
        XCTAssertNil(cache.entry(matching: "unknown"))
        XCTAssertNil(cache.entry(matching: "unknown"))

        XCTAssertEqual(foldCalls, 1)
        XCTAssertEqual(lookupCalls, 2, "Both matching entries and misses are cached by input text.")
    }
}
