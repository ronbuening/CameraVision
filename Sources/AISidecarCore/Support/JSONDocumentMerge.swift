import Foundation

/// Merges a typed rewrite into its source JSON while retaining additive fields
/// the current schema does not model (PW-012).
enum JSONDocumentMerge {
    static func preservingUnknowns(original: JSONValue, replacement: JSONValue) -> JSONValue {
        switch (original, replacement) {
        case (.object(let originalObject), .object(let replacementObject)):
            var merged = originalObject
            for (key, value) in replacementObject {
                if let originalValue = originalObject[key] {
                    merged[key] = preservingUnknowns(original: originalValue, replacement: value)
                } else {
                    merged[key] = value
                }
            }
            return .object(merged)
        case (.array(let originalArray), .array(let replacementArray)):
            let values = replacementArray.enumerated().map { index, value in
                guard originalArray.indices.contains(index) else {
                    return value
                }
                return preservingUnknowns(original: originalArray[index], replacement: value)
            }
            return .array(values)
        default:
            return replacement
        }
    }
}
