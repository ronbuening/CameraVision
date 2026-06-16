import Foundation
import XCTest
@testable import AISidecarCore

func vocabularyData(
    entries: [VocabularyEntry],
    schemaVersion: String = NormalizationSchemaIdentifiers.vocabulary
) throws -> Data {
    let document = VocabularyDocument(schemaVersion: schemaVersion, entries: entries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

func minimalVocabularyEntries() -> [VocabularyEntry] {
    [
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
            canonicalPath: "Subject|Wildlife",
            flatKeyword: "Wildlife",
            namespace: .subject,
            parentPath: "Subject",
            synonyms: ["wild animal"],
            mutuallyExclusiveGroup: "subject-kind"
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Wildlife|Birds",
            flatKeyword: "Birds",
            namespace: .subject,
            parentPath: "Subject|Wildlife",
            synonyms: ["bird", "avian"],
            mutuallyExclusiveGroup: "subject-kind"
        ),
        VocabularyEntry(
            canonicalPath: "Subject|Wildlife|Mammals",
            flatKeyword: "Mammals",
            namespace: .subject,
            parentPath: "Subject|Wildlife",
            synonyms: ["mammal"],
            mutuallyExclusiveGroup: "subject-kind"
        )
    ]
}

func assertVocabularyInvalid(
    _ operation: () throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try operation()
        XCTFail("Expected E_VOCABULARY_INVALID", file: file, line: line)
    } catch let error as SidecarError {
        XCTAssertEqual(error.code, .vocabularyInvalid, file: file, line: line)
        XCTAssertEqual(error.stage, .normalize, file: file, line: line)
        XCTAssertFalse(error.recoverable, file: file, line: line)
    } catch {
        XCTFail("Expected SidecarError, got \(error)", file: file, line: line)
    }
}
