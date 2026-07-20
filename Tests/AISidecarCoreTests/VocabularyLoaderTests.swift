import XCTest

@testable import AISidecarCore

final class VocabularyLoaderTests: XCTestCase {
    func testLoadsExplicitVocabularyAndReportsStableHash() throws {
        let data = try vocabularyData(entries: minimalVocabularyEntries())
        let loaded = try VocabularyLoader.load(data: data, sourcePath: "memory://valid.json")

        XCTAssertEqual(loaded.identity.path, "memory://valid.json")
        XCTAssertEqual(loaded.identity.schemaVersion, NormalizationSchemaIdentifiers.vocabulary)
        XCTAssertEqual(loaded.identity.sha256.count, 64)
        XCTAssertEqual(loaded.entries.count, 4)
    }

    func testLoadsFixtureVocabularyByPath() throws {
        let url = try fixtureURL(named: "valid-minimal-vocabulary")
        let loaded = try VocabularyLoader.load(at: url.path)

        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.index.entry(matching: "wild animal")?.canonicalPath, "Subject|Wildlife")
    }

    func testMissingExplicitPathFailsAsVocabularyInvalid() {
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(at: "/tmp/does-not-exist-\(UUID().uuidString).json")
        }
    }

    func testNonJSONVocabularyPathFailsAsVocabularyInvalid() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("vocabulary.yaml")
        try Data("{}".utf8).write(to: file)

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(at: file.path)
        }
    }

    func testSchemaValidationFailureIsVocabularyInvalid() {
        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(
                data: Data(#"{ "schema_version": "wrong", "entries": [] }"#.utf8), sourcePath: "memory://bad.json")
        }
    }

    func testInvalidVocabularyFixtureFails() throws {
        let url = try fixtureURL(named: "invalid-duplicate-synonym")

        assertVocabularyInvalid {
            _ = try VocabularyLoader.load(at: url.path)
        }
    }

    private func fixtureURL(named name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "vocabularies")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
    }
}
