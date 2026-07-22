import Foundation

/// Normalization state after batch affinity and consensus have been applied.
public struct BatchConsensusResult: Sendable, Equatable {
    public var sessionContext: [NormalizationSessionContextRecord]
    public var observations: [CandidateObservation]
    public var skips: [NormalizationCandidateSkip]
    public var affinity: NormalizationAffinityRecord
    public var batchCandidates: [BatchCandidateSummary]
    public var localConsensus: [LocalWeightedConsensusRecord]
    public var perAssetDecisions: [PerAssetNormalizationDecision]

    public init(
        sessionContext: [NormalizationSessionContextRecord],
        observations: [CandidateObservation],
        skips: [NormalizationCandidateSkip],
        affinity: NormalizationAffinityRecord,
        batchCandidates: [BatchCandidateSummary],
        localConsensus: [LocalWeightedConsensusRecord],
        perAssetDecisions: [PerAssetNormalizationDecision]
    ) {
        self.sessionContext = sessionContext
        self.observations = observations
        self.skips = skips
        self.affinity = affinity
        self.batchCandidates = batchCandidates
        self.localConsensus = localConsensus
        self.perAssetDecisions = perAssetDecisions
    }
}

/// Computes hierarchy-aware batch counts, local consensus, and conservative propagation.
public struct BatchConsensusEngine {
    private let vocabulary: LoadedVocabulary
    private let graphBuilder: AssetAffinityGraphBuilder

    public init(
        vocabulary: LoadedVocabulary,
        graphBuilder: AssetAffinityGraphBuilder = AssetAffinityGraphBuilder()
    ) {
        self.vocabulary = vocabulary
        self.graphBuilder = graphBuilder
    }

    public func apply(
        canonicalization: CandidateCanonicalizationResult,
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration
    ) -> BatchConsensusResult {
        let profile = AssetAffinityProfile.resolved(
            name: configuration.affinityProfile,
            minAffinityForConsensus: configuration.minAffinityForConsensus
        )
        let graph = graphBuilder.build(
            input: input,
            profile: profile,
            mode: shouldBuildGraph(configuration) ? configuration.affinityMode : .off
        )
        var decisions = canonicalization.perAssetDecisions
        let eligibleAssetIDs = input.sourceAssets.map(\.assetID).sorted()

        guard configuration.normalizationMode != .off else {
            assignDecisionIDs(&decisions)
            return result(
                canonicalization: canonicalization,
                graph: graph,
                configuration: configuration,
                batchCandidates: canonicalization.batchCandidates,
                localConsensus: [],
                decisions: decisions
            )
        }

        var support = DirectSupportIndex(
            decisions: decisions,
            vocabulary: vocabulary,
            eligibleAssetIDs: eligibleAssetIDs
        )
        let sessionContextDecisionStartIndex = decisions.count
        let sessionContext = applySessionContext(
            records: canonicalization.sessionContext,
            support: support,
            input: input,
            graph: graph,
            configuration: configuration,
            decisions: &decisions
        )
        support.add(decisions: Array(decisions.dropFirst(sessionContextDecisionStartIndex)))
        if configuration.normalizationMode == .singleImage {
            decisions.sort(by: compareDecisions)
            assignDecisionIDs(&decisions)
            return result(
                canonicalization: canonicalizationWithSessionContext(
                    sessionContext,
                    canonicalization: canonicalization
                ),
                graph: graph,
                configuration: configuration,
                batchCandidates: canonicalization.batchCandidates,
                localConsensus: [],
                decisions: decisions
            )
        }
        var localConsensus: [LocalWeightedConsensusRecord] = []
        if configuration.affinityMode == .metadataWeighted {
            let localDecisions = localPropagationDecisions(
                support: support,
                input: input,
                graph: graph,
                profile: profile,
                configuration: configuration,
                localConsensus: &localConsensus
            )
            decisions.append(contentsOf: localDecisions)
            support.add(decisions: localDecisions)
        }
        let globalDecisions = globalBackstopDecisions(
            support: support,
            input: input,
            graph: graph,
            profile: profile,
            configuration: configuration
        )
        decisions.append(contentsOf: globalDecisions)
        support.add(decisions: globalDecisions)
        decisions.sort(by: compareDecisions)
        assignDecisionIDs(&decisions)
        localConsensus.sort(by: compareLocalConsensus)

        return result(
            canonicalization: canonicalizationWithSessionContext(
                sessionContext,
                canonicalization: canonicalization
            ),
            graph: graph,
            configuration: configuration,
            batchCandidates: hierarchyAwareBatchCandidates(
                support: support,
                decisions: decisions,
                eligibleAssetIDs: eligibleAssetIDs,
                configuration: configuration
            ),
            localConsensus: localConsensus,
            decisions: decisions
        )
    }

    private func result(
        canonicalization: CandidateCanonicalizationResult,
        graph: AssetAffinityGraph,
        configuration: ResolvedNormalizationConfiguration,
        batchCandidates: [BatchCandidateSummary],
        localConsensus: [LocalWeightedConsensusRecord],
        decisions: [PerAssetNormalizationDecision]
    ) -> BatchConsensusResult {
        BatchConsensusResult(
            sessionContext: canonicalization.sessionContext,
            observations: canonicalization.observations,
            skips: canonicalization.skips,
            affinity: NormalizationAffinityRecord(
                mode: shouldBuildGraph(configuration) ? configuration.affinityMode : .off,
                profile: configuration.affinityProfile,
                minAffinityForConsensus: configuration.minAffinityForConsensus,
                nodes: graph.nodes,
                edges: graph.edges,
                clusters: graph.clusters
            ),
            batchCandidates: batchCandidates,
            localConsensus: localConsensus,
            perAssetDecisions: decisions
        )
    }

    private func canonicalizationWithSessionContext(
        _ sessionContext: [NormalizationSessionContextRecord],
        canonicalization: CandidateCanonicalizationResult
    ) -> CandidateCanonicalizationResult {
        CandidateCanonicalizationResult(
            sessionContext: sessionContext,
            observations: canonicalization.observations,
            skips: canonicalization.skips,
            batchCandidates: canonicalization.batchCandidates,
            perAssetDecisions: canonicalization.perAssetDecisions
        )
    }

    private func shouldBuildGraph(_ configuration: ResolvedNormalizationConfiguration) -> Bool {
        configuration.normalizationMode == .batchConservative
            && configuration.affinityMode == .metadataWeighted
    }

    private func hierarchyAwareBatchCandidates(
        support: DirectSupportIndex,
        decisions: [PerAssetNormalizationDecision],
        eligibleAssetIDs: [String],
        configuration: ResolvedNormalizationConfiguration
    ) -> [BatchCandidateSummary] {
        var summaries: [BatchCandidateSummary] = []
        let eligibleCount = eligibleAssetIDs.count
        let isObservedTags = configuration.vocabularyMode == .observedTags
        for canonicalPath in support.supportedCanonicalPaths.sorted() {
            guard let entry = vocabulary.index.entry(canonicalPath: canonicalPath) else {
                continue
            }
            let supporting = support.assetsSupporting(canonicalPath).sorted()
            let observations =
                decisions
                .filter { $0.canonicalPath == canonicalPath && $0.stage == .directModelObservation }
                .flatMap(\.observations)
            summaries.append(
                BatchCandidateSummary(
                    candidateKind: isObservedTags ? .observedModelTag : .canonicalVocabulary,
                    canonicalPath: canonicalPath,
                    flatKeyword: entry.flatKeyword,
                    hierarchicalKeyword: isObservedTags ? nil : entry.canonicalPath,
                    namespace: isObservedTags ? nil : entry.namespace,
                    supportingAssetIDs: supporting,
                    directAssetSupportCount: supporting.count,
                    eligibleAssetCount: eligibleCount,
                    agreementFrequency: eligibleCount > 0
                        ? AffinityScoreFormatter.rounded(Double(supporting.count) / Double(eligibleCount))
                        : nil,
                    observationCount: observations.count,
                    confidenceBands: frequencyCounts(observations.map { $0.confidence.rawValue }),
                    sourceFields: frequencyCounts(observations.map { $0.provenance.sourceField.rawValue }),
                    inputRoles: frequencyCounts(observations.map { $0.provenance.inputRole.rawValue })
                )
            )
        }

        let nonCanonical =
            decisions
            .filter { $0.candidateKind != .canonicalVocabulary && $0.candidateKind != .observedModelTag }
        summaries.append(
            contentsOf: Dictionary(grouping: nonCanonical) {
                "\($0.candidateKind.rawValue)|\($0.flatKeyword ?? "")|\($0.hierarchicalKeyword ?? "")"
            }.values.map { grouped in
                let first = grouped[0]
                let observations = grouped.flatMap(\.observations)
                return BatchCandidateSummary(
                    candidateKind: first.candidateKind,
                    flatKeyword: first.flatKeyword,
                    hierarchicalKeyword: first.hierarchicalKeyword,
                    supportingAssetIDs: grouped.map(\.assetID).sorted(),
                    directAssetSupportCount: grouped.count,
                    eligibleAssetCount: eligibleCount,
                    agreementFrequency: eligibleCount > 0
                        ? AffinityScoreFormatter.rounded(Double(grouped.count) / Double(eligibleCount))
                        : nil,
                    observationCount: observations.count,
                    confidenceBands: frequencyCounts(observations.map { $0.confidence.rawValue }),
                    sourceFields: frequencyCounts(observations.map { $0.provenance.sourceField.rawValue }),
                    inputRoles: frequencyCounts(observations.map { $0.provenance.inputRole.rawValue })
                )
            })

        return summaries.sorted { lhs, rhs in
            let lhsKey = lhs.canonicalPath ?? lhs.flatKeyword ?? lhs.hierarchicalKeyword ?? ""
            let rhsKey = rhs.canonicalPath ?? rhs.flatKeyword ?? rhs.hierarchicalKeyword ?? ""
            if lhs.candidateKind == rhs.candidateKind {
                return lhsKey < rhsKey
            }
            return lhs.candidateKind.rawValue < rhs.candidateKind.rawValue
        }
    }

    private func applySessionContext(
        records: [NormalizationSessionContextRecord],
        support: DirectSupportIndex,
        input: NormalizationResolvedInputBatch,
        graph: AssetAffinityGraph,
        configuration: ResolvedNormalizationConfiguration,
        decisions: inout [PerAssetNormalizationDecision]
    ) -> [NormalizationSessionContextRecord] {
        var updated: [NormalizationSessionContextRecord] = []
        var acceptedDecisionKeys = Set(
            decisions.compactMap { decision -> AssetCanonicalPathKey? in
                guard decision.status == .accepted, let canonicalPath = decision.canonicalPath else {
                    return nil
                }
                return AssetCanonicalPathKey(assetID: decision.assetID, canonicalPath: canonicalPath)
            })
        let targetAssetIDs = targetAssetIDs(in: input)

        for record in records {
            var record = record
            guard record.propagationAllowed else {
                updated.append(record)
                continue
            }

            guard let canonicalPath = record.matchedCanonicalPath,
                let entry = vocabulary.index.entry(canonicalPath: canonicalPath)
            else {
                if record.exportResult == "pending_session_context_decision" {
                    record.exportResult = targetAssetIDs.isEmpty ? "no_target_assets" : "withheld_by_policy"
                }
                updated.append(record)
                continue
            }
            guard !targetAssetIDs.isEmpty else {
                record.conflictCount = 0
                record.exportResult = "no_target_assets"
                updated.append(record)
                continue
            }

            var conflictCount = 0
            var acceptedCoverageCount = 0
            var withheldCount = 0
            for assetID in targetAssetIDs {
                if hasDirectConflict(assetID: assetID, candidatePath: canonicalPath, support: support) {
                    conflictCount += 1
                    continue
                }
                // FR3-003k: withheld model evidence remains auditable but cannot block explicit user context.
                let decisionKey = AssetCanonicalPathKey(assetID: assetID, canonicalPath: canonicalPath)
                if acceptedDecisionKeys.contains(decisionKey) {
                    acceptedCoverageCount += 1
                    continue
                }
                let decision = userContextDecision(
                    assetID: assetID,
                    groupID: graph.nodeIDByAssetID[assetID],
                    record: record,
                    entry: entry,
                    configuration: configuration
                )
                decisions.append(decision)
                if decision.status == .accepted {
                    acceptedCoverageCount += 1
                    acceptedDecisionKeys.insert(decisionKey)
                } else {
                    withheldCount += 1
                }
            }
            record.conflictCount = conflictCount
            record.exportResult = sessionContextExportResult(
                targetCount: targetAssetIDs.count,
                acceptedCoverageCount: acceptedCoverageCount,
                withheldCount: withheldCount,
                conflictCount: conflictCount
            )
            updated.append(record)
        }
        return updated
    }

    private func targetAssetIDs(in input: NormalizationResolvedInputBatch) -> [String] {
        if input.sameBaseNameGroups.isEmpty {
            return input.sourceAssets.map(\.assetID).sorted()
        }
        return Array(Set(input.sameBaseNameGroups.flatMap(\.selectedAssetIDs))).sorted()
    }

    private func sessionContextExportResult(
        targetCount: Int,
        acceptedCoverageCount: Int,
        withheldCount: Int,
        conflictCount: Int
    ) -> String {
        guard targetCount > 0 else {
            return "no_target_assets"
        }
        if acceptedCoverageCount > 0 {
            return conflictCount > 0 ? "applied_with_conflicts" : "applied"
        }
        if conflictCount > 0 {
            return "not_applied_conflicts"
        }
        if withheldCount > 0 {
            return "withheld_by_policy"
        }
        return "withheld_by_policy"
    }

    private func userContextDecision(
        assetID: String,
        groupID: String?,
        record: NormalizationSessionContextRecord,
        entry: ResolvedVocabularyEntry,
        configuration: ResolvedNormalizationConfiguration
    ) -> PerAssetNormalizationDecision {
        var flatKeyword: String?
        var hierarchicalKeyword: String?
        var skipReasons: [NormalizationCandidateSkipReason] = []
        switch entry.directApplyPolicy {
        case .allow, .userOnly:
            if configuration.writeFlatKeywords, entry.exportFlatKeyword {
                flatKeyword = entry.flatKeyword
            } else {
                skipReasons.append(.disabledFlatExport)
            }
            if configuration.writeHierarchicalKeywords, entry.exportHierarchicalKeyword {
                hierarchicalKeyword = entry.canonicalPath
            } else {
                skipReasons.append(.disabledHierarchicalExport)
            }
        case .flatOnly:
            if configuration.writeFlatKeywords, entry.exportFlatKeyword {
                flatKeyword = entry.flatKeyword
            } else {
                skipReasons.append(.disabledFlatExport)
            }
            skipReasons.append(.directApplyFlatOnly)
        case .withhold:
            skipReasons.append(.directApplyWithheld)
        }
        if entry.requiresReview {
            skipReasons.append(.requiresReview)
        }
        return PerAssetNormalizationDecision(
            assetID: assetID,
            groupID: groupID,
            stage: .userSessionContext,
            status: flatKeyword != nil || hierarchicalKeyword != nil ? .accepted : .withheld,
            candidateKind: .canonicalVocabulary,
            canonicalPath: entry.canonicalPath,
            flatKeyword: flatKeyword,
            hierarchicalKeyword: hierarchicalKeyword,
            sourceText: record.originalText,
            contextType: record.contextType,
            namespace: entry.namespace,
            directApplyPolicy: entry.directApplyPolicy,
            requiresReview: entry.requiresReview,
            exportFlatKeyword: flatKeyword != nil,
            exportHierarchicalKeyword: hierarchicalKeyword != nil,
            supportUnits: 1,
            supportingAssetIDs: [assetID],
            governingRule: "user_session_context_\(record.contextType.rawValue)",
            observationCount: 0,
            skipReasons: stableUnique(skipReasons)
        )
    }

    private func localPropagationDecisions(
        support: DirectSupportIndex,
        input: NormalizationResolvedInputBatch,
        graph: AssetAffinityGraph,
        profile: AssetAffinityProfile,
        configuration: ResolvedNormalizationConfiguration,
        localConsensus: inout [LocalWeightedConsensusRecord]
    ) -> [PerAssetNormalizationDecision] {
        var propagated: [PerAssetNormalizationDecision] = []
        let targetAssetIDs = input.sourceAssets.map(\.assetID).sorted()
        let candidatePaths = support.supportedCanonicalPaths
            .filter { path in
                guard let entry = vocabulary.index.entry(canonicalPath: path) else {
                    return false
                }
                return entry.autoApplyAllowed
                    && !entry.requiresReview
                    && entry.propagationScope == .local
                    && entry.specificity != .specific
            }
            .sorted()

        for assetID in targetAssetIDs {
            guard let targetNodeID = graph.nodeIDByAssetID[assetID] else {
                continue
            }
            for canonicalPath in candidatePaths {
                guard let entry = vocabulary.index.entry(canonicalPath: canonicalPath),
                    !support.asset(assetID, supports: canonicalPath),
                    !propagated.contains(where: { $0.assetID == assetID && $0.canonicalPath == canonicalPath })
                else {
                    continue
                }
                let consensus = localConsensusRecord(
                    assetID: assetID,
                    targetNodeID: targetNodeID,
                    canonicalPath: canonicalPath,
                    support: support,
                    graph: graph,
                    profile: profile,
                    entry: entry
                )
                localConsensus.append(consensus)
                guard consensus.decisionEligible else {
                    continue
                }
                propagated.append(
                    propagationDecision(
                        assetID: assetID,
                        groupID: targetNodeID,
                        entry: entry,
                        stage: .localAffinityPropagation,
                        supportingAssetIDs: consensusSupportingAssets(
                            targetNodeID: targetNodeID,
                            canonicalPath: canonicalPath,
                            support: support,
                            graph: graph,
                            minimumAffinity: profile.minAffinityForConsensus
                        ),
                        governingRule: consensus.governingRule,
                        localConsensus: consensus,
                        configuration: configuration
                    )
                )
            }
        }
        return propagated
    }

    private func localConsensusRecord(
        assetID: String,
        targetNodeID: String,
        canonicalPath: String,
        support: DirectSupportIndex,
        graph: AssetAffinityGraph,
        profile: AssetAffinityProfile,
        entry: ResolvedVocabularyEntry
    ) -> LocalWeightedConsensusRecord {
        let neighbors = graph.neighbors(of: targetNodeID, minimumAffinity: profile.minAffinityForConsensus)
        let eligibleMass = neighbors.reduce(0) { $0 + $1.affinity }
        let supporting = neighbors.filter { neighbor in
            support.node(neighbor.nodeID, supports: canonicalPath, graph: graph)
        }
        let supportMass = supporting.reduce(0) { $0 + $1.affinity }
        let maxSupportingAffinity = supporting.map(\.affinity).max() ?? 0
        let agreement = eligibleMass > 0 ? supportMass / eligibleMass : nil
        let conflict = conflictMass(
            neighbors: neighbors,
            candidatePath: canonicalPath,
            support: support,
            graph: graph,
            eligibleMass: eligibleMass,
            profile: profile
        )
        var blockReasons: [NormalizationCandidateSkipReason] = []
        if hasDirectConflict(assetID: assetID, candidatePath: canonicalPath, support: support) {
            blockReasons.append(.blockedDirectConflict)
        }
        if let agreement, agreement < localAgreementThreshold(entry.specificity) {
            blockReasons.append(.weakLocalAgreement)
        }
        if supportMass < supportMassThreshold(entry.specificity) {
            blockReasons.append(.lowSupportMass)
        }
        if supporting.count < supportingNeighborThreshold(entry.specificity) {
            blockReasons.append(.lowSupportingNeighborCount)
        }
        if maxSupportingAffinity < 0.55 {
            blockReasons.append(.lowMaxSupportingAffinity)
        }
        if conflict.blocked {
            blockReasons.append(.blockedLocalConflictMass)
        }
        return LocalWeightedConsensusRecord(
            targetAssetID: assetID,
            targetNodeID: targetNodeID,
            canonicalPath: canonicalPath,
            localWeightedAgreement: agreement.map(AffinityScoreFormatter.rounded),
            supportMass: AffinityScoreFormatter.rounded(supportMass),
            eligibleMass: AffinityScoreFormatter.rounded(eligibleMass),
            supportingNeighborCount: supporting.count,
            maxSupportingAffinity: AffinityScoreFormatter.rounded(maxSupportingAffinity),
            conflictSupportMass: AffinityScoreFormatter.rounded(conflict.supportMass),
            conflictWeightedAgreement: conflict.weightedAgreement.map(AffinityScoreFormatter.rounded),
            conflictingCanonicalPaths: conflict.paths,
            decisionEligible: blockReasons.isEmpty,
            blockReasons: stableUnique(blockReasons),
            governingRule: "local_\(entry.specificity.rawValue)_metadata_weighted"
        )
    }

    private func globalBackstopDecisions(
        support: DirectSupportIndex,
        input: NormalizationResolvedInputBatch,
        graph: AssetAffinityGraph,
        profile: AssetAffinityProfile,
        configuration: ResolvedNormalizationConfiguration
    ) -> [PerAssetNormalizationDecision] {
        guard configuration.vocabularyMode == .controlledVocabulary else {
            return []
        }
        let eligibleAssetIDs = input.sourceAssets.map(\.assetID).sorted()
        guard eligibleAssetIDs.count >= profile.globalMinEligibleAssets else {
            return []
        }
        var decisions: [PerAssetNormalizationDecision] = []
        for canonicalPath in support.supportedCanonicalPaths.sorted() {
            guard let entry = vocabulary.index.entry(canonicalPath: canonicalPath),
                entry.autoApplyAllowed,
                !entry.requiresReview,
                entry.propagationScope == .global,
                entry.specificity == .broad
            else {
                continue
            }
            let supporting = support.assetsSupporting(canonicalPath).sorted()
            guard supporting.count >= profile.globalMinSupportingAssets else {
                continue
            }
            let frequency = Double(supporting.count) / Double(eligibleAssetIDs.count)
            guard frequency >= profile.globalConsensusThreshold else {
                continue
            }
            for assetID in eligibleAssetIDs where !support.asset(assetID, supports: canonicalPath) {
                guard !hasDirectConflict(assetID: assetID, candidatePath: canonicalPath, support: support) else {
                    continue
                }
                decisions.append(
                    propagationDecision(
                        assetID: assetID,
                        groupID: graph.nodeIDByAssetID[assetID],
                        entry: entry,
                        stage: .globalBackstopPropagation,
                        supportingAssetIDs: supporting,
                        governingRule: "global_backstop_\(entry.specificity.rawValue)",
                        localConsensus: nil,
                        configuration: configuration
                    )
                )
            }
        }
        return decisions
    }

    private func propagationDecision(
        assetID: String,
        groupID: String?,
        entry: ResolvedVocabularyEntry,
        stage: NormalizationDecisionStage,
        supportingAssetIDs: [String],
        governingRule: String,
        localConsensus: LocalWeightedConsensusRecord?,
        configuration: ResolvedNormalizationConfiguration
    ) -> PerAssetNormalizationDecision {
        let flatKeyword = configuration.writeFlatKeywords && entry.exportFlatKeyword ? entry.flatKeyword : nil
        let hierarchicalKeyword =
            configuration.writeHierarchicalKeywords && entry.exportHierarchicalKeyword
            ? entry.canonicalPath
            : nil
        let isObservedTags = configuration.vocabularyMode == .observedTags
        return PerAssetNormalizationDecision(
            assetID: assetID,
            groupID: groupID,
            stage: stage,
            status: flatKeyword != nil || hierarchicalKeyword != nil ? .accepted : .withheld,
            candidateKind: isObservedTags ? .observedModelTag : .canonicalVocabulary,
            canonicalPath: entry.canonicalPath,
            flatKeyword: flatKeyword,
            hierarchicalKeyword: hierarchicalKeyword,
            namespace: isObservedTags ? nil : entry.namespace,
            directApplyPolicy: entry.directApplyPolicy,
            requiresReview: entry.requiresReview,
            exportFlatKeyword: flatKeyword != nil,
            exportHierarchicalKeyword: hierarchicalKeyword != nil,
            supportUnits: 1,
            supportingAssetIDs: supportingAssetIDs.sorted(),
            governingRule: governingRule,
            observationCount: 0,
            localConsensus: localConsensus
        )
    }

    private func conflictMass(
        neighbors: [(nodeID: String, affinity: Double)],
        candidatePath: String,
        support: DirectSupportIndex,
        graph: AssetAffinityGraph,
        eligibleMass: Double,
        profile: AssetAffinityProfile
    ) -> (supportMass: Double, weightedAgreement: Double?, paths: [String], blocked: Bool) {
        let conflicts = Set(conflictingCanonicalPaths(for: candidatePath))
        guard !conflicts.isEmpty else {
            return (0, nil, [], false)
        }
        var supportMass = 0.0
        var paths = Set<String>()
        for neighbor in neighbors {
            let neighborPaths = support.exactPathsForNode(neighbor.nodeID, graph: graph)
            let matching = neighborPaths.intersection(conflicts)
            if !matching.isEmpty {
                supportMass += neighbor.affinity
                paths.formUnion(matching)
            }
        }
        let agreement = eligibleMass > 0 ? supportMass / eligibleMass : nil
        let blocked =
            (agreement ?? 0) >= conflictAgreementThreshold(profile.name)
            && supportMass >= 0.75
        return (supportMass, agreement, paths.sorted(), blocked)
    }

    private func hasDirectConflict(
        assetID: String,
        candidatePath: String,
        support: DirectSupportIndex
    ) -> Bool {
        let conflicts = Set(conflictingCanonicalPaths(for: candidatePath))
        return !support.exactPathsByAssetID[assetID, default: []].intersection(conflicts).isEmpty
    }

    private func conflictingCanonicalPaths(for canonicalPath: String) -> [String] {
        guard let entry = vocabulary.index.entry(canonicalPath: canonicalPath) else {
            return []
        }
        var conflicts = Set(vocabulary.index.siblings(of: canonicalPath).map(\.canonicalPath))
        if let group = entry.mutuallyExclusiveGroup {
            conflicts.formUnion(
                vocabulary.index.entries(mutuallyExclusiveGroup: group)
                    .map(\.canonicalPath)
                    .filter { $0 != canonicalPath }
            )
        }
        return conflicts.sorted()
    }

    private func consensusSupportingAssets(
        targetNodeID: String,
        canonicalPath: String,
        support: DirectSupportIndex,
        graph: AssetAffinityGraph,
        minimumAffinity: Double
    ) -> [String] {
        graph.neighbors(of: targetNodeID, minimumAffinity: minimumAffinity)
            .flatMap { neighbor in
                graph.nodeByID[neighbor.nodeID]?
                    .memberAssetIDs
                    .filter { support.asset($0, supports: canonicalPath) } ?? []
            }
            .sorted()
    }

    private func localAgreementThreshold(_ specificity: VocabularySpecificity) -> Double {
        specificity == .broad ? 0.60 : 0.70
    }

    private func supportMassThreshold(_ specificity: VocabularySpecificity) -> Double {
        specificity == .broad ? 0.75 : 1.25
    }

    private func supportingNeighborThreshold(_ specificity: VocabularySpecificity) -> Int {
        specificity == .broad ? 1 : 2
    }

    private func conflictAgreementThreshold(_ profile: NormalizationAffinityProfile) -> Double {
        switch profile {
        case .conservative:
            return 0.35
        case .balanced:
            return 0.30
        case .aggressive:
            return 0.25
        }
    }

    private func assignDecisionIDs(_ decisions: inout [PerAssetNormalizationDecision]) {
        for index in decisions.indices {
            decisions[index].decisionID = String(format: "decision-%06d", index + 1)
        }
    }
}

private struct AssetCanonicalPathKey: Hashable {
    var assetID: String
    var canonicalPath: String
}

private struct DirectSupportIndex {
    var exactPathsByAssetID: [String: Set<String>] = [:]
    var supportedPathsByAssetID: [String: Set<String>] = [:]
    var supportedCanonicalPaths: Set<String> = []
    var supportingAssetsByPath: [String: Set<String>] = [:]
    private let vocabularyIndex: VocabularyIndex

    init(
        decisions: [PerAssetNormalizationDecision],
        vocabulary: LoadedVocabulary,
        eligibleAssetIDs: [String]
    ) {
        self.vocabularyIndex = vocabulary.index
        for assetID in eligibleAssetIDs {
            exactPathsByAssetID[assetID] = []
            supportedPathsByAssetID[assetID] = []
        }
        add(decisions: decisions)
    }

    mutating func add(decisions: [PerAssetNormalizationDecision]) {
        for decision in decisions {
            guard let canonicalPath = decision.canonicalPath else {
                continue
            }
            switch decision.stage {
            case .directModelObservation, .userSessionContext:
                exactPathsByAssetID[decision.assetID, default: []].insert(canonicalPath)
                insertSupportedPath(canonicalPath, assetID: decision.assetID)
                for ancestor in vocabularyIndex.ancestors(of: canonicalPath) {
                    insertSupportedPath(ancestor.canonicalPath, assetID: decision.assetID)
                }
            case .localAffinityPropagation, .globalBackstopPropagation, .phase2Fallback:
                insertSupportedPath(canonicalPath, assetID: decision.assetID)
            }
        }
    }

    private mutating func insertSupportedPath(_ canonicalPath: String, assetID: String) {
        supportedPathsByAssetID[assetID, default: []].insert(canonicalPath)
        supportedCanonicalPaths.insert(canonicalPath)
        supportingAssetsByPath[canonicalPath, default: []].insert(assetID)
    }

    func asset(_ assetID: String, supports canonicalPath: String) -> Bool {
        supportedPathsByAssetID[assetID, default: []].contains(canonicalPath)
    }

    func node(_ nodeID: String, supports canonicalPath: String, graph: AssetAffinityGraph) -> Bool {
        graph.nodeByID[nodeID]?
            .memberAssetIDs
            .contains { asset($0, supports: canonicalPath) } == true
    }

    func assetsSupporting(_ canonicalPath: String) -> Set<String> {
        supportingAssetsByPath[canonicalPath, default: []]
    }

    func exactPathsForNode(_ nodeID: String, graph: AssetAffinityGraph) -> Set<String> {
        let assetIDs = graph.nodeByID[nodeID]?.memberAssetIDs ?? []
        return assetIDs.reduce(into: Set<String>()) { partial, assetID in
            partial.formUnion(exactPathsByAssetID[assetID, default: []])
        }
    }
}

private func compareDecisions(
    _ lhs: PerAssetNormalizationDecision,
    _ rhs: PerAssetNormalizationDecision
) -> Bool {
    if lhs.assetID == rhs.assetID {
        if lhs.stage == rhs.stage {
            return (lhs.canonicalPath ?? lhs.flatKeyword ?? "") < (rhs.canonicalPath ?? rhs.flatKeyword ?? "")
        }
        return lhs.stage.rawValue < rhs.stage.rawValue
    }
    return lhs.assetID < rhs.assetID
}

private func compareLocalConsensus(
    _ lhs: LocalWeightedConsensusRecord,
    _ rhs: LocalWeightedConsensusRecord
) -> Bool {
    if lhs.targetAssetID == rhs.targetAssetID {
        let lhsAgreement = lhs.localWeightedAgreement ?? -1
        let rhsAgreement = rhs.localWeightedAgreement ?? -1
        if lhsAgreement == rhsAgreement {
            if lhs.supportMass == rhs.supportMass {
                return lhs.canonicalPath < rhs.canonicalPath
            }
            return lhs.supportMass > rhs.supportMass
        }
        return lhsAgreement > rhsAgreement
    }
    return lhs.targetAssetID < rhs.targetAssetID
}
