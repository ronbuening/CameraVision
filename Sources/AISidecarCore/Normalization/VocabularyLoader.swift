import CryptoKit
import Foundation

/// Loads explicit and bundled Phase 3 vocabulary JSON through one validation path.
public enum VocabularyLoader {
    public static func load(at path: String) throws -> LoadedVocabulary {
        let lowercasedPath = path.lowercased()
        guard lowercasedPath.hasSuffix(".json") else {
            throw vocabularyInvalid("Vocabulary must be a JSON file: \(path)")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw vocabularyInvalid("Vocabulary file does not exist: \(path)")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try load(data: data, sourcePath: path)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw vocabularyInvalid("Unable to read vocabulary file \(path): \(error.localizedDescription)")
        }
    }

    public static func loadDefault() throws -> LoadedVocabulary {
        guard let url = resourceURL(name: "default-vocabulary", extension: "json", subdirectory: "Vocabularies") else {
            throw vocabularyInvalid("Missing bundled default vocabulary resource.")
        }
        do {
            let data = try Data(contentsOf: url)
            return try load(data: data, sourcePath: "bundle://Vocabularies/default-vocabulary.json")
        } catch let error as SidecarError {
            throw error
        } catch {
            throw vocabularyInvalid("Unable to read bundled default vocabulary: \(error.localizedDescription)")
        }
    }

    public static func load(data: Data, sourcePath: String) throws -> LoadedVocabulary {
        do {
            try validateJSONSchema(data)
            let document = try JSONDecoder().decode(VocabularyDocument.self, from: data)
            let resolvedEntries = try VocabularyValidator.validate(document)
            let identity = VocabularyIdentity(
                path: sourcePath,
                sha256: sha256(data),
                schemaVersion: document.schemaVersion
            )
            return LoadedVocabulary(
                identity: identity,
                document: document,
                entries: resolvedEntries,
                index: VocabularyIndex(entries: resolvedEntries)
            )
        } catch let error as SidecarError {
            throw error
        } catch let error as JSONSchemaValidationError {
            throw vocabularyInvalid("Vocabulary schema validation failed at \(error.path): \(error.message)")
        } catch {
            throw vocabularyInvalid("Invalid vocabulary JSON \(sourcePath): \(error.localizedDescription)")
        }
    }

    private static func validateJSONSchema(_ data: Data) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let schemaURL = resourceURL(
            name: "ai-sidecar-vocabulary-1.0.schema",
            extension: "json",
            subdirectory: "Schemas"
        ) else {
            throw vocabularyInvalid("Missing bundled vocabulary JSON Schema resource.")
        }
        let schemaData = try Data(contentsOf: schemaURL)
        let schemaValue = try JSONDecoder().decode(JSONValue.self, from: schemaData)
        let schema = JSONSchemaDocument(version: NormalizationSchemaIdentifiers.vocabulary, schema: schemaValue)
        try JSONSchemaValidator.validate(value, against: schema)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func resourceURL(name: String, extension fileExtension: String, subdirectory: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}

/// Access point for the bundled conservative starter vocabulary.
public enum DefaultVocabulary {
    public static func load() throws -> LoadedVocabulary {
        try VocabularyLoader.loadDefault()
    }
}
