import Foundation

/// Input counts recorded by the initial Phase 3 normalization report.
public struct NormalizationInputSummary: Codable, Sendable, Equatable {
    public var sourceAssetCount: Int
    public var sourceAISidecarCount: Int
    public var sameBaseNameGroupCount: Int
    public var candidateObservationCount: Int
    public var candidateSkipCount: Int
    public var batchCandidateCount: Int
    public var perAssetDecisionCount: Int
    public var warningCount: Int
    public var failureCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceAssetCount = "source_asset_count"
        case sourceAISidecarCount = "source_ai_sidecar_count"
        case sameBaseNameGroupCount = "same_base_name_group_count"
        case candidateObservationCount = "candidate_observation_count"
        case candidateSkipCount = "candidate_skip_count"
        case batchCandidateCount = "batch_candidate_count"
        case perAssetDecisionCount = "per_asset_decision_count"
        case warningCount = "warning_count"
        case failureCount = "failure_count"
    }

    public init(
        sourceAssetCount: Int,
        sourceAISidecarCount: Int,
        sameBaseNameGroupCount: Int,
        candidateObservationCount: Int = 0,
        candidateSkipCount: Int = 0,
        batchCandidateCount: Int = 0,
        perAssetDecisionCount: Int = 0,
        warningCount: Int,
        failureCount: Int
    ) {
        self.sourceAssetCount = sourceAssetCount
        self.sourceAISidecarCount = sourceAISidecarCount
        self.sameBaseNameGroupCount = sameBaseNameGroupCount
        self.candidateObservationCount = candidateObservationCount
        self.candidateSkipCount = candidateSkipCount
        self.batchCandidateCount = batchCandidateCount
        self.perAssetDecisionCount = perAssetDecisionCount
        self.warningCount = warningCount
        self.failureCount = failureCount
    }
}

/// Decision status counts for quick validation of a normalization report.
public struct NormalizationDecisionSummary: Codable, Sendable, Equatable {
    public var acceptedCount: Int
    public var withheldCount: Int
    public var skippedCount: Int
    public var phase2FallbackCount: Int
    public var userContextCount: Int

    enum CodingKeys: String, CodingKey {
        case acceptedCount = "accepted_count"
        case withheldCount = "withheld_count"
        case skippedCount = "skipped_count"
        case phase2FallbackCount = "phase2_fallback_count"
        case userContextCount = "user_context_count"
    }

    public init(decisions: [PerAssetNormalizationDecision] = []) {
        self.acceptedCount = decisions.filter { $0.status == .accepted }.count
        self.withheldCount = decisions.filter { $0.status == .withheld }.count
        self.skippedCount = decisions.filter { $0.status == .skipped }.count
        self.phase2FallbackCount = decisions.filter { $0.stage == .phase2Fallback }.count
        self.userContextCount = decisions.filter { $0.stage == .userSessionContext }.count
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
    public var decisionSummary: NormalizationDecisionSummary
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
        case decisionSummary = "decision_summary"
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
        decisionSummary: NormalizationDecisionSummary = NormalizationDecisionSummary(),
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
        self.decisionSummary = decisionSummary
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
