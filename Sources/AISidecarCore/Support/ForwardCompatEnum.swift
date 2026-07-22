import Foundation

/// Retains the encoded string for an enum field that may have been written by a
/// newer schema while exposing a safe value to the current process.
struct ForwardCompatEnum<Value>: Codable, Sendable, Equatable
where Value: RawRepresentable & Sendable & Equatable, Value.RawValue == String {
    private(set) var value: Value?
    private var preservedRawValue: String?
    private(set) var unknownRawValue: String?

    init(_ value: Value) {
        self.value = value
        self.preservedRawValue = nil
        self.unknownRawValue = nil
    }

    init(rawValue: String) {
        if let value = Value(rawValue: rawValue) {
            self.value = value
            self.preservedRawValue = nil
            self.unknownRawValue = nil
        } else {
            self.value = nil
            self.preservedRawValue = rawValue
            self.unknownRawValue = rawValue
        }
    }

    var hasUnknownRawValue: Bool {
        unknownRawValue != nil
    }

    mutating func setValue(_ value: Value?) {
        self.value = value
    }

    mutating func useFallbackForUnknown(_ fallback: Value?) {
        guard hasUnknownRawValue else {
            return
        }
        value = fallback
    }

    mutating func overrideValuePreservingEncodedRaw(_ override: Value?) {
        if preservedRawValue == nil {
            preservedRawValue = value?.rawValue
        }
        value = override
    }

    static func updatingOptional(_ field: Self?, to value: Value?) -> Self? {
        guard var field else {
            return value.map(Self.init)
        }
        field.setValue(value)
        if value == nil, field.preservedRawValue == nil {
            return nil
        }
        return field
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        guard let rawValue = preservedRawValue ?? value?.rawValue else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Forward-compatible enum has no value to encode."
                )
            )
        }
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
