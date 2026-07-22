import Foundation

struct ConfigurationBuilder {
    private var mode: AnalysisMode
    private var existing: ExistingPolicy
    private var recursive: Bool
    private var qualityAssessment: Bool
    private var qualityScanMode: QualityScanMode
    private var outputDir: String?
    private var model: String
    private var modelEndpoint: String
    private var modelKeepAlive: String
    private var modelTimeoutSeconds: Double
    private var modelRetryLimit: Int
    private var profile: String
    private var logLevel: LogLevel
    private var logFormat: LogFormat
    private var dryRun: Bool
    private var debugDerivatives: Bool
    private var sourceIdentityPolicy: SourceIdentityPolicy
    private var derivativeCacheDir: String
    private var derivativeCacheSizeBytes: Int64
    private var clearDerivativeCacheOnStart: Bool
    private var clearDerivativeCacheAfterSuccess: Bool
    private var subjectCropMarginFraction: Double
    private var subjectMergeDominanceThreshold: Double
    private var stageConcurrency: Int
    private var modelResponseRepairAttempts: Int
    private var gpsContext: GPSContextMode
    private var modelContextWindow: Int
    private var modelMaxResponseTokens: Int

    init(defaults: ResolvedRunConfiguration) {
        self.mode = defaults.mode
        self.existing = defaults.existing
        self.recursive = defaults.recursive
        self.qualityAssessment = false
        self.qualityScanMode = defaults.qualityScanMode
        self.outputDir = defaults.outputDir
        self.model = defaults.model
        self.modelEndpoint = defaults.modelEndpoint.absoluteString
        self.modelKeepAlive = defaults.modelKeepAlive
        self.modelTimeoutSeconds = defaults.modelTimeoutSeconds
        self.modelRetryLimit = defaults.modelRetryLimit
        self.profile = defaults.profile
        self.logLevel = defaults.logLevel
        self.logFormat = defaults.logFormat
        self.dryRun = defaults.dryRun
        self.debugDerivatives = defaults.debugDerivatives
        self.sourceIdentityPolicy = defaults.sourceIdentityPolicy
        self.derivativeCacheDir = defaults.derivativeCacheDir
        self.derivativeCacheSizeBytes = defaults.derivativeCacheSizeBytes
        self.clearDerivativeCacheOnStart = defaults.clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = defaults.clearDerivativeCacheAfterSuccess
        self.subjectCropMarginFraction = defaults.subjectCropMarginFraction
        self.subjectMergeDominanceThreshold = defaults.subjectMergeDominanceThreshold
        self.stageConcurrency = defaults.stageConcurrency
        self.modelResponseRepairAttempts = defaults.modelResponseRepairAttempts
        self.gpsContext = defaults.gpsContext
        self.modelContextWindow = defaults.modelContextWindow
        self.modelMaxResponseTokens = defaults.modelMaxResponseTokens
    }

    mutating func apply(config: AppConfig) {
        merge(&mode, config.mode)
        merge(&existing, config.existing)
        merge(&recursive, config.recursive)
        merge(&qualityAssessment, config.qualityAssessment)
        merge(&qualityScanMode, config.qualityScanMode)
        merge(&outputDir, config.outputDir)
        merge(&model, config.model)
        merge(&modelEndpoint, config.modelEndpoint)
        merge(&modelKeepAlive, config.modelKeepAlive)
        merge(&modelTimeoutSeconds, config.modelTimeoutSeconds)
        merge(&modelRetryLimit, config.modelRetryLimit)
        merge(&profile, config.profile)
        merge(&logLevel, config.logLevel)
        merge(&logFormat, config.logFormat)
        merge(&dryRun, config.dryRun)
        merge(&debugDerivatives, config.debugDerivatives)
        merge(&sourceIdentityPolicy, config.sourceIdentityPolicy)
        merge(&derivativeCacheDir, config.derivativeCacheDir)
        merge(&derivativeCacheSizeBytes, config.derivativeCacheSizeBytes)
        merge(&clearDerivativeCacheOnStart, config.clearDerivativeCacheOnStart)
        merge(&clearDerivativeCacheAfterSuccess, config.clearDerivativeCacheAfterSuccess)
        merge(&subjectCropMarginFraction, config.subjectCropMarginFraction)
        merge(&subjectMergeDominanceThreshold, config.subjectMergeDominanceThreshold)
        merge(&stageConcurrency, config.stageConcurrency)
        merge(&modelResponseRepairAttempts, config.modelResponseRepairAttempts)
        merge(&gpsContext, config.gpsContext)
        merge(&modelContextWindow, config.modelContextWindow)
        merge(&modelMaxResponseTokens, config.modelMaxResponseTokens)
    }

    mutating func apply(overrides: RunConfigurationOverrides) {
        merge(&mode, overrides.mode)
        merge(&existing, overrides.existing)
        merge(&recursive, overrides.recursive)
        merge(&qualityAssessment, overrides.qualityAssessment)
        merge(&qualityScanMode, overrides.qualityScanMode)
        merge(&outputDir, overrides.outputDir)
        merge(&model, overrides.model)
        merge(&modelEndpoint, overrides.modelEndpoint)
        merge(&modelKeepAlive, overrides.modelKeepAlive)
        merge(&modelTimeoutSeconds, overrides.modelTimeoutSeconds)
        merge(&modelRetryLimit, overrides.modelRetryLimit)
        merge(&profile, overrides.profile)
        merge(&logLevel, overrides.logLevel)
        merge(&logFormat, overrides.logFormat)
        merge(&dryRun, overrides.dryRun)
        merge(&debugDerivatives, overrides.debugDerivatives)
        merge(&sourceIdentityPolicy, overrides.sourceIdentityPolicy)
        merge(&derivativeCacheDir, overrides.derivativeCacheDir)
        merge(&derivativeCacheSizeBytes, overrides.derivativeCacheSizeBytes)
        merge(&clearDerivativeCacheOnStart, overrides.clearDerivativeCacheOnStart)
        merge(&clearDerivativeCacheAfterSuccess, overrides.clearDerivativeCacheAfterSuccess)
        merge(&subjectCropMarginFraction, overrides.subjectCropMarginFraction)
        merge(&subjectMergeDominanceThreshold, overrides.subjectMergeDominanceThreshold)
        merge(&stageConcurrency, overrides.stageConcurrency)
        merge(&modelResponseRepairAttempts, overrides.modelResponseRepairAttempts)
        merge(&gpsContext, overrides.gpsContext)
        merge(&modelContextWindow, overrides.modelContextWindow)
        merge(&modelMaxResponseTokens, overrides.modelMaxResponseTokens)
    }

    func resolved() throws -> ResolvedRunConfiguration {
        guard let endpoint = URL(string: modelEndpoint),
            let scheme = endpoint.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            endpoint.host != nil
        else {
            throw SidecarError.configInvalid("Invalid model endpoint URL: \(modelEndpoint)")
        }
        guard !modelKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SidecarError.configInvalid("model_keep_alive must not be empty")
        }
        guard modelTimeoutSeconds > 0, modelTimeoutSeconds.isFinite else {
            throw SidecarError.configInvalid("model_timeout_seconds must be a finite value greater than zero")
        }
        guard modelRetryLimit >= 0 else {
            throw SidecarError.configInvalid("model_retry_limit must be zero or greater")
        }
        _ = try ModelInputProfileRegistry.resolve(name: profile)
        guard derivativeCacheSizeBytes > 0 else {
            throw SidecarError.configInvalid("derivative_cache_size_bytes must be greater than zero")
        }
        guard subjectCropMarginFraction > 0, subjectCropMarginFraction <= 1, subjectCropMarginFraction.isFinite else {
            throw SidecarError.configInvalid("subject_crop_margin_fraction must be greater than zero and at most one")
        }
        guard subjectMergeDominanceThreshold > 0,
            subjectMergeDominanceThreshold <= 1,
            subjectMergeDominanceThreshold.isFinite
        else {
            throw SidecarError.configInvalid(
                "subject_merge_dominance_threshold must be greater than zero and at most one")
        }
        guard stageConcurrency > 0 else {
            throw SidecarError.configInvalid("stage_concurrency must be greater than zero")
        }
        guard modelResponseRepairAttempts >= 0 else {
            throw SidecarError.configInvalid("model_response_repair_attempts must be zero or greater")
        }
        guard modelContextWindow >= 0 else {
            throw SidecarError.configInvalid("model_context_window must be zero (model default) or greater")
        }
        guard modelMaxResponseTokens > 0 else {
            throw SidecarError.configInvalid("model_max_response_tokens must be greater than zero")
        }

        return ResolvedRunConfiguration(
            mode: mode,
            existing: existing,
            recursive: recursive,
            taskProfile: qualityAssessment ? .taggingWithQuality : .tagging,
            qualityScanMode: qualityScanMode,
            outputDir: outputDir,
            model: model,
            modelEndpoint: endpoint,
            modelKeepAlive: modelKeepAlive,
            modelTimeoutSeconds: modelTimeoutSeconds,
            modelRetryLimit: modelRetryLimit,
            profile: profile,
            logLevel: logLevel,
            logFormat: logFormat,
            dryRun: dryRun,
            debugDerivatives: debugDerivatives,
            sourceIdentityPolicy: sourceIdentityPolicy,
            derivativeCacheDir: derivativeCacheDir,
            derivativeCacheSizeBytes: derivativeCacheSizeBytes,
            clearDerivativeCacheOnStart: clearDerivativeCacheOnStart,
            clearDerivativeCacheAfterSuccess: clearDerivativeCacheAfterSuccess,
            subjectCropMarginFraction: subjectCropMarginFraction,
            subjectMergeDominanceThreshold: subjectMergeDominanceThreshold,
            stageConcurrency: stageConcurrency,
            modelResponseRepairAttempts: modelResponseRepairAttempts,
            gpsContext: gpsContext,
            modelContextWindow: modelContextWindow,
            modelMaxResponseTokens: modelMaxResponseTokens
        )
    }
}
