import Foundation

/// Phase 3 input workflow recorded in session and report artifacts.
public enum NormalizationInputWorkflow: String, Codable, Sendable, Equatable {
    case analyze
    case fromJSON = "from-json"
    case fileList = "file-list"
}

/// Session-context role supplied by the user.
public enum NormalizationSessionContextType: String, Codable, Sendable, Equatable {
    case subject
    case habitat
    case event
}

/// Early session-context audit record before vocabulary matching decisions exist.
public struct NormalizationSessionContextRecord: Codable, Sendable, Equatable {
    public var contextType: NormalizationSessionContextType
    public var originalText: String
    public var foldedText: String
    public var matchedCanonicalPath: String?
    public var unknownPolicyResult: String
    public var propagationAllowed: Bool
    public var exportResult: String

    enum CodingKeys: String, CodingKey {
        case contextType = "context_type"
        case originalText = "original_text"
        case foldedText = "folded_text"
        case matchedCanonicalPath = "matched_canonical_path"
        case unknownPolicyResult = "unknown_policy_result"
        case propagationAllowed = "propagation_allowed"
        case exportResult = "export_result"
    }

    public init(
        contextType: NormalizationSessionContextType,
        originalText: String,
        foldedText: String,
        matchedCanonicalPath: String?,
        unknownPolicyResult: String,
        propagationAllowed: Bool,
        exportResult: String
    ) {
        self.contextType = contextType
        self.originalText = originalText
        self.foldedText = foldedText
        self.matchedCanonicalPath = matchedCanonicalPath
        self.unknownPolicyResult = unknownPolicyResult
        self.propagationAllowed = propagationAllowed
        self.exportResult = exportResult
    }
}

/// Top-level session metadata that binds a Phase 3 run to its source workflow.
public struct NormalizationSessionMetadata: Codable, Sendable, Equatable {
    public var sessionID: String
    public var createdAt: Date
    public var workflow: NormalizationInputWorkflow
    public var inputPath: String
    public var normalizationMode: NormalizationMode
    public var scanRoot: String?
    public var sourceRoot: String?
    public var outputDir: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case createdAt = "created_at"
        case workflow
        case inputPath = "input_path"
        case normalizationMode = "normalization_mode"
        case scanRoot = "scan_root"
        case sourceRoot = "source_root"
        case outputDir = "output_dir"
    }

    public init(
        sessionID: String,
        createdAt: Date,
        workflow: NormalizationInputWorkflow,
        inputPath: String,
        normalizationMode: NormalizationMode,
        scanRoot: String?,
        sourceRoot: String?,
        outputDir: String?
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.workflow = workflow
        self.inputPath = inputPath
        self.normalizationMode = normalizationMode
        self.scanRoot = scanRoot
        self.sourceRoot = sourceRoot
        self.outputDir = outputDir
    }
}

/// Default privacy behavior for affinity audit data.
public struct NormalizationPrivacyRecord: Codable, Sendable, Equatable {
    public var exactAffinityInputsPersisted: Bool
    public var cameraSerialsHashed: Bool
    public var gpsCoordinatesPersisted: Bool
    public var captureTimesPersisted: Bool
    public var privacyMode: AffinityPrivacyMode

    enum CodingKeys: String, CodingKey {
        case exactAffinityInputsPersisted = "exact_affinity_inputs_persisted"
        case cameraSerialsHashed = "camera_serials_hashed"
        case gpsCoordinatesPersisted = "gps_coordinates_persisted"
        case captureTimesPersisted = "capture_times_persisted"
        case privacyMode = "privacy_mode"
    }

    public init(privacyMode: AffinityPrivacyMode) {
        self.privacyMode = privacyMode
        self.exactAffinityInputsPersisted = privacyMode == .debugExact
        self.cameraSerialsHashed = true
        self.gpsCoordinatesPersisted = privacyMode == .debugExact
        self.captureTimesPersisted = privacyMode == .debugExact
    }
}

/// Deterministic policy metadata required to replay and audit later decisions.
public struct NormalizationDeterministicPolicyRecord: Codable, Sendable, Equatable {
    public var scoreRoundingPrecision: Int
    public var scoreBandThresholds: [String: Double]
    public var edgeSortingOrder: [String]
    public var neighborTruncationRule: String
    public var decisionTieBreakOrder: [String]
    public var exactAffinityInputsPersisted: Bool

    enum CodingKeys: String, CodingKey {
        case scoreRoundingPrecision = "score_rounding_precision"
        case scoreBandThresholds = "score_band_thresholds"
        case edgeSortingOrder = "edge_sorting_order"
        case neighborTruncationRule = "neighbor_truncation_rule"
        case decisionTieBreakOrder = "decision_tie_break_order"
        case exactAffinityInputsPersisted = "exact_affinity_inputs_persisted"
    }

    public init(exactAffinityInputsPersisted: Bool) {
        self.scoreRoundingPrecision = 6
        self.scoreBandThresholds = [
            "very_strong": 0.75,
            "strong": 0.55,
            "moderate": 0.35,
            "weak": 0.15
        ]
        self.edgeSortingOrder = ["from_asset_id", "descending_affinity", "to_asset_id"]
        self.neighborTruncationRule = "descending_affinity_then_ascending_asset_id"
        self.decisionTieBreakOrder = [
            "direct_observation",
            "local_weighted_agreement",
            "support_mass",
            "maximum_supporting_affinity",
            "lower_specificity",
            "canonical_path"
        ]
        self.exactAffinityInputsPersisted = exactAffinityInputsPersisted
    }
}

/// Affinity node persisted before Milestone 4 edge scoring is available.
public struct NormalizationAffinityNodeRecord: Codable, Sendable, Equatable {
    public var nodeID: String
    public var groupID: String
    public var memberAssetIDs: [String]

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case groupID = "group_id"
        case memberAssetIDs = "member_asset_ids"
    }

    public init(nodeID: String, groupID: String, memberAssetIDs: [String]) {
        self.nodeID = nodeID
        self.groupID = groupID
        self.memberAssetIDs = memberAssetIDs
    }
}

/// Metadata-affinity audit payload recorded in a normalization session.
public struct NormalizationAffinityRecord: Codable, Sendable, Equatable {
    public var mode: NormalizationAffinityMode
    public var profile: NormalizationAffinityProfile
    public var minAffinityForConsensus: Double
    public var nodes: [NormalizationAffinityNodeRecord]
    public var edges: [String]
    public var clusters: [String]

    enum CodingKeys: String, CodingKey {
        case mode
        case profile
        case minAffinityForConsensus = "min_affinity_for_consensus"
        case nodes
        case edges
        case clusters
    }

    public init(
        mode: NormalizationAffinityMode,
        profile: NormalizationAffinityProfile,
        minAffinityForConsensus: Double,
        nodes: [NormalizationAffinityNodeRecord],
        edges: [String] = [],
        clusters: [String] = []
    ) {
        self.mode = mode
        self.profile = profile
        self.minAffinityForConsensus = minAffinityForConsensus
        self.nodes = nodes
        self.edges = edges
        self.clusters = clusters
    }
}

/// Placeholder batch candidate summary populated by later normalization milestones.
public struct BatchCandidateSummary: Codable, Sendable, Equatable {
    public init() {}
}

/// Placeholder local consensus record populated once affinity scoring exists.
public struct LocalWeightedConsensusRecord: Codable, Sendable, Equatable {
    public init() {}
}

/// Placeholder per-asset decision record populated by canonicalization and propagation milestones.
public struct PerAssetNormalizationDecision: Codable, Sendable, Equatable {
    public init() {}
}

/// Placeholder normalized XMP plan record populated by the Phase 2 plan adapter milestone.
public struct NormalizedXMPWritePlan: Codable, Sendable, Equatable {
    public init() {}
}

/// Durable Phase 3 normalization session consumed later by `apply-session`.
public struct NormalizationSessionDocument: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var session: NormalizationSessionMetadata
    public var vocabulary: VocabularyIdentity
    public var resolvedConfiguration: ResolvedNormalizationConfiguration
    public var sessionContext: [NormalizationSessionContextRecord]
    public var privacy: NormalizationPrivacyRecord
    public var xmpWriter: MetadataWriteEngineContext
    public var sourceAISidecars: [NormalizationSourceAISidecarRecord]
    public var sourceAssets: [NormalizationSourceAsset]
    public var sameBaseNameGroups: [NormalizationSourceGroup]
    public var affinity: NormalizationAffinityRecord
    public var batchCandidates: [BatchCandidateSummary]
    public var localConsensus: [LocalWeightedConsensusRecord]
    public var perAssetDecisions: [PerAssetNormalizationDecision]
    public var xmpWritePlans: [NormalizedXMPWritePlan]
    public var artifacts: NormalizationArtifactPlan
    public var deterministicPolicy: NormalizationDeterministicPolicyRecord
    public var warnings: [SidecarError]
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case session
        case vocabulary
        case resolvedConfiguration = "resolved_configuration"
        case sessionContext = "session_context"
        case privacy
        case xmpWriter = "xmp_writer"
        case sourceAISidecars = "source_ai_sidecars"
        case sourceAssets = "source_assets"
        case sameBaseNameGroups = "same_base_name_groups"
        case affinity
        case batchCandidates = "batch_candidates"
        case localConsensus = "local_consensus"
        case perAssetDecisions = "per_asset_decisions"
        case xmpWritePlans = "xmp_write_plans"
        case artifacts
        case deterministicPolicy = "deterministic_policy"
        case warnings
        case errors
    }

    public init(
        schemaVersion: String = NormalizationSchemaIdentifiers.session,
        session: NormalizationSessionMetadata,
        vocabulary: VocabularyIdentity,
        resolvedConfiguration: ResolvedNormalizationConfiguration,
        sessionContext: [NormalizationSessionContextRecord],
        privacy: NormalizationPrivacyRecord,
        xmpWriter: MetadataWriteEngineContext,
        sourceAISidecars: [NormalizationSourceAISidecarRecord],
        sourceAssets: [NormalizationSourceAsset],
        sameBaseNameGroups: [NormalizationSourceGroup],
        affinity: NormalizationAffinityRecord,
        batchCandidates: [BatchCandidateSummary] = [],
        localConsensus: [LocalWeightedConsensusRecord] = [],
        perAssetDecisions: [PerAssetNormalizationDecision] = [],
        xmpWritePlans: [NormalizedXMPWritePlan] = [],
        artifacts: NormalizationArtifactPlan,
        deterministicPolicy: NormalizationDeterministicPolicyRecord,
        warnings: [SidecarError],
        errors: [SidecarError]
    ) {
        self.schemaVersion = schemaVersion
        self.session = session
        self.vocabulary = vocabulary
        self.resolvedConfiguration = resolvedConfiguration
        self.sessionContext = sessionContext
        self.privacy = privacy
        self.xmpWriter = xmpWriter
        self.sourceAISidecars = sourceAISidecars
        self.sourceAssets = sourceAssets
        self.sameBaseNameGroups = sameBaseNameGroups
        self.affinity = affinity
        self.batchCandidates = batchCandidates
        self.localConsensus = localConsensus
        self.perAssetDecisions = perAssetDecisions
        self.xmpWritePlans = xmpWritePlans
        self.artifacts = artifacts
        self.deterministicPolicy = deterministicPolicy
        self.warnings = warnings
        self.errors = errors
    }
}

/// Writes normalization sessions atomically with stable JSON formatting.
public struct NormalizationSessionWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func write(_ session: NormalizationSessionDocument, to path: String) throws {
        do {
            let data = try encoder.encode(session)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write normalization session \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
