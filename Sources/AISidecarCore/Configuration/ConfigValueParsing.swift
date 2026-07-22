extension ConfigurationResolver {
    static func enumValue<T: RawRepresentable>(
        _ type: T.Type,
        from rawValue: String?,
        key: String
    ) throws -> T? where T.RawValue == String {
        guard let rawValue else {
            return nil
        }
        guard let value = T(rawValue: rawValue) else {
            throw SidecarError.configInvalid("Invalid value for \(key): \(rawValue)")
        }
        return value
    }

    static func boolValue(from rawValue: String?, key: String) throws -> Bool? {
        guard let rawValue else {
            return nil
        }
        switch rawValue.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw SidecarError.configInvalid("Invalid boolean value for \(key): \(rawValue)")
        }
    }

    static func int64Value(from rawValue: String?, key: String) throws -> Int64? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int64(rawValue), value > 0 else {
            throw SidecarError.configInvalid("Invalid positive integer value for \(key): \(rawValue)")
        }
        return value
    }

    static func intValue(from rawValue: String?, key: String) throws -> Int? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int(rawValue), value > 0 else {
            throw SidecarError.configInvalid("Invalid positive integer value for \(key): \(rawValue)")
        }
        return value
    }

    static func nonNegativeIntValue(from rawValue: String?, key: String) throws -> Int? {
        guard let rawValue else {
            return nil
        }
        guard let value = Int(rawValue), value >= 0 else {
            throw SidecarError.configInvalid("Invalid non-negative integer value for \(key): \(rawValue)")
        }
        return value
    }

    static func doubleValue(from rawValue: String?, key: String) throws -> Double? {
        guard let rawValue else {
            return nil
        }
        guard let value = Double(rawValue), value.isFinite else {
            throw SidecarError.configInvalid("Invalid finite decimal value for \(key): \(rawValue)")
        }
        return value
    }
}

/// Overlay an optional candidate onto a required builder field, leaving it unchanged when the
/// candidate is nil. Centralizes the config/override precedence step so each field is one explicit
/// `merge` instead of a repeated `if let value = source.field { field = value }` block.
func merge<Value>(_ destination: inout Value, _ candidate: Value?) {
    if let candidate {
        destination = candidate
    }
}

/// Overlay onto an optional destination field, preserving the same "skip when the candidate is
/// absent" semantics (a nil candidate never clears an existing value).
func merge<Value>(_ destination: inout Value?, _ candidate: Value?) {
    if let candidate {
        destination = candidate
    }
}
