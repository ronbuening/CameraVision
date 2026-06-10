import Foundation

/// Requested analysis input roles for Phase 1.
public enum AnalysisMode: String, Codable, CaseIterable, Sendable {
    case whole
    case subject
    case both
}

/// Policy for destinations that already contain an output artifact.
public enum ExistingPolicy: String, Codable, CaseIterable, Sendable {
    case skip
    case overwrite
    case fail
}

/// Logging severity used by both human-readable and JSON log records.
public enum LogLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case error
    case warn
    case info
    case debug

    private var sortOrder: Int {
        switch self {
        case .error: 0
        case .warn: 1
        case .info: 2
        case .debug: 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Output encoding for CLI logs.
public enum LogFormat: String, Codable, CaseIterable, Sendable {
    case text
    case json
}

/// Optional values supplied by the CLI or environment before precedence is resolved.
///
/// `nil` means "no override"; it does not mean a falsey value. This distinction
/// preserves the configured default chain from PW-007.
public struct RunConfigurationOverrides: Sendable, Equatable {
    public var mode: AnalysisMode?
    public var existing: ExistingPolicy?
    public var recursive: Bool?
    public var outputDir: String?
    public var model: String?
    public var modelEndpoint: String?
    public var profile: String?
    public var configPath: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var debugDerivatives: Bool?
    public var sourceIdentityPolicy: SourceIdentityPolicy?
    public var derivativeCacheDir: String?
    public var derivativeCacheSizeBytes: Int64?

    public init(
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        recursive: Bool? = nil,
        outputDir: String? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        profile: String? = nil,
        configPath: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        debugDerivatives: Bool? = nil,
        sourceIdentityPolicy: SourceIdentityPolicy? = nil,
        derivativeCacheDir: String? = nil,
        derivativeCacheSizeBytes: Int64? = nil
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.profile = profile
        self.configPath = configPath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.debugDerivatives = debugDerivatives
        self.sourceIdentityPolicy = sourceIdentityPolicy
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
    }
}

/// Fully resolved run configuration recorded in provenance.
///
/// Values here have already followed the precedence chain
/// CLI > environment > JSON config > built-in default.
public struct ResolvedRunConfiguration: Codable, Sendable, Equatable {
    public var mode: AnalysisMode
    public var existing: ExistingPolicy
    public var recursive: Bool
    public var outputDir: String?
    public var model: String
    public var modelEndpoint: URL
    public var profile: String
    public var logLevel: LogLevel
    public var logFormat: LogFormat
    public var dryRun: Bool
    public var debugDerivatives: Bool
    public var sourceIdentityPolicy: SourceIdentityPolicy
    public var derivativeCacheDir: String
    public var derivativeCacheSizeBytes: Int64

    enum CodingKeys: String, CodingKey {
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
        case derivativeCacheDir = "derivative_cache_dir"
        case derivativeCacheSizeBytes = "derivative_cache_size_bytes"
    }

    public init(
        mode: AnalysisMode,
        existing: ExistingPolicy,
        recursive: Bool,
        outputDir: String?,
        model: String,
        modelEndpoint: URL,
        profile: String,
        logLevel: LogLevel,
        logFormat: LogFormat,
        dryRun: Bool,
        debugDerivatives: Bool,
        sourceIdentityPolicy: SourceIdentityPolicy,
        derivativeCacheDir: String = DerivativeCache.defaultDirectoryPath(),
        derivativeCacheSizeBytes: Int64 = DerivativeCache.defaultSizeCapBytes
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
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
    }

    public static let builtInDefaults = ResolvedRunConfiguration(
        mode: .both,
        existing: .skip,
        recursive: false,
        outputDir: nil,
        model: "gemma4:26b-a4b-it-qat",
        modelEndpoint: URL(string: "http://localhost:11434")!,
        profile: "gemma4-26b-default",
        logLevel: .info,
        logFormat: .text,
        dryRun: false,
        debugDerivatives: false,
        sourceIdentityPolicy: .sha256,
        derivativeCacheDir: DerivativeCache.defaultDirectoryPath(),
        derivativeCacheSizeBytes: DerivativeCache.defaultSizeCapBytes
    )
}
