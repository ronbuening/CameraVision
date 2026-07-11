import Foundation

/// CORE-9 (Phase 4 Settings, FR4-056): read-modify-write editor for the
/// shared `config.json`.
///
/// Edits go over the generic JSON object so keys this build does not know
/// about — hand-added fields, newer-version settings — survive untouched.
/// The file is created (with its directory) when missing, and written
/// atomically. Precedence is unchanged: environment variables and CLI flags
/// still override whatever is written here (invariant 9).
public enum ConfigFileEditor {
    /// Merge `changes` into the config file at `path`. A `nil` value removes
    /// the key. Throws if the existing file is not a JSON object.
    public static func merge(
        _ changes: [String: JSONValue?],
        atPath path: String,
        fileManager: FileManager = .default
    ) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        var object: [String: Any] = [:]
        if fileManager.fileExists(atPath: url.path) {
            guard let data = fileManager.contents(atPath: url.path) else {
                throw SidecarError.configInvalid("Config file exists but cannot be read: \(url.path)")
            }
            do {
                guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw SidecarError.configInvalid("Config file is not a JSON object: \(url.path)")
                }
                object = existing
            } catch let error as SidecarError {
                throw error
            } catch {
                throw SidecarError.configInvalid(
                    "Config file contains malformed JSON: \(url.path): \(error.localizedDescription)"
                )
            }
        }

        for (key, value) in changes {
            if let value {
                object[key] = foundationValue(value)
            } else {
                object.removeValue(forKey: key)
            }
        }

        let output = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try AtomicFileWriter.write(output, to: url, fileManager: fileManager)
    }

    private static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case .object(let dictionary):
            return dictionary.mapValues(foundationValue)
        case .array(let array):
            return array.map(foundationValue)
        case .string(let string):
            return string
        case .number(let number):
            if number.isFinite,
               number.rounded() == number,
               number >= Double(Int.min),
               number <= Double(Int.max) {
                return Int(number)
            }
            return number
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        }
    }
}
