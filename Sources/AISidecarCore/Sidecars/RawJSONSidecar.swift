import Foundation

/// Encodes an intentionally empty JSON object.
///
/// Sidecars use this for schema slots that were not exercised in a given run,
/// preserving an object-shaped field without inventing placeholder values.
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

/// Per-file pipeline timing recorded in Phase 1 raw sidecars.
///
/// Values are wall-clock milliseconds measured by the analyze pipeline. The
/// model timing here is the aggregate local pipeline wait for model calls;
/// runtime-supplied Ollama counters live on each `model_runs` record.
public struct PipelineTimingRecord: Codable, Sendable, Equatable {
    public var pipelineElapsedMs: Int
    public var renderMs: Int
    public var subjectIsolationMs: Int
    public var modelMs: Int
    public var writeMs: Int

    enum CodingKeys: String, CodingKey {
        case pipelineElapsedMs = "pipeline_elapsed_ms"
        case renderMs = "render_ms"
        case subjectIsolationMs = "subject_isolation_ms"
        case modelMs = "model_ms"
        case writeMs = "write_ms"
    }

    public init(
        pipelineElapsedMs: Int,
        renderMs: Int,
        subjectIsolationMs: Int,
        modelMs: Int,
        writeMs: Int
    ) {
        self.pipelineElapsedMs = pipelineElapsedMs
        self.renderMs = renderMs
        self.subjectIsolationMs = subjectIsolationMs
        self.modelMs = modelMs
        self.writeMs = writeMs
    }
}

/// Phase 1 raw JSON sidecar record.
public struct RawJSONSidecar: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var source: SourceImage
    public var runConfiguration: ResolvedRunConfiguration
    public var modelInputProfile: ModelInputProfile
    public var derivatives: [DerivativeRecord]
    public var subjectIsolation: SubjectIsolationRecord?
    public var modelRuns: [ModelRunRecord]
    public var errors: [SidecarError]
    public var timing: PipelineTimingRecord?
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
        case timing
        case createdAt = "created_at"
    }

    public init(
        schemaVersion: String = "ai-sidecar-json/1.1",
        source: SourceImage,
        runConfiguration: ResolvedRunConfiguration,
        modelInputProfile: ModelInputProfile = .defaultProfile,
        derivatives: [DerivativeRecord] = [],
        subjectIsolation: SubjectIsolationRecord? = nil,
        modelRuns: [ModelRunRecord] = [],
        errors: [SidecarError] = [],
        timing: PipelineTimingRecord? = nil,
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
        self.timing = timing
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        self.source = try container.decode(SourceImage.self, forKey: .source)
        self.runConfiguration = try container.decode(ResolvedRunConfiguration.self, forKey: .runConfiguration)
        self.modelInputProfile = try container.decode(ModelInputProfile.self, forKey: .modelInputProfile)
        self.derivatives = try container.decode([DerivativeRecord].self, forKey: .derivatives)
        self.subjectIsolation = try? container.decode(SubjectIsolationRecord.self, forKey: .subjectIsolation)
        self.modelRuns = try container.decode([ModelRunRecord].self, forKey: .modelRuns)
        self.errors = try container.decode([SidecarError].self, forKey: .errors)
        self.timing = try container.decodeIfPresent(PipelineTimingRecord.self, forKey: .timing)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(source, forKey: .source)
        try container.encode(runConfiguration, forKey: .runConfiguration)
        try container.encode(modelInputProfile, forKey: .modelInputProfile)
        try container.encode(derivatives, forKey: .derivatives)
        if let subjectIsolation {
        try container.encode(subjectIsolation, forKey: .subjectIsolation)
        } else {
            try container.encode(EmptyJSONObject(), forKey: .subjectIsolation)
        }
        try container.encode(modelRuns, forKey: .modelRuns)
        try container.encode(errors, forKey: .errors)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
