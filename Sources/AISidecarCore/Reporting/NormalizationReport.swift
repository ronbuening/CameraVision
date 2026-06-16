import Foundation

/// Input counts recorded by the initial Phase 3 normalization report.
public struct NormalizationInputSummary: Codable, Sendable, Equatable {
    public var sourceAssetCount: Int
    public var sourceAISidecarCount: Int
    public var sameBaseNameGroupCount: Int
    public var warningCount: Int
    public var failureCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceAssetCount = "source_asset_count"
        case sourceAISidecarCount = "source_ai_sidecar_count"
        case sameBaseNameGroupCount = "same_base_name_group_count"
        case warningCount = "warning_count"
        case failureCount = "failure_count"
    }

    public init(
        sourceAssetCount: Int,
        sourceAISidecarCount: Int,
        sameBaseNameGroupCount: Int,
        warningCount: Int,
        failureCount: Int
    ) {
        self.sourceAssetCount = sourceAssetCount
        self.sourceAISidecarCount = sourceAISidecarCount
        self.sameBaseNameGroupCount = sameBaseNameGroupCount
        self.warningCount = warningCount
        self.failureCount = failureCount
    }
}

/// Machine-readable Phase 3 normalization report.
public struct NormalizationReport: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var createdAt: Date
    public var sessionPath: String?
    public var workflow: NormalizationInputWorkflow
    public var inputPath: String
    public var configuration: ResolvedNormalizationConfiguration
    public var vocabulary: VocabularyIdentity
    public var xmpWriter: MetadataWriteEngineContext
    public var artifacts: NormalizationArtifactPlan
    public var inputSummary: NormalizationInputSummary
    public var warnings: [SidecarError]
    public var errors: [SidecarError]
    public var applicationInstructions: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case sessionPath = "session_path"
        case workflow
        case inputPath = "input_path"
        case configuration
        case vocabulary
        case xmpWriter = "xmp_writer"
        case artifacts
        case inputSummary = "input_summary"
        case warnings
        case errors
        case applicationInstructions = "application_instructions"
    }

    public init(
        schemaVersion: String = NormalizationSchemaIdentifiers.report,
        createdAt: Date,
        sessionPath: String?,
        workflow: NormalizationInputWorkflow,
        inputPath: String,
        configuration: ResolvedNormalizationConfiguration,
        vocabulary: VocabularyIdentity,
        xmpWriter: MetadataWriteEngineContext,
        artifacts: NormalizationArtifactPlan,
        inputSummary: NormalizationInputSummary,
        warnings: [SidecarError],
        errors: [SidecarError],
        applicationInstructions: [String] = XMPExportReport.applicationInstructions
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.sessionPath = sessionPath
        self.workflow = workflow
        self.inputPath = inputPath
        self.configuration = configuration
        self.vocabulary = vocabulary
        self.xmpWriter = xmpWriter
        self.artifacts = artifacts
        self.inputSummary = inputSummary
        self.warnings = warnings
        self.errors = errors
        self.applicationInstructions = applicationInstructions
    }
}

/// Writes normalization reports atomically with stable JSON formatting.
public struct NormalizationReportWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func write(_ report: NormalizationReport, to path: String) throws {
        do {
            let data = try encoder.encode(report)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write normalization report \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
