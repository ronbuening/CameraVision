import Foundation

/// Output of Phase 3 candidate observation filtering and direct canonicalization.
public struct CandidateCanonicalizationResult: Sendable, Equatable {
    public var sessionContext: [NormalizationSessionContextRecord]
    public var observations: [CandidateObservation]
    public var skips: [NormalizationCandidateSkip]
    public var batchCandidates: [BatchCandidateSummary]
    public var perAssetDecisions: [PerAssetNormalizationDecision]

    public init(
        sessionContext: [NormalizationSessionContextRecord],
        observations: [CandidateObservation],
        skips: [NormalizationCandidateSkip],
        batchCandidates: [BatchCandidateSummary],
        perAssetDecisions: [PerAssetNormalizationDecision]
    ) {
        self.sessionContext = sessionContext
        self.observations = observations
        self.skips = skips
        self.batchCandidates = batchCandidates
        self.perAssetDecisions = perAssetDecisions
    }
}

/// Applies Phase 3 vocabulary matching and direct-apply policy to model candidates.
public struct CandidateCanonicalizer {
    private let vocabulary: LoadedVocabulary
    private let observationBuilder: CandidateObservationBuilder
    private let lookupCache: CandidateCanonicalizerLookupCache

    public init(
        vocabulary: LoadedVocabulary,
        observationBuilder: CandidateObservationBuilder = CandidateObservationBuilder()
    ) {
        self.vocabulary = vocabulary
        self.observationBuilder = observationBuilder
        self.lookupCache = CandidateCanonicalizerLookupCache(vocabulary: vocabulary)
    }

    /// Reject unknown session context before any expensive analysis or writing can start.
    public static func preflightSessionContext(
        configuration: ResolvedNormalizationConfiguration,
        vocabulary: LoadedVocabulary
    ) throws {
        try CandidateCanonicalizer(vocabulary: vocabulary).preflightSessionContext(configuration: configuration)
    }

    func preflightSessionContext(configuration: ResolvedNormalizationConfiguration) throws {
        guard configuration.normalizationMode != .off else {
            return
        }
        for context in Self.sessionContextInputs(configuration) {
            let normalized = KeywordTextNormalizer.normalize(context.value)
            let folded = lookupCache.fold(normalized)
            guard !folded.isEmpty else {
                continue
            }
            guard !KeywordSafetyPolicy.isUnsafeKeyword(normalized) else {
                throw SidecarError(
                    code: .validationFailed,
                    stage: .normalize,
                    message: "Session context cannot contain GPS metadata or coordinate syntax: \(context.value)",
                    recoverable: false
                )
            }
            if configuration.vocabularyMode == .observedTags {
                if configuration.unknownSessionContextPolicy == .reject {
                    throw SidecarError(
                        code: .validationFailed,
                        stage: .normalize,
                        message:
                            "Session context requires controlled-vocabulary mode or unknown-session-context-policy write-unnormalized: \(context.value)",
                        recoverable: false
                    )
                }
                if context.value.contains("|") {
                    throw SidecarError(
                        code: .validationFailed,
                        stage: .normalize,
                        message:
                            "Unnormalized session context cannot contain the hierarchy separator: \(context.value)",
                        recoverable: false
                    )
                }
                continue
            }
            if lookupCache.entry(matching: context.value) == nil,
                configuration.unknownSessionContextPolicy == .reject
            {
                throw SidecarError(
                    code: .validationFailed,
                    stage: .normalize,
                    message:
                        "Unknown \(context.type.rawValue) session context does not match vocabulary: \(context.value)",
                    recoverable: false
                )
            }
            if lookupCache.entry(matching: context.value) == nil,
                context.value.contains("|")
            {
                throw SidecarError(
                    code: .validationFailed,
                    stage: .normalize,
                    message: "Unnormalized session context cannot contain the hierarchy separator: \(context.value)",
                    recoverable: false
                )
            }
        }
    }

    /// Canonicalize Phase 2 extraction results for the resolved Phase 3 input batch.
    public func canonicalize(
        extractionResults: [CandidateExtractionResult],
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration
    ) throws -> CandidateCanonicalizationResult {
        let observationExtraction = try observationBuilder.build(
            extractionResults: extractionResults,
            input: input
        )
        let contextRecords = makeSessionContextRecords(
            configuration: configuration,
            input: input,
            groupIDByAssetID: observationExtraction.groupIDByAssetID
        )

        switch configuration.normalizationMode {
        case .off:
            return phase2FallbackResult(
                extractionResults: extractionResults,
                input: input,
                observationExtraction: observationExtraction,
                contextRecords: contextRecords
            )
        case .singleImage, .batchConservative:
            if configuration.vocabularyMode == .observedTags {
                return observedTagsResult(
                    extractionResults: extractionResults,
                    input: input,
                    configuration: configuration,
                    observationExtraction: observationExtraction,
                    contextRecords: contextRecords
                )
            }
            return vocabularyResult(
                extractionResults: extractionResults,
                input: input,
                configuration: configuration,
                observationExtraction: observationExtraction,
                contextRecords: contextRecords
            )
        }
    }

    private func observedTagsResult(
        extractionResults: [CandidateExtractionResult],
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        observationExtraction: CandidateObservationExtraction,
        contextRecords: [NormalizationSessionContextRecord]
    ) -> CandidateCanonicalizationResult {
        let blockingReasons = fallbackBlockingReasonsByObservationKey(extractionResults)
        var skips: [NormalizationCandidateSkip] = []
        var accumulators: [DirectDecisionKey: DirectDecisionAccumulator] = [:]
        var order: [DirectDecisionKey] = []

        for result in extractionResults {
            guard let assetID = observationExtraction.sourceAssetIDBySidecarPath[result.sourceSidecar] else {
                continue
            }

            for candidate in result.extractedCandidates {
                let key = CandidateObservationKey(candidate: candidate)
                guard let observation = observationExtraction.observationByKey[key] else {
                    continue
                }

                if candidate.normalizedTerm.isEmpty {
                    appendSkip(&skips, reason: .emptyAfterNormalization, observation: observation)
                    continue
                }
                if candidate.normalizedTerm.contains("|") {
                    appendSkip(&skips, reason: .containsHierarchySeparator, observation: observation)
                    continue
                }
                if candidate.confidence < configuration.minConfidence {
                    appendSkip(&skips, reason: .belowConfidenceThreshold, observation: observation)
                    continue
                }
                if let blockingReason = blockingReasons[key] {
                    appendSkip(&skips, reason: blockingReason, observation: observation)
                    continue
                }
                guard let entry = lookupCache.entry(matching: candidate.normalizedTerm) else {
                    appendSkip(&skips, reason: .unmatchedVocabulary, observation: observation)
                    continue
                }

                let decisionKey = DirectDecisionKey(assetID: assetID, canonicalPath: entry.canonicalPath)
                if accumulators[decisionKey] == nil {
                    accumulators[decisionKey] = DirectDecisionAccumulator(entry: entry, observations: [])
                    order.append(decisionKey)
                } else {
                    appendSkip(
                        &skips,
                        reason: .duplicate,
                        observation: observation,
                        canonicalPath: entry.canonicalPath
                    )
                }
                accumulators[decisionKey]?.observations.append(observation)
            }
        }

        var decisions =
            order
            .sorted()
            .compactMap { key -> PerAssetNormalizationDecision? in
                guard let accumulator = accumulators[key] else {
                    return nil
                }
                return makeDirectDecision(
                    key: key,
                    groupID: observationExtraction.groupIDByAssetID[key.assetID],
                    accumulator: accumulator,
                    configuration: configuration
                )
            }
        decisions.append(
            contentsOf: userContextFallbackDecisions(
                records: contextRecords,
                input: input,
                configuration: configuration,
                groupIDByAssetID: observationExtraction.groupIDByAssetID
            ))
        assignDecisionIDs(&decisions)

        return CandidateCanonicalizationResult(
            sessionContext: contextRecords,
            observations: observationExtraction.observations,
            skips: skips,
            batchCandidates: batchCandidates(from: decisions),
            perAssetDecisions: decisions
        )
    }

    private func vocabularyResult(
        extractionResults: [CandidateExtractionResult],
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        observationExtraction: CandidateObservationExtraction,
        contextRecords: [NormalizationSessionContextRecord]
    ) -> CandidateCanonicalizationResult {
        let blockingPhase2Reasons = blockingReasonsByObservationKey(extractionResults)
        let fallbackBlockingReasons = fallbackBlockingReasonsByObservationKey(extractionResults)
        var skips: [NormalizationCandidateSkip] = []
        var accumulators: [DirectDecisionKey: DirectDecisionAccumulator] = [:]
        var order: [DirectDecisionKey] = []
        var speciesFallbackAccumulators: [SpeciesFallbackDecisionKey: SpeciesFallbackDecisionAccumulator] = [:]
        var speciesFallbackOrder: [SpeciesFallbackDecisionKey] = []

        for result in extractionResults {
            guard let assetID = observationExtraction.sourceAssetIDBySidecarPath[result.sourceSidecar] else {
                continue
            }

            for candidate in result.extractedCandidates {
                let key = CandidateObservationKey(candidate: candidate)
                guard let observation = observationExtraction.observationByKey[key] else {
                    continue
                }

                if candidate.normalizedTerm.isEmpty {
                    appendSkip(
                        &skips,
                        reason: .emptyAfterNormalization,
                        observation: observation
                    )
                    continue
                }
                if candidate.normalizedTerm.contains("|") {
                    appendSkip(
                        &skips,
                        reason: .containsHierarchySeparator,
                        observation: observation
                    )
                    continue
                }
                if candidate.confidence < configuration.minConfidence {
                    appendSkip(
                        &skips,
                        reason: .belowConfidenceThreshold,
                        observation: observation
                    )
                    continue
                }
                if let blockingReason = blockingPhase2Reasons[key] {
                    appendSkip(
                        &skips,
                        reason: blockingReason,
                        observation: observation
                    )
                    continue
                }
                guard let entry = lookupCache.entry(matching: candidate.normalizedTerm) else {
                    if candidate.provenance.sourceField == .species {
                        // FR3-011c: unmatched species common names may normalize
                        // across model text, but cannot become vocabulary-backed
                        // hierarchy or propagation support.
                        if let fallbackBlockingReason = fallbackBlockingReasons[key] {
                            appendSkip(
                                &skips,
                                reason: fallbackBlockingReason,
                                observation: observation
                            )
                            continue
                        }
                        let fallbackKey = SpeciesFallbackDecisionKey(
                            assetID: assetID,
                            speciesKey: speciesFallbackKey(for: candidate.normalizedTerm)
                        )
                        if speciesFallbackAccumulators[fallbackKey] == nil {
                            speciesFallbackAccumulators[fallbackKey] = SpeciesFallbackDecisionAccumulator(
                                observations: []
                            )
                            speciesFallbackOrder.append(fallbackKey)
                        } else {
                            appendSkip(
                                &skips,
                                reason: .duplicate,
                                observation: observation
                            )
                        }
                        speciesFallbackAccumulators[fallbackKey]?.observations.append(observation)
                        continue
                    }
                    appendSkip(
                        &skips,
                        reason: .unmatchedVocabulary,
                        observation: observation
                    )
                    continue
                }

                let decisionKey = DirectDecisionKey(assetID: assetID, canonicalPath: entry.canonicalPath)
                if accumulators[decisionKey] == nil {
                    accumulators[decisionKey] = DirectDecisionAccumulator(entry: entry, observations: [])
                    order.append(decisionKey)
                } else {
                    appendSkip(
                        &skips,
                        reason: .duplicate,
                        observation: observation,
                        canonicalPath: entry.canonicalPath
                    )
                }
                accumulators[decisionKey]?.observations.append(observation)
            }
        }

        let speciesDisplayTerms = speciesFallbackDisplayTerms(from: speciesFallbackAccumulators)
        var decisions =
            order
            .sorted()
            .compactMap { key -> PerAssetNormalizationDecision? in
                guard let accumulator = accumulators[key] else {
                    return nil
                }
                return makeDirectDecision(
                    key: key,
                    groupID: observationExtraction.groupIDByAssetID[key.assetID],
                    accumulator: accumulator,
                    configuration: configuration
                )
            }
        decisions.append(
            contentsOf:
                speciesFallbackOrder
                .sorted()
                .compactMap { key -> PerAssetNormalizationDecision? in
                    guard let accumulator = speciesFallbackAccumulators[key],
                        let displayTerm = speciesDisplayTerms[key.speciesKey]
                    else {
                        return nil
                    }
                    return makeSpeciesFallbackDecision(
                        key: key,
                        groupID: observationExtraction.groupIDByAssetID[key.assetID],
                        accumulator: accumulator,
                        displayTerm: displayTerm,
                        configuration: configuration
                    )
                })
        decisions.append(
            contentsOf: userContextFallbackDecisions(
                records: contextRecords,
                input: input,
                configuration: configuration,
                groupIDByAssetID: observationExtraction.groupIDByAssetID
            ))
        assignDecisionIDs(&decisions)

        return CandidateCanonicalizationResult(
            sessionContext: contextRecords,
            observations: observationExtraction.observations,
            skips: skips,
            batchCandidates: batchCandidates(from: decisions),
            perAssetDecisions: decisions
        )
    }

    private func makeSpeciesFallbackDecision(
        key: SpeciesFallbackDecisionKey,
        groupID: String?,
        accumulator: SpeciesFallbackDecisionAccumulator,
        displayTerm: String,
        configuration: ResolvedNormalizationConfiguration
    ) -> PerAssetNormalizationDecision {
        var skipReasons: [NormalizationCandidateSkipReason] = [.directApplyFlatOnly]
        let flatKeyword = configuration.writeFlatKeywords ? displayTerm : nil
        if flatKeyword == nil {
            skipReasons.append(.disabledFlatExport)
        }

        return PerAssetNormalizationDecision(
            assetID: key.assetID,
            groupID: groupID,
            stage: .directModelObservation,
            status: flatKeyword != nil ? .accepted : .withheld,
            candidateKind: .modelSpeciesFallback,
            flatKeyword: flatKeyword,
            sourceText: accumulator.observations.first?.normalizedTerm,
            directApplyPolicy: .flatOnly,
            exportFlatKeyword: flatKeyword != nil,
            exportHierarchicalKeyword: false,
            supportUnits: 1,
            supportingAssetIDs: [key.assetID],
            governingRule: "model_species_fallback_direct_flat_only",
            observationCount: accumulator.observations.count,
            skipReasons: stableUnique(skipReasons),
            observations: accumulator.observations.sorted(by: compareObservations)
        )
    }

    private func phase2FallbackResult(
        extractionResults: [CandidateExtractionResult],
        input: NormalizationResolvedInputBatch,
        observationExtraction: CandidateObservationExtraction,
        contextRecords: [NormalizationSessionContextRecord]
    ) -> CandidateCanonicalizationResult {
        var skips: [NormalizationCandidateSkip] = []
        var decisions: [PerAssetNormalizationDecision] = []

        for result in extractionResults {
            guard let assetID = observationExtraction.sourceAssetIDBySidecarPath[result.sourceSidecar] else {
                continue
            }
            for skipped in result.skippedCandidates {
                appendPhase2Skip(
                    &skips,
                    skipped: skipped,
                    result: result,
                    observationExtraction: observationExtraction
                )
            }

            let flatByKey = Dictionary(uniqueKeysWithValues: result.flatKeywords.map { ($0.normalizedKey, $0) })
            let hierarchicalByKey = Dictionary(
                uniqueKeysWithValues: result.hierarchicalKeywords.map { ($0.normalizedKey, $0) })
            let keys = Set(flatByKey.keys).union(hierarchicalByKey.keys).sorted()
            for key in keys {
                let flat = flatByKey[key]
                let hierarchical = hierarchicalByKey[key]
                let candidates = (flat?.candidates ?? hierarchical?.candidates ?? [])
                let observations = candidates.compactMap {
                    observationExtraction.observationByKey[CandidateObservationKey(candidate: $0)]
                }
                let flatKeyword = flat?.term
                let hierarchicalKeyword = hierarchical?.term
                decisions.append(
                    PerAssetNormalizationDecision(
                        assetID: assetID,
                        groupID: observationExtraction.groupIDByAssetID[assetID],
                        stage: .phase2Fallback,
                        status: flatKeyword != nil || hierarchicalKeyword != nil ? .accepted : .skipped,
                        candidateKind: .phase2Fallback,
                        flatKeyword: flatKeyword,
                        hierarchicalKeyword: hierarchicalKeyword,
                        sourceText: flatKeyword ?? hierarchicalKeyword,
                        exportFlatKeyword: flatKeyword != nil,
                        exportHierarchicalKeyword: hierarchicalKeyword != nil,
                        supportUnits: observations.isEmpty ? 0 : 1,
                        observationCount: observations.count,
                        observations: observations
                    )
                )
            }
        }

        decisions.sort { lhs, rhs in
            if lhs.assetID == rhs.assetID {
                return (lhs.flatKeyword ?? lhs.hierarchicalKeyword ?? "")
                    < (rhs.flatKeyword ?? rhs.hierarchicalKeyword ?? "")
            }
            return lhs.assetID < rhs.assetID
        }
        assignDecisionIDs(&decisions)

        return CandidateCanonicalizationResult(
            sessionContext: contextRecords,
            observations: observationExtraction.observations,
            skips: skips,
            batchCandidates: batchCandidates(from: decisions),
            perAssetDecisions: decisions
        )
    }

    private func makeDirectDecision(
        key: DirectDecisionKey,
        groupID: String?,
        accumulator: DirectDecisionAccumulator,
        configuration: ResolvedNormalizationConfiguration
    ) -> PerAssetNormalizationDecision {
        let entry = accumulator.entry
        var skipReasons: [NormalizationCandidateSkipReason] = []
        let flatAllowedByEntry = entry.exportFlatKeyword
        let hierarchicalAllowedByEntry = entry.exportHierarchicalKeyword
        let writesFlatByConfiguration = configuration.writeFlatKeywords
        let writesHierarchicalByConfiguration = configuration.writeHierarchicalKeywords
        var flatKeyword: String?
        var hierarchicalKeyword: String?

        switch entry.directApplyPolicy {
        case .allow:
            if writesFlatByConfiguration, flatAllowedByEntry {
                flatKeyword = entry.flatKeyword
            } else {
                skipReasons.append(.disabledFlatExport)
            }
            if writesHierarchicalByConfiguration, hierarchicalAllowedByEntry {
                hierarchicalKeyword = entry.canonicalPath
            } else {
                skipReasons.append(.disabledHierarchicalExport)
            }
        case .flatOnly:
            if writesFlatByConfiguration, flatAllowedByEntry {
                flatKeyword = entry.flatKeyword
            } else {
                skipReasons.append(.disabledFlatExport)
            }
            skipReasons.append(.directApplyFlatOnly)
        case .withhold, .userOnly:
            skipReasons.append(.directApplyWithheld)
            if entry.requiresReview {
                skipReasons.append(.requiresReview)
            }
        }

        let status: NormalizationDecisionStatus =
            flatKeyword != nil || hierarchicalKeyword != nil ? .accepted : .withheld
        let isObservedTag = configuration.vocabularyMode == .observedTags
        return PerAssetNormalizationDecision(
            assetID: key.assetID,
            groupID: groupID,
            stage: .directModelObservation,
            status: status,
            candidateKind: isObservedTag ? .observedModelTag : .canonicalVocabulary,
            canonicalPath: entry.canonicalPath,
            flatKeyword: flatKeyword,
            hierarchicalKeyword: hierarchicalKeyword,
            sourceText: accumulator.observations.first?.normalizedTerm,
            namespace: isObservedTag ? nil : entry.namespace,
            directApplyPolicy: entry.directApplyPolicy,
            requiresReview: entry.requiresReview,
            exportFlatKeyword: flatKeyword != nil,
            exportHierarchicalKeyword: hierarchicalKeyword != nil,
            supportUnits: 1,
            observationCount: accumulator.observations.count,
            skipReasons: stableUnique(skipReasons),
            observations: accumulator.observations.sorted(by: compareObservations)
        )
    }

    private func makeSessionContextRecords(
        configuration: ResolvedNormalizationConfiguration,
        input: NormalizationResolvedInputBatch,
        groupIDByAssetID _: [String: String]
    ) -> [NormalizationSessionContextRecord] {
        let hasTargetAssets = !targetAssetIDs(in: input).isEmpty
        return Self.sessionContextInputs(configuration).compactMap { context -> NormalizationSessionContextRecord? in
            let normalized = KeywordTextNormalizer.normalize(context.value)
            guard !normalized.isEmpty else {
                return nil
            }
            if configuration.normalizationMode == .off {
                return NormalizationSessionContextRecord(
                    contextType: context.type,
                    originalText: context.value,
                    foldedText: lookupCache.fold(normalized),
                    matchedCanonicalPath: nil,
                    unknownPolicyResult: "ignored_normalization_off",
                    directApplyPolicy: nil,
                    propagationAllowed: context.propagationAllowed,
                    conflictCount: 0,
                    exportResult: "ignored_normalization_off"
                )
            }

            let writesUnnormalized = configuration.unknownSessionContextPolicy == .writeUnnormalized
            let unmatchedExportResult: String
            if !context.propagationAllowed {
                unmatchedExportResult = "propagation_not_allowed"
            } else if !hasTargetAssets {
                unmatchedExportResult = "no_target_assets"
            } else if writesUnnormalized, configuration.writeFlatKeywords {
                unmatchedExportResult = "flat_only_unnormalized"
            } else if writesUnnormalized {
                unmatchedExportResult = "withheld_by_policy"
            } else {
                unmatchedExportResult = "unknown_context_rejected"
            }
            if configuration.vocabularyMode == .observedTags {
                return NormalizationSessionContextRecord(
                    contextType: context.type,
                    originalText: context.value,
                    foldedText: lookupCache.fold(normalized),
                    matchedCanonicalPath: nil,
                    unknownPolicyResult: writesUnnormalized ? "write_unnormalized" : "rejected",
                    directApplyPolicy: writesUnnormalized ? .flatOnly : nil,
                    propagationAllowed: context.propagationAllowed,
                    conflictCount: 0,
                    exportResult: unmatchedExportResult
                )
            }
            if let entry = lookupCache.entry(matching: normalized) {
                return NormalizationSessionContextRecord(
                    contextType: context.type,
                    originalText: context.value,
                    foldedText: lookupCache.fold(normalized),
                    matchedCanonicalPath: entry.canonicalPath,
                    unknownPolicyResult: "matched",
                    directApplyPolicy: entry.directApplyPolicy,
                    propagationAllowed: context.propagationAllowed,
                    conflictCount: 0,
                    exportResult: context.propagationAllowed
                        ? "pending_session_context_decision" : "propagation_not_allowed"
                )
            }

            return NormalizationSessionContextRecord(
                contextType: context.type,
                originalText: context.value,
                foldedText: lookupCache.fold(normalized),
                matchedCanonicalPath: nil,
                unknownPolicyResult: writesUnnormalized ? "write_unnormalized" : "rejected",
                directApplyPolicy: writesUnnormalized ? .flatOnly : nil,
                propagationAllowed: context.propagationAllowed,
                conflictCount: 0,
                exportResult: unmatchedExportResult
            )
        }
    }

    private func userContextFallbackDecisions(
        records: [NormalizationSessionContextRecord],
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        groupIDByAssetID: [String: String]
    ) -> [PerAssetNormalizationDecision] {
        let targetAssetIDs = targetAssetIDs(in: input)

        var decisions: [PerAssetNormalizationDecision] = []
        for record in records
        where record.unknownPolicyResult == "write_unnormalized" && record.propagationAllowed {
            let keyword = KeywordTextNormalizer.normalize(record.originalText)
            guard !keyword.isEmpty else {
                continue
            }
            for assetID in targetAssetIDs.sorted() {
                let flatKeyword = configuration.writeFlatKeywords ? keyword : nil
                var skipReasons: [NormalizationCandidateSkipReason] = [.unknownSessionContextFlatOnly]
                if flatKeyword == nil {
                    skipReasons.append(.disabledFlatExport)
                }
                decisions.append(
                    PerAssetNormalizationDecision(
                        assetID: assetID,
                        groupID: groupIDByAssetID[assetID],
                        stage: .userSessionContext,
                        status: flatKeyword == nil ? .withheld : .accepted,
                        candidateKind: .userContextUnnormalized,
                        flatKeyword: flatKeyword,
                        sourceText: record.originalText,
                        contextType: record.contextType,
                        directApplyPolicy: .flatOnly,
                        exportFlatKeyword: flatKeyword != nil,
                        exportHierarchicalKeyword: false,
                        supportUnits: 1,
                        supportingAssetIDs: [assetID],
                        governingRule: "user_session_context_\(record.contextType.rawValue)_unnormalized",
                        observationCount: 0,
                        skipReasons: skipReasons
                    )
                )
            }
        }
        return decisions
    }

    private func targetAssetIDs(in input: NormalizationResolvedInputBatch) -> [String] {
        if input.sameBaseNameGroups.isEmpty {
            return input.sourceAssets.map(\.assetID).sorted()
        }
        return Array(Set(input.sameBaseNameGroups.flatMap(\.selectedAssetIDs))).sorted()
    }

    private func blockingReasonsByObservationKey(
        _ extractionResults: [CandidateExtractionResult]
    ) -> [CandidateObservationKey: NormalizationCandidateSkipReason] {
        var reasons: [CandidateObservationKey: NormalizationCandidateSkipReason] = [:]
        for result in extractionResults {
            for skipped in result.skippedCandidates {
                guard let candidate = skipped.candidate else {
                    continue
                }
                switch skipped.reason {
                case .coordinateLikeTerm:
                    reasons[CandidateObservationKey(candidate: candidate)] = .coordinateLikeTerm
                case .gpsOnlyEvidence:
                    reasons[CandidateObservationKey(candidate: candidate)] = .gpsOnlyEvidence
                case .speciesWithoutBiologicalGenre:
                    reasons[CandidateObservationKey(candidate: candidate)] = .speciesWithoutBiologicalGenre
                default:
                    continue
                }
            }
        }
        return reasons
    }

    private func fallbackBlockingReasonsByObservationKey(
        _ extractionResults: [CandidateExtractionResult]
    ) -> [CandidateObservationKey: NormalizationCandidateSkipReason] {
        var reasons = blockingReasonsByObservationKey(extractionResults)
        for result in extractionResults {
            for skipped in result.skippedCandidates {
                guard let candidate = skipped.candidate,
                    skipped.reason == .specificTagPolicy
                else {
                    continue
                }
                reasons[CandidateObservationKey(candidate: candidate)] = .specificTagPolicy
            }
        }
        return reasons
    }

    private func appendPhase2Skip(
        _ skips: inout [NormalizationCandidateSkip],
        skipped: SkippedCandidate,
        result: CandidateExtractionResult,
        observationExtraction: CandidateObservationExtraction
    ) {
        let observation = skipped.candidate.flatMap {
            observationExtraction.observationByKey[CandidateObservationKey(candidate: $0)]
        }
        let assetID = observation?.assetID ?? observationExtraction.sourceAssetIDBySidecarPath[result.sourceSidecar]
        appendSkip(
            &skips,
            reason: Self.convert(reason: skipped.reason),
            observation: observation,
            assetID: assetID,
            groupID: assetID.flatMap { observationExtraction.groupIDByAssetID[$0] },
            term: skipped.term,
            normalizedTerm: skipped.normalizedTerm
        )
    }

    private func appendSkip(
        _ skips: inout [NormalizationCandidateSkip],
        reason: NormalizationCandidateSkipReason,
        observation: CandidateObservation?,
        assetID: String?,
        groupID: String?,
        term: String?,
        normalizedTerm: String?,
        canonicalPath: String? = nil
    ) {
        skips.append(
            NormalizationCandidateSkip(
                skipID: String(format: "skip-%06d", skips.count + 1),
                reason: reason,
                assetID: observation?.assetID ?? assetID,
                groupID: observation?.groupID ?? groupID,
                observationID: observation?.observationID,
                term: observation?.term ?? term,
                normalizedTerm: observation?.normalizedTerm ?? normalizedTerm,
                foldedTerm: observation?.foldedTerm ?? normalizedTerm.map { lookupCache.fold($0) },
                canonicalPath: canonicalPath,
                sourceSidecar: observation?.provenance.sourceSidecar,
                sourceImage: observation?.provenance.sourceImage,
                sourceField: observation?.provenance.sourceField,
                inputRole: observation?.provenance.inputRole,
                modelRunIndex: observation?.provenance.modelRunIndex
            )
        )
    }

    private func appendSkip(
        _ skips: inout [NormalizationCandidateSkip],
        reason: NormalizationCandidateSkipReason,
        observation: CandidateObservation,
        canonicalPath: String? = nil
    ) {
        appendSkip(
            &skips,
            reason: reason,
            observation: observation,
            assetID: nil,
            groupID: nil,
            term: nil,
            normalizedTerm: nil,
            canonicalPath: canonicalPath
        )
    }

    private func batchCandidates(from decisions: [PerAssetNormalizationDecision]) -> [BatchCandidateSummary] {
        let grouped = Dictionary(grouping: decisions) { decision in
            BatchCandidateKey(
                candidateKind: decision.candidateKind,
                canonicalPath: decision.canonicalPath,
                flatKeyword: decision.flatKeyword,
                hierarchicalKeyword: decision.hierarchicalKeyword,
                namespace: decision.namespace
            )
        }

        return grouped.keys.sorted().compactMap { key in
            guard let decisions = grouped[key] else {
                return nil
            }
            let observations = decisions.flatMap(\.observations)
            return BatchCandidateSummary(
                candidateKind: key.candidateKind,
                canonicalPath: key.canonicalPath,
                flatKeyword: key.flatKeyword,
                hierarchicalKeyword: key.hierarchicalKeyword,
                namespace: key.namespace,
                supportingAssetIDs: decisions.map(\.assetID).sorted(),
                directAssetSupportCount: decisions.count,
                observationCount: observations.count,
                confidenceBands: counts(observations.map { $0.confidence.rawValue }),
                sourceFields: counts(observations.map { $0.provenance.sourceField.rawValue }),
                inputRoles: counts(observations.map { $0.provenance.inputRole.rawValue })
            )
        }
    }

    private func assignDecisionIDs(_ decisions: inout [PerAssetNormalizationDecision]) {
        for index in decisions.indices {
            decisions[index].decisionID = String(format: "decision-%06d", index + 1)
        }
    }

    private func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { partial, value in
            partial[value, default: 0] += 1
        }
    }

    private func stableUnique(_ values: [NormalizationCandidateSkipReason]) -> [NormalizationCandidateSkipReason] {
        var seen: Set<NormalizationCandidateSkipReason> = []
        var result: [NormalizationCandidateSkipReason] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private func speciesFallbackKey(for normalizedTerm: String) -> String {
        let separatorFolded = VocabularyTextFolder.separatorInsensitiveFold(normalizedTerm)
        let variants =
            [separatorFolded]
            + VocabularyTextFolder
            .finalTokenVariantSeparatorInsensitiveFolds(separatorFolded)
        return
            variants
            .filter { !$0.isEmpty }
            .sorted()
            .first ?? separatorFolded
    }

    private func speciesFallbackDisplayTerms(
        from accumulators: [SpeciesFallbackDecisionKey: SpeciesFallbackDecisionAccumulator]
    ) -> [String: String] {
        let observationsBySpeciesKey = Dictionary(grouping: accumulators) { entry in
            entry.key.speciesKey
        }
        return observationsBySpeciesKey.mapValues { entries in
            preferredSpeciesFallbackDisplayTerm(
                observations: entries.flatMap { $0.value.observations }
            )
        }
    }

    private func preferredSpeciesFallbackDisplayTerm(observations: [CandidateObservation]) -> String {
        let terms = observations.map(\.normalizedTerm).filter { !$0.isEmpty }
        let counts = counts(terms)
        return terms.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            let lhsTitleScore = titleCaseWordCount(lhs)
            let rhsTitleScore = titleCaseWordCount(rhs)
            if lhsTitleScore != rhsTitleScore {
                return lhsTitleScore > rhsTitleScore
            }
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            let lhsLowercased = lhs.lowercased()
            let rhsLowercased = rhs.lowercased()
            if lhsLowercased != rhsLowercased {
                return lhsLowercased < rhsLowercased
            }
            return lhs < rhs
        }.first ?? ""
    }

    private func titleCaseWordCount(_ value: String) -> Int {
        value.split(whereSeparator: \.isWhitespace).filter { word in
            guard let first = word.first, first.isUppercase else {
                return false
            }
            return word.dropFirst().contains { $0.isLowercase }
        }.count
    }

    private static func convert(reason: SkippedCandidateReason) -> NormalizationCandidateSkipReason {
        switch reason {
        case .belowConfidenceThreshold:
            return .belowConfidenceThreshold
        case .unmatchedVocabulary:
            return .unmatchedVocabulary
        case .directApplyWithheld:
            return .directApplyWithheld
        case .directApplyFlatOnly:
            return .directApplyFlatOnly
        case .requiresReview:
            return .requiresReview
        case .specificTagPolicy:
            return .specificTagPolicy
        case .containsHierarchySeparator:
            return .containsHierarchySeparator
        case .emptyAfterNormalization:
            return .emptyAfterNormalization
        case .duplicate:
            return .duplicate
        case .disabledFlatExport:
            return .disabledFlatExport
        case .disabledHierarchicalExport:
            return .disabledHierarchicalExport
        case .coordinateLikeTerm:
            return .coordinateLikeTerm
        case .gpsOnlyEvidence:
            return .gpsOnlyEvidence
        case .speciesWithoutBiologicalGenre:
            return .speciesWithoutBiologicalGenre
        case .unknownSessionContextRejected:
            return .unknownSessionContextRejected
        case .unknownSessionContextFlatOnly:
            return .unknownSessionContextFlatOnly
        case .weakLocalAgreement:
            return .weakLocalAgreement
        case .lowSupportMass:
            return .lowSupportMass
        case .lowSupportingNeighborCount:
            return .lowSupportingNeighborCount
        case .lowMaxSupportingAffinity:
            return .lowMaxSupportingAffinity
        case .blockedDirectConflict:
            return .blockedDirectConflict
        case .blockedLocalConflictMass:
            return .blockedLocalConflictMass
        case .gearOnlyAffinity:
            return .gearOnlyAffinity
        case .globalBackstopThreshold:
            return .globalBackstopThreshold
        case .sessionContextConflict:
            return .sessionContextConflict
        case .userReviewRejected:
            return .userReviewRejected
        case .userReviewDeferred:
            return .userReviewDeferred
        }
    }

    private static func sessionContextInputs(
        _ configuration: ResolvedNormalizationConfiguration
    ) -> [SessionContextInput] {
        var inputs: [SessionContextInput] = []
        appendContext(
            type: .subject,
            value: configuration.sessionSubject,
            propagationAllowed: configuration.allowSessionSubjectPropagation,
            to: &inputs
        )
        appendContext(
            type: .habitat,
            value: configuration.sessionHabitat,
            propagationAllowed: configuration.allowSessionHabitatPropagation,
            to: &inputs
        )
        appendContext(
            type: .event,
            value: configuration.sessionEvent,
            propagationAllowed: configuration.allowSessionEventPropagation,
            to: &inputs
        )
        return inputs
    }

    private static func appendContext(
        type: NormalizationSessionContextType,
        value: String?,
        propagationAllowed: Bool,
        to inputs: inout [SessionContextInput]
    ) {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return
        }
        inputs.append(
            SessionContextInput(
                type: type,
                value: trimmed,
                propagationAllowed: propagationAllowed
            )
        )
    }
}

final class CandidateCanonicalizerLookupCache {
    private var foldsByText: [String: String] = [:]
    private var entriesByText: [String: ResolvedVocabularyEntry?] = [:]
    private let foldText: (String) -> String
    private let lookupEntry: (String) -> ResolvedVocabularyEntry?

    init(vocabulary: LoadedVocabulary) {
        self.foldText = VocabularyTextFolder.fold
        self.lookupEntry = vocabulary.index.entry(matching:)
    }

    init(
        foldText: @escaping (String) -> String,
        lookupEntry: @escaping (String) -> ResolvedVocabularyEntry?
    ) {
        self.foldText = foldText
        self.lookupEntry = lookupEntry
    }

    func fold(_ text: String) -> String {
        if let cached = foldsByText[text] {
            return cached
        }
        let folded = foldText(text)
        foldsByText[text] = folded
        return folded
    }

    func entry(matching text: String) -> ResolvedVocabularyEntry? {
        if let cached = entriesByText[text] {
            return cached
        }
        let entry = lookupEntry(text)
        entriesByText[text] = .some(entry)
        return entry
    }
}

private struct DirectDecisionKey: Hashable, Sendable, Comparable {
    var assetID: String
    var canonicalPath: String

    static func < (lhs: DirectDecisionKey, rhs: DirectDecisionKey) -> Bool {
        if lhs.assetID == rhs.assetID {
            return lhs.canonicalPath < rhs.canonicalPath
        }
        return lhs.assetID < rhs.assetID
    }
}

private struct DirectDecisionAccumulator: Sendable, Equatable {
    var entry: ResolvedVocabularyEntry
    var observations: [CandidateObservation]
}

private struct SpeciesFallbackDecisionKey: Hashable, Sendable, Comparable {
    var assetID: String
    var speciesKey: String

    static func < (lhs: SpeciesFallbackDecisionKey, rhs: SpeciesFallbackDecisionKey) -> Bool {
        if lhs.assetID == rhs.assetID {
            return lhs.speciesKey < rhs.speciesKey
        }
        return lhs.assetID < rhs.assetID
    }
}

private struct SpeciesFallbackDecisionAccumulator: Sendable, Equatable {
    var observations: [CandidateObservation]
}

private struct BatchCandidateKey: Hashable, Sendable, Comparable {
    var candidateKind: NormalizedCandidateKind
    var canonicalPath: String?
    var flatKeyword: String?
    var hierarchicalKeyword: String?
    var namespace: VocabularyNamespace?

    static func < (lhs: BatchCandidateKey, rhs: BatchCandidateKey) -> Bool {
        let lhsTuple = [
            lhs.candidateKind.rawValue,
            lhs.canonicalPath ?? "",
            lhs.flatKeyword ?? "",
            lhs.hierarchicalKeyword ?? "",
            lhs.namespace?.rawValue ?? "",
        ]
        let rhsTuple = [
            rhs.candidateKind.rawValue,
            rhs.canonicalPath ?? "",
            rhs.flatKeyword ?? "",
            rhs.hierarchicalKeyword ?? "",
            rhs.namespace?.rawValue ?? "",
        ]
        return lhsTuple.lexicographicallyPrecedes(rhsTuple)
    }
}

private struct SessionContextInput: Sendable {
    var type: NormalizationSessionContextType
    var value: String
    var propagationAllowed: Bool
}

private func compareObservations(_ lhs: CandidateObservation, _ rhs: CandidateObservation) -> Bool {
    if lhs.assetID != rhs.assetID {
        return lhs.assetID < rhs.assetID
    }
    return lhs.observationID < rhs.observationID
}
