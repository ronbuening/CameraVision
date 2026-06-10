import Foundation

/// Encodes an intentionally empty JSON object.
///
/// Milestone 2 sidecars must reserve object slots for later provenance without
/// inventing placeholder fields before rendering or model runtime exist.
public struct EmptyJSONObject: Codable, Sendable, Equatable {
    public init() {}

    public init(from decoder: Decoder) throws {
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
    }

    public func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }
}

private struct EmptyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// Minimal Phase 1 raw JSON sidecar shell.
///
/// Milestone 2 writes the durable artifact before rendering and model runtime
/// exist, so model and derivative arrays remain empty by construction.
public struct RawJSONSidecar: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var source: SourceImage
    public var runConfiguration: ResolvedRunConfiguration
    public var modelInputProfile: EmptyJSONObject
    public var derivatives: [EmptyJSONObject]
    public var subjectIsolation: EmptyJSONObject
    public var modelRuns: [EmptyJSONObject]
    public var errors: [SidecarError]
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source
        case runConfiguration = "run_configuration"
        case modelInputProfile = "model_input_profile"
        case derivatives
        case subjectIsolation = "subject_isolation"
        case modelRuns = "model_runs"
        case errors
        case createdAt = "created_at"
    }

    public init(
        schemaVersion: String = "ai-sidecar-json/1.0",
        source: SourceImage,
        runConfiguration: ResolvedRunConfiguration,
        modelInputProfile: EmptyJSONObject = EmptyJSONObject(),
        derivatives: [EmptyJSONObject] = [],
        subjectIsolation: EmptyJSONObject = EmptyJSONObject(),
        modelRuns: [EmptyJSONObject] = [],
        errors: [SidecarError] = [],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.runConfiguration = runConfiguration
        self.modelInputProfile = modelInputProfile
        self.derivatives = derivatives
        self.subjectIsolation = subjectIsolation
        self.modelRuns = modelRuns
        self.errors = errors
        self.createdAt = createdAt
    }
}
