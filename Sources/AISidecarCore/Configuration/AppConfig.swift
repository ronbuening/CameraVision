import Foundation

/// JSON-backed persistent defaults loaded before environment and CLI overrides.
public struct AppConfig: Codable, Sendable, Equatable {
    public var mode: AnalysisMode?
    public var existing: ExistingPolicy?
    public var recursive: Bool?
    public var outputDir: String?
    public var model: String?
    public var modelEndpoint: String?
    public var profile: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var debugDerivatives: Bool?
    public var sourceIdentityPolicy: SourceIdentityPolicy?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode
        case existing
        case recursive
        case outputDir = "output_dir"
        case model
        case modelEndpoint = "model_endpoint"
        case profile
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case debugDerivatives = "debug_derivatives"
        case sourceIdentityPolicy = "source_identity_policy"
    }

    public init(
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        recursive: Bool? = nil,
        outputDir: String? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        profile: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        debugDerivatives: Bool? = nil,
        sourceIdentityPolicy: SourceIdentityPolicy? = nil
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.profile = profile
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.debugDerivatives = debugDerivatives
        self.sourceIdentityPolicy = sourceIdentityPolicy
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let unknownKeys = allKeys.allKeys
            .map(\.stringValue)
            .filter { !allowedKeys.contains($0) }
            .sorted()
        // Unknown keys are rejected so typos in persistent defaults cannot
        // silently change later batch behavior.
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown config keys: \(unknownKeys.joined(separator: ", "))"
                )
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(AnalysisMode.self, forKey: .mode)
        self.existing = try container.decodeIfPresent(ExistingPolicy.self, forKey: .existing)
        self.recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive)
        self.outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelEndpoint = try container.decodeIfPresent(String.self, forKey: .modelEndpoint)
        self.profile = try container.decodeIfPresent(String.self, forKey: .profile)
        self.logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel)
        self.logFormat = try container.decodeIfPresent(LogFormat.self, forKey: .logFormat)
        self.dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun)
        self.debugDerivatives = try container.decodeIfPresent(Bool.self, forKey: .debugDerivatives)
        self.sourceIdentityPolicy = try container.decodeIfPresent(
            SourceIdentityPolicy.self,
            forKey: .sourceIdentityPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(existing, forKey: .existing)
        try container.encodeIfPresent(recursive, forKey: .recursive)
        try container.encodeIfPresent(outputDir, forKey: .outputDir)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(modelEndpoint, forKey: .modelEndpoint)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(logLevel, forKey: .logLevel)
        try container.encodeIfPresent(logFormat, forKey: .logFormat)
        try container.encodeIfPresent(dryRun, forKey: .dryRun)
        try container.encodeIfPresent(debugDerivatives, forKey: .debugDerivatives)
        try container.encodeIfPresent(sourceIdentityPolicy, forKey: .sourceIdentityPolicy)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
