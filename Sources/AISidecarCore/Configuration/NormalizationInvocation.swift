import Foundation

/// Input mode selected after `normalize` invocation validation.
public enum NormalizationInvocationMode: Sendable, Equatable {
    case analyze(inputPath: String)
    case fromJSON(path: String)
    case fileList(path: String)
}

/// Explicit `normalize` command shape before config-file defaults are applied.
public struct NormalizationInvocationRequest: Sendable, Equatable {
    public var inputPath: String?
    public var fromJSONPath: String?
    public var fileListPath: String?
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy?
    public var mode: AnalysisMode?
    public var assessQuality: Bool
    public var existing: ExistingPolicy?
    public var model: String?
    public var modelEndpoint: String?
    public var modelTimeoutSeconds: Double?
    public var modelRetryLimit: Int?
    public var profile: String?
    public var debugDerivatives: Bool
    public var clearDerivativeCacheOnStart: Bool
    public var clearDerivativeCacheAfterSuccess: Bool
    public var stageConcurrency: Int?
    public var modelResponseRepairAttempts: Int?
    public var gpsContext: GPSContextMode?
    public var writeFlatKeywords: Bool
    public var noWriteFlatKeywords: Bool
    public var writeHierarchicalKeywords: Bool
    public var noWriteHierarchicalKeywords: Bool
    public var backupSidecars: Bool
    public var noBackupSidecars: Bool
    public var writeAIJSON: Bool
    public var noWriteAIJSON: Bool

    public init(
        inputPath: String? = nil,
        fromJSONPath: String? = nil,
        fileListPath: String? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        mode: AnalysisMode? = nil,
        assessQuality: Bool = false,
        existing: ExistingPolicy? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        modelTimeoutSeconds: Double? = nil,
        modelRetryLimit: Int? = nil,
        profile: String? = nil,
        debugDerivatives: Bool = false,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false,
        stageConcurrency: Int? = nil,
        modelResponseRepairAttempts: Int? = nil,
        gpsContext: GPSContextMode? = nil,
        writeFlatKeywords: Bool = false,
        noWriteFlatKeywords: Bool = false,
        writeHierarchicalKeywords: Bool = false,
        noWriteHierarchicalKeywords: Bool = false,
        backupSidecars: Bool = false,
        noBackupSidecars: Bool = false,
        writeAIJSON: Bool = false,
        noWriteAIJSON: Bool = false
    ) {
        self.inputPath = inputPath
        self.fromJSONPath = fromJSONPath
        self.fileListPath = fileListPath
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.mode = mode
        self.assessQuality = assessQuality
        self.existing = existing
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.modelTimeoutSeconds = modelTimeoutSeconds
        self.modelRetryLimit = modelRetryLimit
        self.profile = profile
        self.debugDerivatives = debugDerivatives
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
        self.stageConcurrency = stageConcurrency
        self.modelResponseRepairAttempts = modelResponseRepairAttempts
        self.gpsContext = gpsContext
        self.writeFlatKeywords = writeFlatKeywords
        self.noWriteFlatKeywords = noWriteFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.noWriteHierarchicalKeywords = noWriteHierarchicalKeywords
        self.backupSidecars = backupSidecars
        self.noBackupSidecars = noBackupSidecars
        self.writeAIJSON = writeAIJSON
        self.noWriteAIJSON = noWriteAIJSON
    }
}

/// Requirement-level validation for the Phase 3 `normalize` CLI scaffold.
public enum NormalizationInvocationValidator {
    public static func validate(_ request: NormalizationInvocationRequest) throws -> NormalizationInvocationMode {
        try rejectConflictingBooleanPairs(request)

        let inputPath = InvocationRules.normalizedPath(request.inputPath)
        let fromJSONPath = InvocationRules.normalizedPath(request.fromJSONPath)
        let fileListPath = InvocationRules.normalizedPath(request.fileListPath)
        let selectedInputs = [inputPath, fromJSONPath, fileListPath].compactMap { $0 }
        guard selectedInputs.count == 1 else {
            throw SidecarError.configInvalid(
                "normalize requires exactly one of positional input, --from-json, or --file-list.")
        }

        if let fromJSONPath {
            try validateFromJSONOnlyOptions(request)
            return .fromJSON(path: fromJSONPath)
        }
        if let fileListPath {
            if request.assessQuality {
                throw SidecarError.configInvalid(
                    "--assess-quality is valid only with positional analyze-and-normalize input."
                )
            }
            try validateAnalyzeInputOnlyOptions(request, inputLabel: "--file-list")
            return .fileList(path: fileListPath)
        }
        guard let inputPath else {
            throw SidecarError.configInvalid("normalize requires an input.")
        }
        try validateAnalyzeInputOnlyOptions(request, inputLabel: "positional input")
        return .analyze(inputPath: inputPath)
    }

    private static func rejectConflictingBooleanPairs(_ request: NormalizationInvocationRequest) throws {
        try InvocationRules.rejectConflictingFlag(
            "write-flat-keywords", enabled: request.writeFlatKeywords, disabled: request.noWriteFlatKeywords
        )
        try InvocationRules.rejectConflictingFlag(
            "write-hierarchical-keywords",
            enabled: request.writeHierarchicalKeywords,
            disabled: request.noWriteHierarchicalKeywords
        )
        try InvocationRules.rejectConflictingFlag(
            "backup-sidecars", enabled: request.backupSidecars, disabled: request.noBackupSidecars
        )
        try InvocationRules.rejectConflictingFlag(
            "write-ai-json", enabled: request.writeAIJSON, disabled: request.noWriteAIJSON
        )
    }

    private static func validateAnalyzeInputOnlyOptions(
        _ request: NormalizationInvocationRequest,
        inputLabel _: String
    ) throws {
        if request.sourceRoot != nil {
            throw SidecarError.configInvalid("--source-root is valid only with normalize --from-json or apply-session.")
        }
        if request.sourceVerification != nil {
            throw SidecarError.configInvalid(
                "--source-verification is valid only with normalize --from-json or apply-session.")
        }
    }

    private static func validateFromJSONOnlyOptions(_ request: NormalizationInvocationRequest) throws {
        try InvocationRules.rejectFromJSONIncompatible([
            ("mode", request.mode != nil),
            ("assess-quality", request.assessQuality),
            ("existing", request.existing != nil),
            ("model", request.model != nil),
            ("model-endpoint", request.modelEndpoint != nil),
            ("model-timeout", request.modelTimeoutSeconds != nil),
            ("model-retry-limit", request.modelRetryLimit != nil),
            ("profile", request.profile != nil),
            ("debug-derivatives", request.debugDerivatives),
            ("clear-derivative-cache-on-start", request.clearDerivativeCacheOnStart),
            ("clear-derivative-cache-after-success", request.clearDerivativeCacheAfterSuccess),
            ("stage-concurrency", request.stageConcurrency != nil),
            ("model-response-repair-attempts", request.modelResponseRepairAttempts != nil),
            ("gps-context", request.gpsContext != nil),
        ])
        if request.writeAIJSON || request.noWriteAIJSON {
            throw SidecarError.configInvalid("--write-ai-json is valid only with analyze-and-normalize mode.")
        }
    }
}

/// Explicit `apply-session` command shape before config-file defaults are applied.
public struct ApplySessionInvocationRequest: Sendable, Equatable {
    public var sessionPath: String?
    public var backupSidecars: Bool
    public var noBackupSidecars: Bool
    public var invalidNormalizationFlags: [String]

    public init(
        sessionPath: String? = nil,
        backupSidecars: Bool = false,
        noBackupSidecars: Bool = false,
        invalidNormalizationFlags: [String] = []
    ) {
        self.sessionPath = sessionPath
        self.backupSidecars = backupSidecars
        self.noBackupSidecars = noBackupSidecars
        self.invalidNormalizationFlags = invalidNormalizationFlags
    }
}

/// Requirement-level validation for the Phase 3 `apply-session` CLI scaffold.
public enum ApplySessionInvocationValidator {
    public static func validate(_ request: ApplySessionInvocationRequest) throws -> String {
        guard request.invalidNormalizationFlags.isEmpty else {
            throw SidecarError.configInvalid(
                "apply-session cannot accept normalization or analysis flags: "
                    + request.invalidNormalizationFlags.sorted().joined(separator: ", ")
            )
        }
        try InvocationRules.rejectConflictingFlag(
            "backup-sidecars", enabled: request.backupSidecars, disabled: request.noBackupSidecars
        )
        guard let sessionPath = InvocationRules.normalizedPath(request.sessionPath) else {
            throw SidecarError.configInvalid("apply-session requires a normalization session file.")
        }
        return sessionPath
    }
}
