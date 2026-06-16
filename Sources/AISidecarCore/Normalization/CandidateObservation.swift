import Foundation

/// Candidate text provenance after Phase 2 extraction and before vocabulary policy.
///
/// Phase 3 keeps this layer separate from final decisions so reports can explain
/// why model terms were canonicalized, withheld, or ignored without re-reading
/// raw model JSON during `apply-session`.
public struct CandidateObservation: Codable, Sendable, Equatable {
    public var observationID: String
    public var assetID: String
    public var groupID: String?
    public var term: String
    public var normalizedTerm: String
    public var foldedTerm: String
    public var confidence: XMPMinimumConfidence
    public var evidence: String?
    public var provenance: CandidateProvenance

    enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case assetID = "asset_id"
        case groupID = "group_id"
        case term
        case normalizedTerm = "normalized_term"
        case foldedTerm = "folded_term"
        case confidence
        case evidence
        case provenance
    }

    public init(
        observationID: String,
        assetID: String,
        groupID: String?,
        term: String,
        normalizedTerm: String,
        foldedTerm: String,
        confidence: XMPMinimumConfidence,
        evidence: String?,
        provenance: CandidateProvenance
    ) {
        self.observationID = observationID
        self.assetID = assetID
        self.groupID = groupID
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.foldedTerm = foldedTerm
        self.confidence = confidence
        self.evidence = evidence
        self.provenance = provenance
    }
}

/// Stable skip reasons emitted by the Phase 3 candidate and decision layer.
public enum NormalizationCandidateSkipReason: String, Codable, CaseIterable, Sendable, Hashable {
    case belowConfidenceThreshold = "below_confidence_threshold"
    case unmatchedVocabulary = "unmatched_vocabulary"
    case directApplyWithheld = "direct_apply_withheld"
    case directApplyFlatOnly = "direct_apply_flat_only"
    case requiresReview = "requires_review"
    case specificTagPolicy = "specific_tag_policy"
    case containsHierarchySeparator = "contains_hierarchy_separator"
    case emptyAfterNormalization = "empty_after_normalization"
    case duplicate
    case disabledFlatExport = "disabled_flat_export"
    case disabledHierarchicalExport = "disabled_hierarchical_export"
    case coordinateLikeTerm = "coordinate_like_term"
    case gpsOnlyEvidence = "gps_only_evidence"
    case unknownSessionContextRejected = "unknown_session_context_rejected"
    case unknownSessionContextFlatOnly = "unknown_session_context_flat_only"
}

/// One candidate-level skip or decision-policy block recorded in the session.
public struct NormalizationCandidateSkip: Codable, Sendable, Equatable {
    public var skipID: String
    public var reason: NormalizationCandidateSkipReason
    public var assetID: String?
    public var groupID: String?
    public var observationID: String?
    public var term: String?
    public var normalizedTerm: String?
    public var foldedTerm: String?
    public var canonicalPath: String?
    public var sourceSidecar: String?
    public var sourceImage: String?
    public var sourceField: CandidateSourceField?
    public var inputRole: ModelInputRole?
    public var modelRunIndex: Int?

    enum CodingKeys: String, CodingKey {
        case skipID = "skip_id"
        case reason
        case assetID = "asset_id"
        case groupID = "group_id"
        case observationID = "observation_id"
        case term
        case normalizedTerm = "normalized_term"
        case foldedTerm = "folded_term"
        case canonicalPath = "canonical_path"
        case sourceSidecar = "source_sidecar"
        case sourceImage = "source_image"
        case sourceField = "source_field"
        case inputRole = "input_role"
        case modelRunIndex = "model_run_index"
    }

    public init(
        skipID: String,
        reason: NormalizationCandidateSkipReason,
        assetID: String? = nil,
        groupID: String? = nil,
        observationID: String? = nil,
        term: String? = nil,
        normalizedTerm: String? = nil,
        foldedTerm: String? = nil,
        canonicalPath: String? = nil,
        sourceSidecar: String? = nil,
        sourceImage: String? = nil,
        sourceField: CandidateSourceField? = nil,
        inputRole: ModelInputRole? = nil,
        modelRunIndex: Int? = nil
    ) {
        self.skipID = skipID
        self.reason = reason
        self.assetID = assetID
        self.groupID = groupID
        self.observationID = observationID
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.foldedTerm = foldedTerm
        self.canonicalPath = canonicalPath
        self.sourceSidecar = sourceSidecar
        self.sourceImage = sourceImage
        self.sourceField = sourceField
        self.inputRole = inputRole
        self.modelRunIndex = modelRunIndex
    }
}

/// Result of converting Phase 2 extraction output into Phase 3 observations.
public struct CandidateObservationExtraction: Sendable, Equatable {
    public var observations: [CandidateObservation]
    public var observationByKey: [CandidateObservationKey: CandidateObservation]
    public var sourceAssetIDBySidecarPath: [String: String]
    public var groupIDByAssetID: [String: String]

    public init(
        observations: [CandidateObservation],
        observationByKey: [CandidateObservationKey: CandidateObservation],
        sourceAssetIDBySidecarPath: [String: String],
        groupIDByAssetID: [String: String]
    ) {
        self.observations = observations
        self.observationByKey = observationByKey
        self.sourceAssetIDBySidecarPath = sourceAssetIDBySidecarPath
        self.groupIDByAssetID = groupIDByAssetID
    }
}

/// Hashable identity for one extracted model candidate within a source sidecar.
public struct CandidateObservationKey: Hashable, Sendable {
    public var sourceSidecar: String
    public var sourceImage: String
    public var modelRunIndex: Int
    public var sourceField: CandidateSourceField
    public var inputRole: ModelInputRole
    public var term: String
    public var normalizedTerm: String

    public init(candidate: ExtractedCandidate) {
        self.sourceSidecar = candidate.provenance.sourceSidecar
        self.sourceImage = candidate.provenance.sourceImage
        self.modelRunIndex = candidate.provenance.modelRunIndex
        self.sourceField = candidate.provenance.sourceField
        self.inputRole = candidate.provenance.inputRole
        self.term = candidate.term
        self.normalizedTerm = candidate.normalizedTerm
    }
}

/// Builds Phase 3 observation records from Phase 2 extraction results.
public struct CandidateObservationBuilder {
    public init() {}

    public func build(
        extractionResults: [CandidateExtractionResult],
        input: NormalizationResolvedInputBatch
    ) -> CandidateObservationExtraction {
        let assetIDBySidecarPath = Dictionary(
            uniqueKeysWithValues: input.sourceAISidecars.map { ($0.sidecarPath, $0.sourceAssetID) }
        )
        let groupIDByAssetID = Dictionary(
            uniqueKeysWithValues: input.sameBaseNameGroups.flatMap { group in
                group.memberAssetIDs.map { ($0, group.groupID) }
            }
        )
        var observations: [CandidateObservation] = []
        var observationByKey: [CandidateObservationKey: CandidateObservation] = [:]

        for result in extractionResults {
            guard let assetID = assetIDBySidecarPath[result.sourceSidecar] else {
                continue
            }
            for candidate in result.extractedCandidates {
                let observation = CandidateObservation(
                    observationID: String(format: "obs-%06d", observations.count + 1),
                    assetID: assetID,
                    groupID: groupIDByAssetID[assetID],
                    term: candidate.term,
                    normalizedTerm: candidate.normalizedTerm,
                    foldedTerm: VocabularyTextFolder.fold(candidate.normalizedTerm),
                    confidence: candidate.confidence,
                    evidence: candidate.evidence,
                    provenance: candidate.provenance
                )
                observations.append(observation)
                observationByKey[CandidateObservationKey(candidate: candidate)] = observation
            }
        }

        return CandidateObservationExtraction(
            observations: observations,
            observationByKey: observationByKey,
            sourceAssetIDBySidecarPath: assetIDBySidecarPath,
            groupIDByAssetID: groupIDByAssetID
        )
    }
}
