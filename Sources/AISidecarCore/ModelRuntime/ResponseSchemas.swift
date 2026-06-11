import Foundation

/// Loads the JSON Schema contracts sent to Ollama's structured-output `format` field.
public enum ResponseSchemas {
    /// Return the response schema for the requested model-input role.
    public static func schema(for role: ModelInputRole) throws -> JSONSchemaDocument {
        let schema = try resourceSchema(named: resourceName(for: role))
        let version = try schemaID(from: schema, resourceName: resourceName(for: role))
        return JSONSchemaDocument(version: version, schema: schema)
    }

    private static func resourceName(for role: ModelInputRole) -> String {
        switch role {
        case .wholeImage:
            return "whole_image_v1.3.0"
        case .subjectIsolated:
            return "subject_isolated_v1.3.0"
        }
    }

    private static func resourceSchema(named resourceName: String) throws -> JSONValue {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw resourceError("Missing bundled response schema resource: \(resourceName).json")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        } catch {
            throw resourceError("Response schema resource is malformed JSON: \(resourceName).json")
        }
    }

    private static func schemaID(from schema: JSONValue, resourceName: String) throws -> String {
        guard let id = schema.objectValue?["$id"]?.stringValue, !id.isEmpty else {
            throw resourceError("Response schema resource is missing non-empty $id: \(resourceName).json")
        }
        return id
    }
}

private func resourceError(_ message: String) -> SidecarError {
    SidecarError(code: .validationFailed, stage: .model, message: message, recoverable: false)
}
