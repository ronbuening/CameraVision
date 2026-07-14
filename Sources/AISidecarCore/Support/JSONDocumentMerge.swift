import Foundation

/// Merges a typed rewrite into its source JSON while retaining additive fields
/// the current schema does not model (PW-012).
enum JSONDocumentMerge {
    /// Keys the current schema owns at a node, addressed by the object-key path
    /// from the document root (array elements do not extend the path). Owned
    /// keys follow the replacement — including intentional absence, so a field
    /// the writer cleared is not resurrected — while unowned keys are preserved.
    typealias OwnedKeys = (_ path: [String]) -> Set<String>

    static func preservingUnknowns(
        original: JSONValue,
        replacement: JSONValue,
        ownedKeys: OwnedKeys = { _ in [] }
    ) -> JSONValue {
        merge(original: original, replacement: replacement, path: [], ownedKeys: ownedKeys)
    }

    private static func merge(
        original: JSONValue,
        replacement: JSONValue,
        path: [String],
        ownedKeys: OwnedKeys
    ) -> JSONValue {
        switch (original, replacement) {
        case (.object(let originalObject), .object(let replacementObject)):
            var merged = originalObject
            let owned = ownedKeys(path)
            if !owned.isEmpty {
                for key in originalObject.keys
                where owned.contains(key) && replacementObject[key] == nil {
                    merged.removeValue(forKey: key)
                }
            }
            for (key, value) in replacementObject {
                if let originalValue = originalObject[key] {
                    merged[key] = merge(
                        original: originalValue,
                        replacement: value,
                        path: path + [key],
                        ownedKeys: ownedKeys
                    )
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
                return merge(
                    original: originalArray[index],
                    replacement: value,
                    path: path,
                    ownedKeys: ownedKeys
                )
            }
            return .array(values)
        default:
            return replacement
        }
    }
}
