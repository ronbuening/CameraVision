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
    public var existing: ExistingPolicy?
    public var model: String?
    public var modelEndpoint: String?
    public var profile: String?
    public var debugDerivatives: Bool
    public var clearDerivativeCacheOnStart: Bool
    public var clearDerivativeCacheAfterSuccess: Bool
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
        existing: ExistingPolicy? = nil,
        model: String? = nil,
        modelEndpoint: String? = nil,
        profile: String? = nil,
        debugDerivatives: Bool = false,
        clearDerivativeCacheOnStart: Bool = false,
        clearDerivativeCacheAfterSuccess: Bool = false,
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
        self.existing = existing
        self.model = model
        self.modelEndpoint = modelEndpoint
        self.profile = profile
        self.debugDerivatives = debugDerivatives
        self.clearDerivativeCacheOnStart = clearDerivativeCacheOnStart
        self.clearDerivativeCacheAfterSuccess = clearDerivativeCacheAfterSuccess
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

        let inputPath = normalizedPath(request.inputPath)
        let fromJSONPath = normalizedPath(request.fromJSONPath)
        let fileListPath = normalizedPath(request.fileListPath)
        let selectedInputs = [inputPath, fromJSONPath, fileListPath].compactMap { $0 }
        guard selectedInputs.count == 1 else {
            throw SidecarError.configInvalid("normalize requires exactly one of positional input, --from-json, or --file-list.")
        }

        if let fromJSONPath {
            try validateFromJSONOnlyOptions(request)
            return .fromJSON(path: fromJSONPath)
        }
        if let fileListPath {
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
        if request.writeFlatKeywords, request.noWriteFlatKeywords {
            throw SidecarError.configInvalid("--write-flat-keywords and --no-write-flat-keywords cannot be combined.")
        }
        if request.writeHierarchicalKeywords, request.noWriteHierarchicalKeywords {
            throw SidecarError.configInvalid(
                "--write-hierarchical-keywords and --no-write-hierarchical-keywords cannot be combined."
            )
        }
        if request.backupSidecars, request.noBackupSidecars {
            throw SidecarError.configInvalid("--backup-sidecars and --no-backup-sidecars cannot be combined.")
        }
        if request.writeAIJSON, request.noWriteAIJSON {
            throw SidecarError.configInvalid("--write-ai-json and --no-write-ai-json cannot be combined.")
        }
    }

    private static func validateAnalyzeInputOnlyOptions(
        _ request: NormalizationInvocationRequest,
        inputLabel _: String
    ) throws {
        if request.sourceRoot != nil {
            throw SidecarError.configInvalid("--source-root is valid only with normalize --from-json or apply-session.")
        }
        if request.sourceVerification != nil {
            throw SidecarError.configInvalid("--source-verification is valid only with normalize --from-json or apply-session.")
        }
    }

    private static func validateFromJSONOnlyOptions(_ request: NormalizationInvocationRequest) throws {
        if request.mode != nil {
            throw SidecarError.configInvalid("--mode is invalid with --from-json.")
        }
        if request.existing != nil {
            throw SidecarError.configInvalid("--existing is invalid with --from-json.")
        }
        if request.model != nil {
            throw SidecarError.configInvalid("--model is invalid with --from-json.")
        }
        if request.modelEndpoint != nil {
            throw SidecarError.configInvalid("--model-endpoint is invalid with --from-json.")
        }
        if request.profile != nil {
            throw SidecarError.configInvalid("--profile is invalid with --from-json.")
        }
        if request.debugDerivatives {
            throw SidecarError.configInvalid("--debug-derivatives is invalid with --from-json.")
        }
        if request.clearDerivativeCacheOnStart {
            throw SidecarError.configInvalid("--clear-derivative-cache-on-start is invalid with --from-json.")
        }
        if request.clearDerivativeCacheAfterSuccess {
            throw SidecarError.configInvalid("--clear-derivative-cache-after-success is invalid with --from-json.")
        }
        if request.modelResponseRepairAttempts != nil {
            throw SidecarError.configInvalid("--model-response-repair-attempts is invalid with --from-json.")
        }
        if request.gpsContext != nil {
            throw SidecarError.configInvalid("--gps-context is invalid with --from-json.")
        }
        if request.writeAIJSON || request.noWriteAIJSON {
            throw SidecarError.configInvalid("--write-ai-json is valid only with analyze-and-normalize mode.")
        }
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
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
        if request.backupSidecars, request.noBackupSidecars {
            throw SidecarError.configInvalid("--backup-sidecars and --no-backup-sidecars cannot be combined.")
        }
        guard let sessionPath = normalizedPath(request.sessionPath) else {
            throw SidecarError.configInvalid("apply-session requires a normalization session file.")
        }
        return sessionPath
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }
}
