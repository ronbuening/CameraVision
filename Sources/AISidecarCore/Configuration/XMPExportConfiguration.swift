import Foundation

/// Source identity handling for Phase 2 `write-xmp --from-json` inputs.
public enum XMPSourceVerificationPolicy: String, Codable, CaseIterable, Sendable {
    case fail
    case warn
    case skip
}

/// Existing-XMP handling for Phase 2 sidecar export.
public enum XMPConflictPolicy: String, Codable, CaseIterable, Sendable {
    case fail
    case merge
    case backupAndMerge = "backup-and-merge"
}

/// Ordinal minimum confidence threshold for candidate keyword export.
public enum XMPMinimumConfidence: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    private var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: XMPMinimumConfidence, rhs: XMPMinimumConfidence) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Same-base-name source selection policy for shared XMP sidecars.
public enum XMPPairScope: String, Codable, CaseIterable, Sendable {
    case union
    case rawOnly = "raw-only"
    case jpegOnly = "jpeg-only"
}

/// Optional Phase 2 export values supplied before precedence is resolved.
///
/// This is intentionally separate from `RunConfigurationOverrides` so Phase 2
/// metadata-write defaults do not become Phase 1 raw-sidecar provenance.
public struct XMPExportConfigurationOverrides: Sendable, Equatable {
    public var recursive: Bool?
    public var outputDir: String?
    public var configPath: String?
    public var logLevel: LogLevel?
    public var logFormat: LogFormat?
    public var dryRun: Bool?
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy?
    public var writeFlatKeywords: Bool?
    public var writeHierarchicalKeywords: Bool?
    public var backupSidecars: Bool?
    public var xmpConflictPolicy: XMPConflictPolicy?
    public var minConfidence: XMPMinimumConfidence?
    public var allowSpecificTags: Bool?
    public var pairScope: XMPPairScope?
    public var writeAIJSON: Bool?

    public init(
        recursive: Bool? = nil,
        outputDir: String? = nil,
        configPath: String? = nil,
        logLevel: LogLevel? = nil,
        logFormat: LogFormat? = nil,
        dryRun: Bool? = nil,
        sourceRoot: String? = nil,
        sourceVerification: XMPSourceVerificationPolicy? = nil,
        writeFlatKeywords: Bool? = nil,
        writeHierarchicalKeywords: Bool? = nil,
        backupSidecars: Bool? = nil,
        xmpConflictPolicy: XMPConflictPolicy? = nil,
        minConfidence: XMPMinimumConfidence? = nil,
        allowSpecificTags: Bool? = nil,
        pairScope: XMPPairScope? = nil,
        writeAIJSON: Bool? = nil
    ) {
        self.recursive = recursive
        self.outputDir = outputDir
        self.configPath = configPath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.writeFlatKeywords = writeFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.minConfidence = minConfidence
        self.allowSpecificTags = allowSpecificTags
        self.pairScope = pairScope
        self.writeAIJSON = writeAIJSON
    }
}

/// Fully resolved Phase 2 export configuration.
///
/// Values here follow PW-007 but are not recorded in Phase 1 raw sidecars.
public struct ResolvedXMPExportConfiguration: Codable, Sendable, Equatable {
    public var recursive: Bool
    public var outputDir: String?
    public var logLevel: LogLevel
    public var logFormat: LogFormat
    public var dryRun: Bool
    public var sourceRoot: String?
    public var sourceVerification: XMPSourceVerificationPolicy
    public var writeFlatKeywords: Bool
    public var writeHierarchicalKeywords: Bool
    public var backupSidecars: Bool
    public var xmpConflictPolicy: XMPConflictPolicy
    public var minConfidence: XMPMinimumConfidence
    public var allowSpecificTags: Bool
    public var pairScope: XMPPairScope
    public var writeAIJSON: Bool

    enum CodingKeys: String, CodingKey {
        case recursive
        case outputDir = "output_dir"
        case logLevel = "log_level"
        case logFormat = "log_format"
        case dryRun = "dry_run"
        case sourceRoot = "source_root"
        case sourceVerification = "source_verification"
        case writeFlatKeywords = "write_flat_keywords"
        case writeHierarchicalKeywords = "write_hierarchical_keywords"
        case backupSidecars = "backup_sidecars"
        case xmpConflictPolicy = "xmp_conflict_policy"
        case minConfidence = "min_confidence"
        case allowSpecificTags = "allow_specific_tags"
        case pairScope = "pair_scope"
        case writeAIJSON = "write_ai_json"
    }

    public init(
        recursive: Bool,
        outputDir: String?,
        logLevel: LogLevel,
        logFormat: LogFormat,
        dryRun: Bool,
        sourceRoot: String?,
        sourceVerification: XMPSourceVerificationPolicy,
        writeFlatKeywords: Bool,
        writeHierarchicalKeywords: Bool,
        backupSidecars: Bool,
        xmpConflictPolicy: XMPConflictPolicy,
        minConfidence: XMPMinimumConfidence,
        allowSpecificTags: Bool,
        pairScope: XMPPairScope,
        writeAIJSON: Bool
    ) {
        self.recursive = recursive
        self.outputDir = outputDir
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.dryRun = dryRun
        self.sourceRoot = sourceRoot
        self.sourceVerification = sourceVerification
        self.writeFlatKeywords = writeFlatKeywords
        self.writeHierarchicalKeywords = writeHierarchicalKeywords
        self.backupSidecars = backupSidecars
        self.xmpConflictPolicy = xmpConflictPolicy
        self.minConfidence = minConfidence
        self.allowSpecificTags = allowSpecificTags
        self.pairScope = pairScope
        self.writeAIJSON = writeAIJSON
    }

    public static let builtInDefaults = ResolvedXMPExportConfiguration(
        recursive: false,
        outputDir: nil,
        logLevel: .info,
        logFormat: .text,
        dryRun: false,
        sourceRoot: nil,
        sourceVerification: .fail,
        writeFlatKeywords: true,
        writeHierarchicalKeywords: true,
        backupSidecars: true,
        xmpConflictPolicy: .backupAndMerge,
        minConfidence: .medium,
        allowSpecificTags: false,
        pairScope: .union,
        writeAIJSON: true
    )
}

/// Input mode selected after Phase 2 CLI shape validation.
public enum XMPExportInvocationMode: Sendable, Equatable {
    case fromJSON(path: String)
    case analyzeAndWrite(inputPath: String)
}

/// Explicit `write-xmp` invocation shape before config-file defaults are applied.
///
/// Boolean pairs are kept as separate explicit flags so validation can reject
/// contradictory CLI input before converting them into optional overrides.
public struct XMPExportInvocationRequest: Sendable, Equatable {
    public var inputPath: String?
    public var fromJSONPath: String?
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

/// Requirement-level validation for the Phase 2 CLI scaffold.
public enum XMPExportInvocationValidator {
    public static func validate(_ request: XMPExportInvocationRequest) throws -> XMPExportInvocationMode {
        try rejectConflictingBooleanPairs(request)

        let inputPath = normalizedPath(request.inputPath)
        let fromJSONPath = normalizedPath(request.fromJSONPath)
        switch (inputPath, fromJSONPath) {
        case let (.some(inputPath), .none):
            try validateAnalyzeAndWriteOnlyOptions(request)
            return .analyzeAndWrite(inputPath: inputPath)
        case let (.none, .some(fromJSONPath)):
            try validateFromJSONOnlyOptions(request)
            return .fromJSON(path: fromJSONPath)
        case (.some, .some):
            throw SidecarError.configInvalid("--from-json and positional image input are mutually exclusive.")
        case (.none, .none):
            throw SidecarError.configInvalid("write-xmp requires either an image input path or --from-json.")
        }
    }

    private static func rejectConflictingBooleanPairs(_ request: XMPExportInvocationRequest) throws {
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

    private static func validateAnalyzeAndWriteOnlyOptions(_ request: XMPExportInvocationRequest) throws {
        if request.sourceRoot != nil {
            throw SidecarError.configInvalid("--source-root is valid only with --from-json.")
        }
        if request.sourceVerification != nil {
            throw SidecarError.configInvalid("--source-verification is valid only with --from-json.")
        }
    }

    private static func validateFromJSONOnlyOptions(_ request: XMPExportInvocationRequest) throws {
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
        if request.writeAIJSON || request.noWriteAIJSON {
            throw SidecarError.configInvalid("--write-ai-json is valid only with analyze-and-write mode.")
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
