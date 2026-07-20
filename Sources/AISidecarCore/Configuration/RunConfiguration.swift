import Darwin
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

/// How quality assessment runs when it is enabled.
///
/// `combined` folds the quality_assessment block into the tagging model call —
/// one call per input, but the extra prompt content shifts which tags the
/// model emits. `sequential` runs a second dedicated quality pass that writes
/// `.quality.ai.json` sidecars, so tagging output stays byte-identical to a
/// run without quality assessment at the cost of a second model call.
public enum QualityScanMode: String, Codable, CaseIterable, Sendable {
    case combined
    case sequential
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
    public var qualityAssessment: Bool?
    public var qualityScanMode: QualityScanMode?
    public var outputDir: String?
    public var model: String?
    public var modelEndpoint: String?
    public var modelKeepAlive: String?
    public var modelTimeoutSeconds: Double?
    public var modelRetryLimit: Int?
    public var profile: String?
    public var configPath: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var debugDerivatives: Bool?
    public var sourceIdentityPolicy: SourceIdentityPolicy?
    public var derivativeCacheDir: String?
    public var derivativeCacheSizeBytes: Int64?
    public var clearDerivativeCacheOnStart: Bool?
    public var clearDerivativeCacheAfterSuccess: Bool?
    public var subjectCropMarginFraction: Double?
    public var subjectMergeDominanceThreshold: Double?
    /// Optional override for the bounded render/isolation stage only.
    public var stageConcurrency: Int?
    /// Bounded model-output repair attempts after invalid JSON or schema failure.
    public var modelResponseRepairAttempts: Int?
    /// Controls whether EXIF GPS coordinates are attached to model prompts.
    public var gpsContext: GPSContextMode?
    /// Ollama `num_ctx` token window requested for every model call.
    public var modelContextWindow: Int?
    /// Ollama `num_predict` output-token cap for every model call.
    public var modelMaxResponseTokens: Int?

    public init(
        mode: AnalysisMode? = nil,
        existing: ExistingPolicy? = nil,
        recursive: Bool? = nil,
        qualityAssessment: Bool? = nil,
        qualityScanMode: QualityScanMode? = nil,
        outputDir: String? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        modelKeepAlive: String? = nil,
        modelTimeoutSeconds: Double? = nil,
        modelRetryLimit: Int? = nil,
        profile: String? = nil,
        configPath: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        debugDerivatives: Bool? = nil,
        sourceIdentityPolicy: SourceIdentityPolicy? = nil,
        derivativeCacheDir: String? = nil,
        derivativeCacheSizeBytes: Int64? = nil,
        clearDerivativeCacheOnStart: Bool? = nil,
        clearDerivativeCacheAfterSuccess: Bool? = nil,
        subjectCropMarginFraction: Double? = nil,
        subjectMergeDominanceThreshold: Double? = nil,
        stageConcurrency: Int? = nil,
        modelResponseRepairAttempts: Int? = nil,
        gpsContext: GPSContextMode? = nil,
        modelContextWindow: Int? = nil,
        modelMaxResponseTokens: Int? = nil
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.qualityAssessment = qualityAssessment
        self.qualityScanMode = qualityScanMode
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelKeepAlive = modelKeepAlive
        self.modelTimeoutSeconds = modelTimeoutSeconds
        self.modelRetryLimit = modelRetryLimit
        self.profile = profile
        self.configPath = configPath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.debugDerivatives = debugDerivatives
        self.sourceIdentityPolicy = sourceIdentityPolicy
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
        self.subjectCropMarginFraction = subjectCropMarginFraction
        self.subjectMergeDominanceThreshold = subjectMergeDominanceThreshold
        self.stageConcurrency = stageConcurrency
        self.modelResponseRepairAttempts = modelResponseRepairAttempts
        self.gpsContext = gpsContext
        self.modelContextWindow = modelContextWindow
        self.modelMaxResponseTokens = modelMaxResponseTokens
    }
}

/// Cache-specific values supplied before precedence is resolved.
public struct DerivativeCacheConfigurationOverrides: Sendable, Equatable {
    public var configPath: String?
    public var derivativeCacheDir: String?
    public var derivativeCacheSizeBytes: Int64?

    public init(
        configPath: String? = nil,
        derivativeCacheDir: String? = nil,
        derivativeCacheSizeBytes: Int64? = nil
    ) {
        self.configPath = configPath
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
    }
}

/// Resolved derivative cache settings for maintenance commands.
public struct ResolvedDerivativeCacheConfiguration: Sendable, Equatable {
    public var derivativeCacheDir: String
    public var derivativeCacheSizeBytes: Int64

    public init(
        derivativeCacheDir: String = DerivativeCache.defaultDirectoryPath(),
        derivativeCacheSizeBytes: Int64 = DerivativeCache.defaultSizeCapBytes
    ) {
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
    /// Model prompt/schema contract selected for this run.
    public var taskProfile: ModelTaskProfile
    /// Whether quality assessment shares the tagging call or runs as a second pass.
    public var qualityScanMode: QualityScanMode
    public var outputDir: String?
    public var model: String
    public var modelEndpoint: URL
    public var modelKeepAlive: String
    /// Timeout applied to each Ollama model request.
    public var modelTimeoutSeconds: Double
    /// Additional attempts allowed for retryable model-request failures.
    public var modelRetryLimit: Int
    public var profile: String
    public var logLevel: LogLevel
    public var logFormat: LogFormat
    public var dryRun: Bool
    public var debugDerivatives: Bool
    public var sourceIdentityPolicy: SourceIdentityPolicy
    public var derivativeCacheDir: String
    public var derivativeCacheSizeBytes: Int64
    public var clearDerivativeCacheOnStart: Bool
    public var clearDerivativeCacheAfterSuccess: Bool
    public var subjectCropMarginFraction: Double
    public var subjectMergeDominanceThreshold: Double
    /// Bounded render/isolation workers; the model stage still has one request in flight.
    public var stageConcurrency: Int
    /// Number of schema-constrained model-output repair attempts before recording failure.
    public var modelResponseRepairAttempts: Int
    /// GPS context policy for model prompts; coordinates are never written to XMP.
    public var gpsContext: GPSContextMode
    /// Ollama `num_ctx` token window requested for every model call. Zero —
    /// the built-in default — means "model default": no `num_ctx` is sent and
    /// Ollama sizes the window itself. Set a positive value to pin the window
    /// when the model's default is too small for the prompt, image tokens,
    /// and full JSON response.
    public var modelContextWindow: Int
    /// Ollama `num_predict` output-token cap; healthy responses run a few
    /// hundred tokens, so the default stops runaway generation early instead
    /// of letting it fill the whole context window.
    public var modelMaxResponseTokens: Int

    enum CodingKeys: String, CodingKey {
        case mode
        case existing
        case recursive
        case taskProfile = "task_profile"
        case qualityScanMode = "quality_scan_mode"
        case outputDir = "output_dir"
        case model
        case modelEndpoint = "model_endpoint"
        case modelKeepAlive = "model_keep_alive"
        case modelTimeoutSeconds = "model_timeout_seconds"
        case modelRetryLimit = "model_retry_limit"
        case profile
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case debugDerivatives = "debug_derivatives"
        case sourceIdentityPolicy = "source_identity_policy"
        case derivativeCacheDir = "derivative_cache_dir"
        case derivativeCacheSizeBytes = "derivative_cache_size_bytes"
        case clearDerivativeCacheOnStart = "clear_derivative_cache_on_start"
        case clearDerivativeCacheAfterSuccess = "clear_derivative_cache_after_success"
        case subjectCropMarginFraction = "subject_crop_margin_fraction"
        case subjectMergeDominanceThreshold = "subject_merge_dominance_threshold"
        case stageConcurrency = "stage_concurrency"
        case modelResponseRepairAttempts = "model_response_repair_attempts"
        case gpsContext = "gps_context"
        case modelContextWindow = "model_context_window"
        case modelMaxResponseTokens = "model_max_response_tokens"
    }

    public init(
        mode: AnalysisMode,
        existing: ExistingPolicy,
        recursive: Bool,
        taskProfile: ModelTaskProfile = .tagging,
        qualityScanMode: QualityScanMode = .combined,
        outputDir: String?,
        model: String,
        modelEndpoint: URL,
        modelKeepAlive: String = ModelRunOptions.default.keepAlive,
        modelTimeoutSeconds: Double = ModelRunOptions.default.timeoutSeconds,
        modelRetryLimit: Int = ModelRunOptions.default.retryLimit,
        profile: String,
        logLevel: LogLevel,
        logFormat: LogFormat,
        dryRun: Bool,
        debugDerivatives: Bool,
        sourceIdentityPolicy: SourceIdentityPolicy,
        derivativeCacheDir: String = DerivativeCache.defaultDirectoryPath(),
        derivativeCacheSizeBytes: Int64 = DerivativeCache.defaultSizeCapBytes,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false,
        subjectCropMarginFraction: Double = 0.08,
        subjectMergeDominanceThreshold: Double = 0.8,
        stageConcurrency: Int = Self.defaultStageConcurrency(),
        modelResponseRepairAttempts: Int = 1,
        gpsContext: GPSContextMode = .coarse,
        modelContextWindow: Int = 0,
        modelMaxResponseTokens: Int = 2_048
    ) {
        self.mode = mode
        self.existing = existing
        self.recursive = recursive
        self.taskProfile = taskProfile
        self.qualityScanMode = qualityScanMode
        self.outputDir = outputDir
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelKeepAlive = modelKeepAlive
        self.modelTimeoutSeconds = modelTimeoutSeconds
        self.modelRetryLimit = modelRetryLimit
        self.profile = profile
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.debugDerivatives = debugDerivatives
        self.sourceIdentityPolicy = sourceIdentityPolicy
        self.derivativeCacheDir = derivativeCacheDir
        self.derivativeCacheSizeBytes = derivativeCacheSizeBytes
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
        self.subjectCropMarginFraction = subjectCropMarginFraction
        self.subjectMergeDominanceThreshold = subjectMergeDominanceThreshold
        self.stageConcurrency = stageConcurrency
        self.modelResponseRepairAttempts = modelResponseRepairAttempts
        self.gpsContext = gpsContext
        self.modelContextWindow = modelContextWindow
        self.modelMaxResponseTokens = modelMaxResponseTokens
    }

    /// Default bounded render/isolation worker count for PW-015.
    ///
    /// Apple Silicon exposes physical performance cores through this sysctl.
    /// Other macOS hardware falls back to the active processor count while
    /// preserving a positive worker count for configuration provenance.
    public static func defaultStageConcurrency() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &value, &size, nil, 0) == 0, value > 0 {
            return Int(value)
        }
        return max(1, ProcessInfo.processInfo.activeProcessorCount)
    }

    public static let builtInDefaults = ResolvedRunConfiguration(
        mode: .both,
        existing: .skip,
        recursive: false,
        taskProfile: .tagging,
        qualityScanMode: .combined,
        outputDir: nil,
        model: "gemma4:26b-a4b-it-qat",
        modelEndpoint: URL(string: "http://localhost:11434")!,
        modelKeepAlive: ModelRunOptions.default.keepAlive,
        modelTimeoutSeconds: ModelRunOptions.default.timeoutSeconds,
        modelRetryLimit: ModelRunOptions.default.retryLimit,
        profile: "gemma4-26b-default",
        logLevel: .info,
        logFormat: .text,
        dryRun: false,
        debugDerivatives: false,
        sourceIdentityPolicy: .sha256,
        derivativeCacheDir: DerivativeCache.defaultDirectoryPath(),
        derivativeCacheSizeBytes: DerivativeCache.defaultSizeCapBytes,
        clearDerivativeCacheOnStart: false,
        clearDerivativeCacheAfterSuccess: false,
        subjectCropMarginFraction: 0.08,
        subjectMergeDominanceThreshold: 0.8,
        stageConcurrency: ResolvedRunConfiguration.defaultStageConcurrency(),
        modelResponseRepairAttempts: 1,
        gpsContext: .coarse,
        modelContextWindow: 0,
        modelMaxResponseTokens: 2_048
    )

    /// Return a configuration selecting a different model task contract while preserving all run settings.
    public func with(taskProfile: ModelTaskProfile) -> Self {
        var copy = self
        copy.taskProfile = taskProfile
        return copy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(existing, forKey: .existing)
        try container.encode(recursive, forKey: .recursive)
        try container.encode(taskProfile, forKey: .taskProfile)
        // Recorded only when it departs from the default: sidecars from runs
        // that never chose a scan mode stay byte-identical to earlier
        // releases, an identity the golden/hash tests pin.
        if qualityScanMode != Self.builtInDefaults.qualityScanMode {
            try container.encode(qualityScanMode, forKey: .qualityScanMode)
        }
        try container.encodeIfPresent(outputDir, forKey: .outputDir)
        try container.encode(model, forKey: .model)
        try container.encode(modelEndpoint, forKey: .modelEndpoint)
        try container.encode(modelKeepAlive, forKey: .modelKeepAlive)
        try container.encode(modelTimeoutSeconds, forKey: .modelTimeoutSeconds)
        try container.encode(modelRetryLimit, forKey: .modelRetryLimit)
        try container.encode(profile, forKey: .profile)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(logFormat, forKey: .logFormat)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encode(debugDerivatives, forKey: .debugDerivatives)
        try container.encode(sourceIdentityPolicy, forKey: .sourceIdentityPolicy)
        try container.encode(derivativeCacheDir, forKey: .derivativeCacheDir)
        try container.encode(derivativeCacheSizeBytes, forKey: .derivativeCacheSizeBytes)
        try container.encode(clearDerivativeCacheOnStart, forKey: .clearDerivativeCacheOnStart)
        try container.encode(clearDerivativeCacheAfterSuccess, forKey: .clearDerivativeCacheAfterSuccess)
        try container.encode(subjectCropMarginFraction, forKey: .subjectCropMarginFraction)
        try container.encode(subjectMergeDominanceThreshold, forKey: .subjectMergeDominanceThreshold)
        try container.encode(stageConcurrency, forKey: .stageConcurrency)
        try container.encode(modelResponseRepairAttempts, forKey: .modelResponseRepairAttempts)
        try container.encode(gpsContext, forKey: .gpsContext)
        try container.encode(modelContextWindow, forKey: .modelContextWindow)
        try container.encode(modelMaxResponseTokens, forKey: .modelMaxResponseTokens)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decode(AnalysisMode.self, forKey: .mode)
        self.existing = try container.decode(ExistingPolicy.self, forKey: .existing)
        self.recursive = try container.decode(Bool.self, forKey: .recursive)
        self.taskProfile =
            try container.decodeIfPresent(ModelTaskProfile.self, forKey: .taskProfile)
            ?? Self.builtInDefaults.taskProfile
        self.qualityScanMode =
            try container.decodeIfPresent(QualityScanMode.self, forKey: .qualityScanMode)
            ?? Self.builtInDefaults.qualityScanMode
        self.outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir)
        self.model = try container.decode(String.self, forKey: .model)
        self.modelEndpoint = try container.decode(URL.self, forKey: .modelEndpoint)
        self.modelKeepAlive =
            try container.decodeIfPresent(
                String.self,
                forKey: .modelKeepAlive
            ) ?? Self.builtInDefaults.modelKeepAlive
        self.modelTimeoutSeconds =
            try container.decodeIfPresent(
                Double.self,
                forKey: .modelTimeoutSeconds
            ) ?? Self.builtInDefaults.modelTimeoutSeconds
        self.modelRetryLimit =
            try container.decodeIfPresent(
                Int.self,
                forKey: .modelRetryLimit
            ) ?? Self.builtInDefaults.modelRetryLimit
        self.profile = try container.decode(String.self, forKey: .profile)
        self.logLevel = try container.decode(LogLevel.self, forKey: .logLevel)
        self.logFormat = try container.decode(LogFormat.self, forKey: .logFormat)
        self.dryRun = try container.decode(Bool.self, forKey: .dryRun)
        self.debugDerivatives = try container.decode(Bool.self, forKey: .debugDerivatives)
        self.sourceIdentityPolicy = try container.decode(SourceIdentityPolicy.self, forKey: .sourceIdentityPolicy)
        self.derivativeCacheDir = try container.decode(String.self, forKey: .derivativeCacheDir)
        self.derivativeCacheSizeBytes = try container.decode(Int64.self, forKey: .derivativeCacheSizeBytes)
        self.clearDerivativeCacheOnStart = try container.decode(Bool.self, forKey: .clearDerivativeCacheOnStart)
        self.clearDerivativeCacheAfterSuccess = try container.decode(
            Bool.self, forKey: .clearDerivativeCacheAfterSuccess)
        self.subjectCropMarginFraction = try container.decode(Double.self, forKey: .subjectCropMarginFraction)
        self.subjectMergeDominanceThreshold = try container.decode(Double.self, forKey: .subjectMergeDominanceThreshold)
        self.stageConcurrency = try container.decode(Int.self, forKey: .stageConcurrency)
        self.modelResponseRepairAttempts =
            try container.decodeIfPresent(
                Int.self,
                forKey: .modelResponseRepairAttempts
            ) ?? Self.builtInDefaults.modelResponseRepairAttempts
        self.gpsContext =
            try container.decodeIfPresent(
                GPSContextMode.self,
                forKey: .gpsContext
            ) ?? Self.builtInDefaults.gpsContext
        self.modelContextWindow =
            try container.decodeIfPresent(
                Int.self,
                forKey: .modelContextWindow
            ) ?? Self.builtInDefaults.modelContextWindow
        self.modelMaxResponseTokens =
            try container.decodeIfPresent(
                Int.self,
                forKey: .modelMaxResponseTokens
            ) ?? Self.builtInDefaults.modelMaxResponseTokens
    }
}
