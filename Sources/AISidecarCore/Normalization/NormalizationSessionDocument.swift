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
    public var directApplyPolicy: DirectApplyPolicy?
    public var propagationAllowed: Bool
    public var conflictCount: Int
    public var exportResult: String

    enum CodingKeys: String, CodingKey {
        case contextType = "context_type"
        case originalText = "original_text"
        case foldedText = "folded_text"
        case matchedCanonicalPath = "matched_canonical_path"
        case unknownPolicyResult = "unknown_policy_result"
        case directApplyPolicy = "direct_apply_policy"
        case propagationAllowed = "propagation_allowed"
        case conflictCount = "conflict_count"
        case exportResult = "export_result"
    }

    public init(
        contextType: NormalizationSessionContextType,
        originalText: String,
        foldedText: String,
        matchedCanonicalPath: String?,
        unknownPolicyResult: String,
        directApplyPolicy: DirectApplyPolicy?,
        propagationAllowed: Bool,
        conflictCount: Int = 0,
        exportResult: String
    ) {
        self.contextType = contextType
        self.originalText = originalText
        self.foldedText = foldedText
        self.matchedCanonicalPath = matchedCanonicalPath
        self.unknownPolicyResult = unknownPolicyResult
        self.directApplyPolicy = directApplyPolicy
        self.propagationAllowed = propagationAllowed
        self.conflictCount = conflictCount
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
    public var edges: [AssetAffinityEdgeRecord]
    public var clusters: [NormalizationClusterRecord]

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
        edges: [AssetAffinityEdgeRecord] = [],
        clusters: [NormalizationClusterRecord] = []
    ) {
        self.mode = mode
        self.profile = profile
        self.minAffinityForConsensus = minAffinityForConsensus
        self.nodes = nodes
        self.edges = edges
        self.clusters = clusters
    }
}

/// Normalized candidate category recorded in batch summaries.
public enum NormalizedCandidateKind: String, Codable, Sendable, Equatable {
    case canonicalVocabulary = "canonical_vocabulary"
    case observedModelTag = "observed_model_tag"
    case modelSpeciesFallback = "model_species_fallback"
    case phase2Fallback = "phase2_fallback"
    case userContextUnnormalized = "user_context_unnormalized"
    // Additive (Phase 4 review, invariant 7): the user replaced the keyword
    // text during review; `source_text` preserves the original term.
    case userEdited = "user_edited"
}

/// Summary of direct support for one normalized or fallback candidate.
public struct BatchCandidateSummary: Codable, Sendable, Equatable {
    public var candidateKind: NormalizedCandidateKind
    public var canonicalPath: String?
    public var flatKeyword: String?
    public var hierarchicalKeyword: String?
    public var namespace: VocabularyNamespace?
    public var supportingAssetIDs: [String]
    public var directAssetSupportCount: Int
    public var eligibleAssetCount: Int
    public var agreementFrequency: Double?
    public var observationCount: Int
    public var confidenceBands: [String: Int]
    public var sourceFields: [String: Int]
    public var inputRoles: [String: Int]

    enum CodingKeys: String, CodingKey {
        case candidateKind = "candidate_kind"
        case canonicalPath = "canonical_path"
        case flatKeyword = "flat_keyword"
        case hierarchicalKeyword = "hierarchical_keyword"
        case namespace
        case supportingAssetIDs = "supporting_asset_ids"
        case directAssetSupportCount = "direct_asset_support_count"
        case eligibleAssetCount = "eligible_asset_count"
        case agreementFrequency = "agreement_frequency"
        case observationCount = "observation_count"
        case confidenceBands = "confidence_bands"
        case sourceFields = "source_fields"
        case inputRoles = "input_roles"
    }

    public init(
        candidateKind: NormalizedCandidateKind = .canonicalVocabulary,
        canonicalPath: String? = nil,
        flatKeyword: String? = nil,
        hierarchicalKeyword: String? = nil,
        namespace: VocabularyNamespace? = nil,
        supportingAssetIDs: [String] = [],
        directAssetSupportCount: Int = 0,
        eligibleAssetCount: Int = 0,
        agreementFrequency: Double? = nil,
        observationCount: Int = 0,
        confidenceBands: [String: Int] = [:],
        sourceFields: [String: Int] = [:],
        inputRoles: [String: Int] = [:]
    ) {
        self.candidateKind = candidateKind
        self.canonicalPath = canonicalPath
        self.flatKeyword = flatKeyword
        self.hierarchicalKeyword = hierarchicalKeyword
        self.namespace = namespace
        self.supportingAssetIDs = supportingAssetIDs
        self.directAssetSupportCount = directAssetSupportCount
        self.eligibleAssetCount = eligibleAssetCount
        self.agreementFrequency = agreementFrequency
        self.observationCount = observationCount
        self.confidenceBands = confidenceBands
        self.sourceFields = sourceFields
        self.inputRoles = inputRoles
    }
}

/// Local weighted consensus diagnostics for one target and candidate path.
public struct LocalWeightedConsensusRecord: Codable, Sendable, Equatable {
    public var targetAssetID: String
    public var targetNodeID: String?
    public var canonicalPath: String
    public var localWeightedAgreement: Double?
    public var supportMass: Double
    public var eligibleMass: Double
    public var supportingNeighborCount: Int
    public var maxSupportingAffinity: Double
    public var conflictSupportMass: Double
    public var conflictWeightedAgreement: Double?
    public var conflictingCanonicalPaths: [String]
    public var decisionEligible: Bool
    public var blockReasons: [NormalizationCandidateSkipReason]
    public var governingRule: String

    enum CodingKeys: String, CodingKey {
        case targetAssetID = "target_asset_id"
        case targetNodeID = "target_node_id"
        case canonicalPath = "canonical_path"
        case localWeightedAgreement = "local_weighted_agreement"
        case supportMass = "support_mass"
        case eligibleMass = "eligible_mass"
        case supportingNeighborCount = "supporting_neighbor_count"
        case maxSupportingAffinity = "max_supporting_affinity"
        case conflictSupportMass = "conflict_support_mass"
        case conflictWeightedAgreement = "conflict_weighted_agreement"
        case conflictingCanonicalPaths = "conflicting_canonical_paths"
        case decisionEligible = "decision_eligible"
        case blockReasons = "block_reasons"
        case governingRule = "governing_rule"
    }

    public init(
        targetAssetID: String = "",
        targetNodeID: String? = nil,
        canonicalPath: String = "",
        localWeightedAgreement: Double? = nil,
        supportMass: Double = 0,
        eligibleMass: Double = 0,
        supportingNeighborCount: Int = 0,
        maxSupportingAffinity: Double = 0,
        conflictSupportMass: Double = 0,
        conflictWeightedAgreement: Double? = nil,
        conflictingCanonicalPaths: [String] = [],
        decisionEligible: Bool = false,
        blockReasons: [NormalizationCandidateSkipReason] = [],
        governingRule: String = ""
    ) {
        self.targetAssetID = targetAssetID
        self.targetNodeID = targetNodeID
        self.canonicalPath = canonicalPath
        self.localWeightedAgreement = localWeightedAgreement
        self.supportMass = supportMass
        self.eligibleMass = eligibleMass
        self.supportingNeighborCount = supportingNeighborCount
        self.maxSupportingAffinity = maxSupportingAffinity
        self.conflictSupportMass = conflictSupportMass
        self.conflictWeightedAgreement = conflictWeightedAgreement
        self.conflictingCanonicalPaths = conflictingCanonicalPaths
        self.decisionEligible = decisionEligible
        self.blockReasons = blockReasons
        self.governingRule = governingRule
    }
}

/// Ordered stage that first created a Phase 3 per-asset decision.
public enum NormalizationDecisionStage: String, Codable, Sendable, Equatable {
    case directModelObservation = "direct_model_observation"
    case userSessionContext = "user_session_context"
    case localAffinityPropagation = "local_affinity_propagation"
    case globalBackstopPropagation = "global_backstop_propagation"
    case phase2Fallback = "phase2_fallback"
}

/// Export status for a direct normalization decision before XMP writing.
public enum NormalizationDecisionStatus: String, Codable, Sendable, Equatable {
    case accepted
    case withheld
    case skipped
}

private enum TolerantStringEnum<Value: RawRepresentable> where Value.RawValue == String {
    case known(Value)
    case unknown(String)

    init(rawValue: String) {
        if let value = Value(rawValue: rawValue) {
            self = .known(value)
        } else {
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .known(let value):
            value.rawValue
        case .unknown(let rawValue):
            rawValue
        }
    }
}

extension TolerantStringEnum: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Per-asset decision emitted before later milestones adapt decisions into XMP plans.
public struct PerAssetNormalizationDecision: Codable, Sendable, Equatable {
    public var decisionID: String
    public var assetID: String
    public var groupID: String?
    public var stage: NormalizationDecisionStage
    public var status: NormalizationDecisionStatus
    public var candidateKind: NormalizedCandidateKind
    public var canonicalPath: String?
    public var flatKeyword: String?
    public var hierarchicalKeyword: String?
    public var sourceText: String?
    public var contextType: NormalizationSessionContextType?
    public var namespace: VocabularyNamespace?
    public var directApplyPolicy: DirectApplyPolicy?
    public var requiresReview: Bool
    public var exportFlatKeyword: Bool
    public var exportHierarchicalKeyword: Bool
    public var supportUnits: Int
    public var supportingAssetIDs: [String]
    public var governingRule: String?
    public var observationCount: Int
    public var skipReasons: [NormalizationCandidateSkipReason]
    public var localConsensus: LocalWeightedConsensusRecord?
    public var observations: [CandidateObservation]
    private var forwardCompatUnknownStatus: String?
    private var forwardCompatUnknownCandidateKind: String?
    private var forwardCompatUnknownSkipReasons: [String]

    /// A future additive enum affected this decision. The document remains
    /// readable, but this decision is fail-closed and cannot export.
    public var isForwardCompatUnknown: Bool {
        forwardCompatUnknownStatus != nil
            || forwardCompatUnknownCandidateKind != nil
            || !forwardCompatUnknownSkipReasons.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case decisionID = "decision_id"
        case assetID = "asset_id"
        case groupID = "group_id"
        case stage
        case status
        case candidateKind = "candidate_kind"
        case canonicalPath = "canonical_path"
        case flatKeyword = "flat_keyword"
        case hierarchicalKeyword = "hierarchical_keyword"
        case sourceText = "source_text"
        case contextType = "context_type"
        case namespace
        case directApplyPolicy = "direct_apply_policy"
        case requiresReview = "requires_review"
        case exportFlatKeyword = "export_flat_keyword"
        case exportHierarchicalKeyword = "export_hierarchical_keyword"
        case supportUnits = "support_units"
        case supportingAssetIDs = "supporting_asset_ids"
        case governingRule = "governing_rule"
        case observationCount = "observation_count"
        case skipReasons = "skip_reasons"
        case localConsensus = "local_consensus"
        case observations
    }

    public init(
        decisionID: String = "",
        assetID: String = "",
        groupID: String? = nil,
        stage: NormalizationDecisionStage = .directModelObservation,
        status: NormalizationDecisionStatus = .skipped,
        candidateKind: NormalizedCandidateKind = .canonicalVocabulary,
        canonicalPath: String? = nil,
        flatKeyword: String? = nil,
        hierarchicalKeyword: String? = nil,
        sourceText: String? = nil,
        contextType: NormalizationSessionContextType? = nil,
        namespace: VocabularyNamespace? = nil,
        directApplyPolicy: DirectApplyPolicy? = nil,
        requiresReview: Bool = false,
        exportFlatKeyword: Bool = false,
        exportHierarchicalKeyword: Bool = false,
        supportUnits: Int = 0,
        supportingAssetIDs: [String] = [],
        governingRule: String? = nil,
        observationCount: Int = 0,
        skipReasons: [NormalizationCandidateSkipReason] = [],
        localConsensus: LocalWeightedConsensusRecord? = nil,
        observations: [CandidateObservation] = []
    ) {
        self.decisionID = decisionID
        self.assetID = assetID
        self.groupID = groupID
        self.stage = stage
        self.status = status
        self.candidateKind = candidateKind
        self.canonicalPath = canonicalPath
        self.flatKeyword = flatKeyword
        self.hierarchicalKeyword = hierarchicalKeyword
        self.sourceText = sourceText
        self.contextType = contextType
        self.namespace = namespace
        self.directApplyPolicy = directApplyPolicy
        self.requiresReview = requiresReview
        self.exportFlatKeyword = exportFlatKeyword
        self.exportHierarchicalKeyword = exportHierarchicalKeyword
        self.supportUnits = supportUnits
        self.supportingAssetIDs = supportingAssetIDs
        self.governingRule = governingRule
        self.observationCount = observationCount
        self.skipReasons = skipReasons
        self.localConsensus = localConsensus
        self.observations = observations
        self.forwardCompatUnknownStatus = nil
        self.forwardCompatUnknownCandidateKind = nil
        self.forwardCompatUnknownSkipReasons = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decisionID = try container.decode(String.self, forKey: .decisionID)
        assetID = try container.decode(String.self, forKey: .assetID)
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        stage = try container.decode(NormalizationDecisionStage.self, forKey: .stage)

        let tolerantStatus = try container.decode(
            TolerantStringEnum<NormalizationDecisionStatus>.self,
            forKey: .status
        )
        switch tolerantStatus {
        case .known(let value):
            status = value
            forwardCompatUnknownStatus = nil
        case .unknown(let rawValue):
            status = .withheld
            forwardCompatUnknownStatus = rawValue
        }

        let tolerantCandidateKind = try container.decode(
            TolerantStringEnum<NormalizedCandidateKind>.self,
            forKey: .candidateKind
        )
        switch tolerantCandidateKind {
        case .known(let value):
            candidateKind = value
            forwardCompatUnknownCandidateKind = nil
        case .unknown(let rawValue):
            candidateKind = .phase2Fallback
            forwardCompatUnknownCandidateKind = rawValue
        }

        canonicalPath = try container.decodeIfPresent(String.self, forKey: .canonicalPath)
        flatKeyword = try container.decodeIfPresent(String.self, forKey: .flatKeyword)
        hierarchicalKeyword = try container.decodeIfPresent(String.self, forKey: .hierarchicalKeyword)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        contextType = try container.decodeIfPresent(NormalizationSessionContextType.self, forKey: .contextType)
        namespace = try container.decodeIfPresent(VocabularyNamespace.self, forKey: .namespace)
        directApplyPolicy = try container.decodeIfPresent(DirectApplyPolicy.self, forKey: .directApplyPolicy)
        requiresReview = try container.decode(Bool.self, forKey: .requiresReview)
        exportFlatKeyword = try container.decode(Bool.self, forKey: .exportFlatKeyword)
        exportHierarchicalKeyword = try container.decode(Bool.self, forKey: .exportHierarchicalKeyword)
        supportUnits = try container.decode(Int.self, forKey: .supportUnits)
        supportingAssetIDs = try container.decode([String].self, forKey: .supportingAssetIDs)
        governingRule = try container.decodeIfPresent(String.self, forKey: .governingRule)
        observationCount = try container.decode(Int.self, forKey: .observationCount)

        let tolerantSkipReasons = try container.decode(
            [TolerantStringEnum<NormalizationCandidateSkipReason>].self,
            forKey: .skipReasons
        )
        skipReasons = tolerantSkipReasons.compactMap { reason in
            guard case .known(let value) = reason else {
                return nil
            }
            return value
        }
        forwardCompatUnknownSkipReasons = tolerantSkipReasons.compactMap { reason in
            guard case .unknown(let rawValue) = reason else {
                return nil
            }
            return rawValue
        }

        localConsensus = try container.decodeIfPresent(LocalWeightedConsensusRecord.self, forKey: .localConsensus)
        observations = try container.decode([CandidateObservation].self, forKey: .observations)

        if isForwardCompatUnknown {
            status = .withheld
            exportFlatKeyword = false
            exportHierarchicalKeyword = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(decisionID, forKey: .decisionID)
        try container.encode(assetID, forKey: .assetID)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encode(stage, forKey: .stage)
        try container.encode(
            TolerantStringEnum<NormalizationDecisionStatus>(
                rawValue: forwardCompatUnknownStatus ?? status.rawValue
            ),
            forKey: .status
        )
        try container.encode(
            TolerantStringEnum<NormalizedCandidateKind>(
                rawValue: forwardCompatUnknownCandidateKind ?? candidateKind.rawValue
            ),
            forKey: .candidateKind
        )
        try container.encodeIfPresent(canonicalPath, forKey: .canonicalPath)
        try container.encodeIfPresent(flatKeyword, forKey: .flatKeyword)
        try container.encodeIfPresent(hierarchicalKeyword, forKey: .hierarchicalKeyword)
        try container.encodeIfPresent(sourceText, forKey: .sourceText)
        try container.encodeIfPresent(contextType, forKey: .contextType)
        try container.encodeIfPresent(namespace, forKey: .namespace)
        try container.encodeIfPresent(directApplyPolicy, forKey: .directApplyPolicy)
        try container.encode(requiresReview, forKey: .requiresReview)
        try container.encode(exportFlatKeyword, forKey: .exportFlatKeyword)
        try container.encode(exportHierarchicalKeyword, forKey: .exportHierarchicalKeyword)
        try container.encode(supportUnits, forKey: .supportUnits)
        try container.encode(supportingAssetIDs, forKey: .supportingAssetIDs)
        try container.encodeIfPresent(governingRule, forKey: .governingRule)
        try container.encode(observationCount, forKey: .observationCount)
        let encodedSkipReasons = skipReasons.map {
            TolerantStringEnum<NormalizationCandidateSkipReason>.known($0)
        } + forwardCompatUnknownSkipReasons.map {
            TolerantStringEnum<NormalizationCandidateSkipReason>.unknown($0)
        }
        try container.encode(encodedSkipReasons, forKey: .skipReasons)
        try container.encodeIfPresent(localConsensus, forKey: .localConsensus)
        try container.encode(observations, forKey: .observations)
    }
}

/// Managed keyword bag targeted by a normalized XMP term.
public enum NormalizedXMPKeywordBag: String, Codable, Sendable, Equatable {
    case flat = "dc_subject"
    case hierarchical = "lr_hierarchical_subject"
}

/// Phase 3 decision provenance retained for one planned XMP keyword.
public struct NormalizedXMPKeywordProvenance: Codable, Sendable, Equatable {
    public var term: String
    public var normalizedKey: String
    public var keywordBag: NormalizedXMPKeywordBag
    public var decisionIDs: [String]
    public var assetIDs: [String]
    public var stages: [NormalizationDecisionStage]
    public var candidateKinds: [NormalizedCandidateKind]
    public var canonicalPaths: [String]
    public var observationIDs: [String]
    public var sourceTexts: [String]
    public var contextTypes: [NormalizationSessionContextType]
    public var governingRules: [String]
    public var supportingAssetIDs: [String]

    enum CodingKeys: String, CodingKey {
        case term
        case normalizedKey = "normalized_key"
        case keywordBag = "keyword_bag"
        case decisionIDs = "decision_ids"
        case assetIDs = "asset_ids"
        case stages
        case candidateKinds = "candidate_kinds"
        case canonicalPaths = "canonical_paths"
        case observationIDs = "observation_ids"
        case sourceTexts = "source_texts"
        case contextTypes = "context_types"
        case governingRules = "governing_rules"
        case supportingAssetIDs = "supporting_asset_ids"
    }

    public init(
        term: String,
        normalizedKey: String,
        keywordBag: NormalizedXMPKeywordBag,
        decisionIDs: [String],
        assetIDs: [String],
        stages: [NormalizationDecisionStage],
        candidateKinds: [NormalizedCandidateKind],
        canonicalPaths: [String],
        observationIDs: [String],
        sourceTexts: [String],
        contextTypes: [NormalizationSessionContextType],
        governingRules: [String],
        supportingAssetIDs: [String]
    ) {
        self.term = term
        self.normalizedKey = normalizedKey
        self.keywordBag = keywordBag
        self.decisionIDs = decisionIDs
        self.assetIDs = assetIDs
        self.stages = stages
        self.candidateKinds = candidateKinds
        self.canonicalPaths = canonicalPaths
        self.observationIDs = observationIDs
        self.sourceTexts = sourceTexts
        self.contextTypes = contextTypes
        self.governingRules = governingRules
        self.supportingAssetIDs = supportingAssetIDs
    }
}

/// Normalized XMP plan plus Phase 3 provenance consumed later by `apply-session`.
public struct NormalizedXMPWritePlan: Codable, Sendable, Equatable {
    public var xmpChangePlan: XMPChangePlan
    public var flatKeywordProvenance: [NormalizedXMPKeywordProvenance]
    public var hierarchicalKeywordProvenance: [NormalizedXMPKeywordProvenance]
    public var normalizationSkips: [NormalizationCandidateSkip]

    enum CodingKeys: String, CodingKey {
        case xmpChangePlan = "xmp_change_plan"
        case flatKeywordProvenance = "flat_keyword_provenance"
        case hierarchicalKeywordProvenance = "hierarchical_keyword_provenance"
        case normalizationSkips = "normalization_skips"
    }

    public init(
        xmpChangePlan: XMPChangePlan,
        flatKeywordProvenance: [NormalizedXMPKeywordProvenance],
        hierarchicalKeywordProvenance: [NormalizedXMPKeywordProvenance],
        normalizationSkips: [NormalizationCandidateSkip]
    ) {
        self.xmpChangePlan = xmpChangePlan
        self.flatKeywordProvenance = flatKeywordProvenance
        self.hierarchicalKeywordProvenance = hierarchicalKeywordProvenance
        self.normalizationSkips = normalizationSkips
    }
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
    public var candidateObservations: [CandidateObservation]
    public var candidateSkips: [NormalizationCandidateSkip]
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
        case candidateObservations = "candidate_observations"
        case candidateSkips = "candidate_skips"
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
        candidateObservations: [CandidateObservation] = [],
        candidateSkips: [NormalizationCandidateSkip] = [],
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
        self.candidateObservations = candidateObservations
        self.candidateSkips = candidateSkips
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
        self.encoder = JSONCoding.documentEncoder()
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

/// Reads Phase 3 normalization sessions and rejects unsupported schema majors before use.
public struct NormalizationSessionReader {
    private let fileManager: FileManager

    /// Create a reader for durable `ai-sidecar-normalization/1.0` sessions.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Decode a normalization session from disk after checking the schema identifier.
    public func read(from path: String) throws -> NormalizationSessionDocument {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            guard let object = json.objectValue else {
                throw SidecarError(
                    code: .schemaUnsupported,
                    stage: .write,
                    message: "Normalization session document must be a JSON object.",
                    recoverable: false
                )
            }
            guard let schemaVersion = object["schema_version"]?.stringValue else {
                throw SidecarError(
                    code: .schemaUnsupported,
                    stage: .write,
                    message: "Normalization session document is missing schema_version.",
                    recoverable: false
                )
            }
            try Self.validateSchemaVersion(schemaVersion)

            let decoder = JSONCoding.decoder()
            let document = try decoder.decode(NormalizationSessionDocument.self, from: data)
            try Self.validateStructuralUniqueness(document)
            return document
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .decodeFailed,
                stage: .write,
                message: "Unable to read normalization session \(url.path): \(error.localizedDescription)",
                recoverable: false
            )
        }
    }

    private static func validateSchemaVersion(_ schemaVersion: String) throws {
        guard
            let slashIndex = schemaVersion.firstIndex(of: "/"),
            schemaVersion[..<slashIndex] == "ai-sidecar-normalization"
        else {
            throw unsupportedSchema(schemaVersion)
        }

        let version = schemaVersion[schemaVersion.index(after: slashIndex)...]
        let majorText = version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let majorText, let major = Int(majorText), major == 1 else {
            throw unsupportedSchema(schemaVersion)
        }
    }

    private static func validateStructuralUniqueness(_ document: NormalizationSessionDocument) throws {
        _ = try uniqueLookup(
            document.sourceAssets.map { ($0.assetID, $0) },
            onDuplicate: { assetID in
                SidecarError(
                    code: .sessionStale,
                    stage: .normalize,
                    message: "Duplicate source asset ID in session document: \(assetID)",
                    recoverable: false
                )
            }
        )
        _ = try uniqueLookup(
            document.sourceAISidecars.map { ($0.sourceAssetID, $0) },
            onDuplicate: { assetID in
                SidecarError(
                    code: .sessionStale,
                    stage: .normalize,
                    message: "Duplicate source-sidecar asset ID in session document: \(assetID)",
                    recoverable: false
                )
            }
        )
    }

    private static func unsupportedSchema(_ schemaVersion: String) -> SidecarError {
        SidecarError(
            code: .schemaUnsupported,
            stage: .write,
            message: "Unsupported normalization session schema version: \(schemaVersion).",
            recoverable: false
        )
    }
}
