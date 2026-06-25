import XCTest
@testable import AISidecarCore

final class VocabularyValidatorTests: XCTestCase {
    func testRejectsDuplicateCanonicalPath() throws {
        var entries = minimalVocabularyEntries()
        entries.append(entries[1])

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: entries), sourcePath: "memory://duplicate.json")
        }
    }

    func testRejectsDuplicateSynonymAndCanonicalSynonymCollision() throws {
        var duplicateSynonym = minimalVocabularyEntries()
        duplicateSynonym[2].synonyms.append("wild animal")

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: duplicateSynonym), sourcePath: "memory://dupe-syn.json")
        }

        var collision = minimalVocabularyEntries()
        collision[2].synonyms.append("Subject|Wildlife")

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: collision), sourcePath: "memory://collision.json")
        }
    }

    func testRejectsOrphanParentCycleEmptyLevelAndPipeFlatKeyword() throws {
        var orphan = minimalVocabularyEntries()
        orphan[1].parentPath = "Missing"
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: orphan), sourcePath: "memory://orphan.json")
        }

        var cycle = minimalVocabularyEntries()
        cycle[1].parentPath = "Subject|Wildlife|Birds"
        cycle[2].parentPath = "Subject|Wildlife"
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: cycle), sourcePath: "memory://cycle.json")
        }

        var emptyLevel = minimalVocabularyEntries()
        emptyLevel[1].canonicalPath = "Subject||Wildlife"
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: emptyLevel), sourcePath: "memory://empty-level.json")
        }

        var pipeFlat = minimalVocabularyEntries()
        pipeFlat[1].flatKeyword = "Wildlife|Birds"
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: pipeFlat), sourcePath: "memory://pipe-flat.json")
        }
    }

    func testRejectsInvalidEnumAndInvalidGlobalPolicy() {
        let invalidEnum = Data(
            """
            {
              "schema_version": "ai-sidecar-vocabulary/1.0",
              "entries": [
                {
                  "canonical_path": "Subject",
                  "flat_keyword": "Subject",
                  "namespace": "Subject",
                  "parent_path": null,
                  "synonyms": [],
                  "direct_apply_policy": "maybe"
                }
              ]
            }
            """.utf8
        )
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: invalidEnum, sourcePath: "memory://invalid-enum.json")
        }
    }

    func testRejectsGlobalPropagationForNonBroadEntry() throws {
        var entries = minimalVocabularyEntries()
        entries[2].propagationScope = .global
        entries[2].specificity = .mid

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(data: vocabularyData(entries: entries), sourcePath: "memory://global-mid.json")
        }
    }
}
