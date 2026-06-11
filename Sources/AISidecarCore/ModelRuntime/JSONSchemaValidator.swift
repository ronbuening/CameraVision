import Foundation

/// Error raised when parsed model JSON does not satisfy the response schema.
public struct JSONSchemaValidationError: Error, Sendable, Equatable, LocalizedError {
    public var path: String
    public var message: String

    public var errorDescription: String? {
        "\(path): \(message)"
    }

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Minimal JSON Schema validator for the response-schema subset Phase 1 sends to Ollama.
///
/// This intentionally validates only the keywords the project owns in
/// FR1-045. A narrow validator keeps tests offline and avoids importing a
/// general-purpose schema engine for a model-output contract we control.
public enum JSONSchemaValidator {
    /// Validate a JSON value against a schema document.
    public static func validate(_ value: JSONValue, against document: JSONSchemaDocument) throws {
        try validate(value, schema: document.schema, path: "$")
    }

    private static func validate(_ value: JSONValue, schema: JSONValue, path: String) throws {
        guard let schemaObject = schema.objectValue else {
            throw JSONSchemaValidationError(path: path, message: "Schema must be a JSON object.")
        }

        try validateType(value, schemaObject: schemaObject, path: path)
        try validateEnum(value, schemaObject: schemaObject, path: path)

        switch value {
        case .object(let object):
            try validateObject(object, schemaObject: schemaObject, path: path)
        case .array(let array):
            try validateArray(array, schemaObject: schemaObject, path: path)
        case .string(let string):
            try validateString(string, schemaObject: schemaObject, path: path)
        case .number, .bool, .null:
            break
        }
    }

    private static func validateType(
        _ value: JSONValue,
        schemaObject: [String: JSONValue],
        path: String
    ) throws {
        guard let typeValue = schemaObject["type"] else {
            return
        }
        let allowedTypes: [String]
        if let string = typeValue.stringValue {
            allowedTypes = [string]
        } else if let array = typeValue.arrayValue {
            allowedTypes = array.compactMap(\.stringValue)
        } else {
            throw JSONSchemaValidationError(path: path, message: "`type` must be a string or string array.")
        }

        guard allowedTypes.contains(where: { matches(value, type: $0) }) else {
            throw JSONSchemaValidationError(
                path: path,
                message: "Expected \(allowedTypes.joined(separator: " or ")), found \(typeName(for: value))."
            )
        }
    }

    private static func validateEnum(
        _ value: JSONValue,
        schemaObject: [String: JSONValue],
        path: String
    ) throws {
        guard let cases = schemaObject["enum"]?.arrayValue else {
            return
        }
        guard cases.contains(value) else {
            throw JSONSchemaValidationError(path: path, message: "Value is not one of the allowed enum cases.")
        }
    }

    private static func validateObject(
        _ object: [String: JSONValue],
        schemaObject: [String: JSONValue],
        path: String
    ) throws {
        if let required = schemaObject["required"]?.arrayValue?.compactMap(\.stringValue) {
            for key in required where object[key] == nil {
                throw JSONSchemaValidationError(path: "\(path).\(key)", message: "Required property is missing.")
            }
        }

        let properties = schemaObject["properties"]?.objectValue ?? [:]
        for (key, propertySchema) in properties {
            if let propertyValue = object[key] {
                try validate(propertyValue, schema: propertySchema, path: "\(path).\(key)")
            }
        }

        let knownKeys = Set(properties.keys)
        let unknownKeys = Set(object.keys).subtracting(knownKeys)
        guard !unknownKeys.isEmpty else {
            return
        }

        switch schemaObject["additionalProperties"] {
        case .some(.bool(false)):
            let first = unknownKeys.sorted()[0]
            throw JSONSchemaValidationError(path: "\(path).\(first)", message: "Additional property is not allowed.")
        case .some(.object(_)):
            let additionalSchema = try unwrap(schemaObject["additionalProperties"], path: path)
            for key in unknownKeys {
                try validate(try unwrap(object[key], path: "\(path).\(key)"), schema: additionalSchema, path: "\(path).\(key)")
            }
        default:
            break
        }
    }

    private static func validateArray(
        _ array: [JSONValue],
        schemaObject: [String: JSONValue],
        path: String
    ) throws {
        if let minItems = integerValue(schemaObject["minItems"]), array.count < minItems {
            throw JSONSchemaValidationError(path: path, message: "Expected at least \(minItems) items.")
        }
        if let maxItems = integerValue(schemaObject["maxItems"]), array.count > maxItems {
            throw JSONSchemaValidationError(path: path, message: "Expected at most \(maxItems) items.")
        }
        if let items = schemaObject["items"] {
            for (index, item) in array.enumerated() {
                try validate(item, schema: items, path: "\(path)[\(index)]")
            }
        }
    }

    private static func validateString(
        _ string: String,
        schemaObject: [String: JSONValue],
        path: String
    ) throws {
        if let minLength = integerValue(schemaObject["minLength"]), string.count < minLength {
            throw JSONSchemaValidationError(path: path, message: "Expected at least \(minLength) characters.")
        }
        if let maxLength = integerValue(schemaObject["maxLength"]), string.count > maxLength {
            throw JSONSchemaValidationError(path: path, message: "Expected at most \(maxLength) characters.")
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (value, type) {
        case (.object, "object"), (.array, "array"), (.string, "string"), (.bool, "boolean"), (.null, "null"):
            return true
        case (.number, "number"):
            return true
        case (.number(let number), "integer"):
            return number.rounded(.towardZero) == number
        default:
            return false
        }
    }

    private static func typeName(for value: JSONValue) -> String {
        switch value {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number(let number):
            return number.rounded(.towardZero) == number ? "integer" : "number"
        case .bool: return "boolean"
        case .null: return "null"
        }
    }

    private static func integerValue(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite else {
            return nil
        }
        return Int(number)
    }

    private static func unwrap(_ value: JSONValue?, path: String) throws -> JSONValue {
        guard let value else {
            throw JSONSchemaValidationError(path: path, message: "Expected schema value.")
        }
        return value
    }
}
