import Foundation

/// Reduces a response schema to the subset Ollama's structured-output grammar
/// conversion actually supports before it is sent through `/api/chat` `format`.
///
/// Probing Ollama 0.30.10 with gemma4 vision showed the converter silently
/// falls back to unconstrained JSON when the schema contains `$ref`/`$defs`
/// or `pattern` — the model then emits bare-string arrays, missing required
/// keys, and repetition loops. Inlining every `$ref` and stripping the
/// unsupported keywords restores token-level enforcement of `required`,
/// `enum`, `additionalProperties: false`, array `minItems`/`maxItems`, and
/// string `minLength`/`maxLength` (which also stops in-string repetition
/// loops at the length bound).
///
/// The authoritative bundled schema is unchanged: `JSONSchemaValidator` still
/// validates responses against the full contract (patterns included), and
/// sidecars record the authoritative schema version. This transform shapes
/// only the wire request.
public enum OllamaWireSchema {
    /// Keywords that break or bloat the grammar conversion; their absence
    /// from the wire schema never loosens the local validation contract.
    private static let unsupportedKeys: Set<String> = [
        "$schema",
        "$id",
        "title",
        "description",
        "pattern",
    ]

    /// Return the grammar-safe wire form of an authoritative response schema.
    public static func wireSchema(from schema: JSONValue) -> JSONValue {
        let definitions = schema.objectValue?["$defs"]?.objectValue ?? [:]
        return transform(schema, definitions: definitions, depth: 0)
    }

    private static func transform(_ node: JSONValue, definitions: [String: JSONValue], depth: Int) -> JSONValue {
        // The bundled schemas nest three levels ($defs -> candidate -> field);
        // the depth cap only guards against a future accidental $ref cycle.
        guard depth < 32 else {
            return node
        }
        switch node {
        case .object(let object):
            if let reference = object["$ref"]?.stringValue {
                let name = reference.split(separator: "/").last.map(String.init) ?? reference
                guard let resolved = definitions[name] else {
                    return node
                }
                return transform(resolved, definitions: definitions, depth: depth + 1)
            }
            var transformed: [String: JSONValue] = [:]
            for (key, value) in object where key != "$defs" && !unsupportedKeys.contains(key) {
                transformed[key] = transform(value, definitions: definitions, depth: depth + 1)
            }
            return .object(transformed)
        case .array(let array):
            return .array(array.map { transform($0, definitions: definitions, depth: depth + 1) })
        case .string, .number, .bool, .null:
            return node
        }
    }
}
