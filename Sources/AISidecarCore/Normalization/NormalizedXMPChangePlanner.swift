import Foundation

/// Result of adapting normalized decisions into Phase 2-compatible XMP plans.
public struct NormalizedXMPChangePlanResult: Sendable, Equatable {
    public var changePlan: XMPChangePlanDocument
    public var writePlans: [NormalizedXMPWritePlan]

    public init(changePlan: XMPChangePlanDocument, writePlans: [NormalizedXMPWritePlan]) {
        self.changePlan = changePlan
        self.writePlans = writePlans
    }
}

/// Converts Phase 3 decisions into shared Phase 2 XMP change-plan records.
public struct NormalizedXMPChangePlanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Build normalized write plans without writing, backing up, or validating XMP sidecars.
    ///
    /// When quality grading requires scalar conflict resolution, reads occur only through the
    /// caller-supplied snapshot reader.
    public func plan(
        input: NormalizationResolvedInputBatch,
        decisions: [PerAssetNormalizationDecision],
        candidateSkips: [NormalizationCandidateSkip],
        configuration: ResolvedNormalizationConfiguration,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)? = nil
    ) throws -> NormalizedXMPChangePlanResult {
        let assetsByID = try uniqueLookup(
            input.sourceAssets.map { ($0.assetID, $0) },
            onDuplicate: { assetID in
                duplicateInputError(kind: "source asset ID", key: assetID)
            }
        )
        let sidecarsByAssetID = try uniqueLookup(
            input.sourceAISidecars.map { ($0.sourceAssetID, $0) },
            onDuplicate: { assetID in
                duplicateInputError(kind: "source-sidecar asset ID", key: assetID)
            }
        )
        let targetInfos = targetInfos(
            groups: input.sameBaseNameGroups,
            assetsByID: assetsByID,
            inputBasePath: input.inputBasePath,
            configuration: configuration
        )
        let collisionPaths = caseInsensitiveCollisionPaths(targetInfos.map(\.targetPath))
        let writePlans = targetInfos.map { info in
            writePlan(
                group: info.group,
                targetPath: info.targetPath,
                targetFailure: info.failure,
                hasCollision: collisionPaths.contains(info.targetPath.lowercased()),
                input: input,
                assetsByID: assetsByID,
                sidecarsByAssetID: sidecarsByAssetID,
                decisions: decisions,
                candidateSkips: candidateSkips,
                configuration: configuration,
                snapshotReader: snapshotReader
            )
        }
        let changePlan = XMPChangePlanDocument(
            dryRun: configuration.dryRun,
            targetPlans: writePlans.map(\.xmpChangePlan),
            inputFailures: input.failures.map {
                XMPChangePlanInputFailure(
                    sidecarPath: $0.path,
                    relativePath: $0.relativePath,
                    error: $0.error
                )
            }
        )
        return NormalizedXMPChangePlanResult(changePlan: changePlan, writePlans: writePlans)
    }

    private func duplicateInputError(kind: String, key: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .normalize,
            message: "Duplicate \(kind) in normalization input: \(key)",
            recoverable: false
        )
    }

    private func writePlan(
        group: NormalizationSourceGroup,
        targetPath: String,
        targetFailure: SidecarError?,
        hasCollision: Bool,
        input: NormalizationResolvedInputBatch,
        assetsByID: [String: NormalizationSourceAsset],
        sidecarsByAssetID: [String: NormalizationSourceAISidecarRecord],
        decisions: [PerAssetNormalizationDecision],
        candidateSkips: [NormalizationCandidateSkip],
        configuration: ResolvedNormalizationConfiguration,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)?
    ) -> NormalizedXMPWritePlan {
        let memberIDs = Set(group.memberAssetIDs)
        let selectedIDs = Set(group.selectedAssetIDs)
        let acceptedGroupDecisions =
            decisions
            .filter { selectedIDs.contains($0.assetID) && $0.status == .accepted }
            .filter { !$0.isForwardCompatUnknown }
            .sorted(by: compareDecisions)
        var groupDecisions: [PerAssetNormalizationDecision] = []
        var blockedDecisions: [UnsafeKeywordDecision] = []
        for decision in acceptedGroupDecisions {
            if let term = unsafeExportTerm(in: decision, configuration: configuration) {
                blockedDecisions.append(UnsafeKeywordDecision(decision: decision, term: term))
            } else {
                groupDecisions.append(decision)
            }
        }
        let safetySkips = blockedDecisions.enumerated().map { offset, blocked in
            NormalizationCandidateSkip(
                skipID: "skip-export-safety-\(group.groupID)-\(String(format: "%06d", offset + 1))",
                reason: .coordinateLikeTerm,
                assetID: blocked.decision.assetID,
                groupID: blocked.decision.groupID,
                term: blocked.term,
                normalizedTerm: KeywordTextNormalizer.normalize(blocked.term),
                foldedTerm: VocabularyTextFolder.fold(blocked.term),
                canonicalPath: blocked.decision.canonicalPath,
                sourceSidecar: sidecarsByAssetID[blocked.decision.assetID]?.sidecarPath,
                sourceImage: assetsByID[blocked.decision.assetID]?.sourcePath
            )
        }
        let groupSkips =
            (candidateSkips
            .filter { skip in
                if let assetID = skip.assetID {
                    return memberIDs.contains(assetID)
                }
                return skip.groupID == group.groupID
            }
            + safetySkips)
            .sorted(by: compareSkips)

        let flat = plannedKeywords(
            from: groupDecisions,
            bag: .flat,
            writeEnabled: configuration.writeFlatKeywords
        )
        let hierarchical = plannedKeywords(
            from: groupDecisions,
            bag: .hierarchical,
            writeEnabled: configuration.writeHierarchicalKeywords
        )
        let gradingInputsByAssetID =
            configuration.qualityGrading.enabled
            ? selectedRawSidecarInputsByAssetID(
                assetIDs: group.selectedAssetIDs,
                rawSidecarInputs: input.rawSidecarInputs,
                sidecarsByAssetID: sidecarsByAssetID
            )
            : [:]
        var failures = [SidecarError]()
        if let targetFailure {
            failures.append(targetFailure)
        }
        if hasCollision {
            failures.append(collisionError(targetPath: targetPath, group: group))
        }
        if group.selectedAssetIDs.isEmpty {
            failures.append(emptySelectionError(group: group, pairScope: configuration.pairScope))
        }

        var plan = XMPChangePlan(
            status: failures.isEmpty ? .planned : .failed,
            targetXMPPath: targetPath,
            targetRelativePath: group.targetRelativePath,
            pairScope: configuration.pairScope,
            sourceMembers: group.memberAssetIDs.compactMap {
                sourceMemberPlan(
                    assetID: $0,
                    selected: selectedIDs.contains($0),
                    asset: assetsByID[$0],
                    sidecar: sidecarsByAssetID[$0],
                    rawSidecarInput: gradingInputsByAssetID[$0],
                    decisions: groupDecisions,
                    pairScope: configuration.pairScope,
                    includesQualityProvenance: configuration.qualityGrading.enabled
                )
            },
            flatKeywordsToAdd: flat.keywords,
            hierarchicalKeywordsToAdd: hierarchical.keywords,
            skippedCandidates: groupSkips.map(skippedCandidate),
            candidateExtractionIssues: [],
            sourceVerificationWarnings: group.memberAssetIDs
                .compactMap { sidecarsByAssetID[$0] }
                .flatMap(\.warnings),
            groupWarnings: groupWarnings(group: group, pairScope: configuration.pairScope),
            existingPolicy: configuration.xmpConflictPolicy,
            backupPlan: BackupPlan(
                backupSidecars: configuration.backupSidecars,
                backupRequiredBeforeMerge: configuration.xmpConflictPolicy == .backupAndMerge,
                conflictPolicy: configuration.xmpConflictPolicy
            ),
            validationPlan: .phase2Default,
            failures: failures
        )
        QualityGradingPlanApplier().apply(
            to: &plan,
            inputs: group.selectedAssetIDs.compactMap { gradingInputsByAssetID[$0] },
            grading: configuration.qualityGrading,
            writeFlatKeywords: configuration.writeFlatKeywords,
            writeHierarchicalKeywords: configuration.writeHierarchicalKeywords,
            snapshotReader: snapshotReader
        )
        return NormalizedXMPWritePlan(
            xmpChangePlan: plan,
            flatKeywordProvenance: flat.provenance,
            hierarchicalKeywordProvenance: hierarchical.provenance,
            normalizationSkips: groupSkips
        )
    }

    private func plannedKeywords(
        from decisions: [PerAssetNormalizationDecision],
        bag: NormalizedXMPKeywordBag,
        writeEnabled: Bool
    ) -> (keywords: [PlannedKeyword], provenance: [NormalizedXMPKeywordProvenance]) {
        guard writeEnabled else {
            return ([], [])
        }
        var accumulators: [String: PlannedKeywordAccumulator] = [:]
        for decision in decisions {
            let term: String?
            let exportEnabled: Bool
            switch bag {
            case .flat:
                term = decision.flatKeyword
                exportEnabled = decision.exportFlatKeyword
            case .hierarchical:
                term = decision.hierarchicalKeyword
                exportEnabled = decision.exportHierarchicalKeyword
            }
            guard exportEnabled, let normalizedTerm = term.map(KeywordTextNormalizer.normalize), !normalizedTerm.isEmpty
            else {
                continue
            }
            let key = KeywordTextNormalizer.deduplicationKey(for: normalizedTerm)
            var accumulator =
                accumulators[key]
                ?? PlannedKeywordAccumulator(
                    term: normalizedTerm,
                    normalizedKey: key,
                    bag: bag
                )
            accumulator.decisions.append(decision)
            accumulator.candidates.append(contentsOf: decision.observations.map { extractedCandidate(from: $0) })
            accumulators[key] = accumulator
        }
        let sorted = accumulators.values.sorted { comparePaths($0.term, $1.term) }
        return (
            sorted.map {
                PlannedKeyword(
                    term: $0.term,
                    normalizedKey: $0.normalizedKey,
                    candidates: $0.candidates.sorted(by: compareExtractedCandidates)
                )
            },
            sorted.map(\.provenance)
        )
    }

    private func unsafeExportTerm(
        in decision: PerAssetNormalizationDecision,
        configuration: ResolvedNormalizationConfiguration
    ) -> String? {
        let candidates: [(enabled: Bool, term: String?)] = [
            (configuration.writeFlatKeywords && decision.exportFlatKeyword, decision.flatKeyword),
            (
                configuration.writeHierarchicalKeywords && decision.exportHierarchicalKeyword,
                decision.hierarchicalKeyword
            ),
        ]
        return candidates.lazy.compactMap { candidate in
            guard candidate.enabled,
                let term = candidate.term.map(KeywordTextNormalizer.normalize),
                KeywordSafetyPolicy.isUnsafeKeyword(term)
            else {
                return nil
            }
            return term
        }.first
    }

    private func sourceMemberPlan(
        assetID: String,
        selected: Bool,
        asset: NormalizationSourceAsset?,
        sidecar: NormalizationSourceAISidecarRecord?,
        rawSidecarInput: ResolvedRawSidecarInput?,
        decisions: [PerAssetNormalizationDecision],
        pairScope: XMPPairScope,
        includesQualityProvenance: Bool
    ) -> SourceMemberPlan? {
        guard let asset else {
            return nil
        }
        let assetDecisions = selected ? decisions.filter { $0.assetID == assetID } : []
        let sourcePath = asset.sourcePath
        let sourceSidecarPath: String?
        if let candidate = sidecar?.sidecarPath, candidate.lowercased().hasSuffix(".ai.json") {
            sourceSidecarPath = candidate
        } else {
            sourceSidecarPath = nil
        }
        return SourceMemberPlan(
            sourcePath: sourcePath,
            sourceRelativePath: asset.sourceRelativePath,
            sourceFileName: asset.fileName,
            sourceType: asset.sourceType,
            sourceSidecarPath: sourceSidecarPath,
            sourceSidecarRelativePath: sidecar?.relativePath,
            sourceIdentityStatus: asset.sourceIdentityStatus ?? .skipped,
            pairKind: XMPSourcePairKind(sourceType: asset.sourceType),
            selected: selected,
            skipReason: selected ? nil : skipReason(pairScope: pairScope),
            flatKeywordContributionCount: assetDecisions.filter { $0.flatKeyword != nil && $0.exportFlatKeyword }.count,
            hierarchicalKeywordContributionCount: assetDecisions.filter {
                $0.hierarchicalKeyword != nil && $0.exportHierarchicalKeyword
            }.count,
            qualitySidecarPath: selected && includesQualityProvenance
                ? distinctQualitySidecarPath(for: rawSidecarInput)
                : nil
        )
    }

    private func selectedRawSidecarInputsByAssetID(
        assetIDs: [String],
        rawSidecarInputs: [ResolvedRawSidecarInput],
        sidecarsByAssetID: [String: NormalizationSourceAISidecarRecord]
    ) -> [String: ResolvedRawSidecarInput] {
        var inputsByPath: [String: ResolvedRawSidecarInput] = [:]
        for input in rawSidecarInputs {
            inputsByPath[input.sidecarPath.standardizedFileURL.path] = input
            if let qualitySidecarPath = input.qualitySidecarPath?.standardizedFileURL.path {
                inputsByPath[qualitySidecarPath] = input
            }
        }

        var result: [String: ResolvedRawSidecarInput] = [:]
        for assetID in assetIDs {
            guard let sidecarPath = sidecarsByAssetID[assetID]?.sidecarPath else {
                continue
            }
            let standardizedPath = URL(fileURLWithPath: sidecarPath).standardizedFileURL.path
            result[assetID] = inputsByPath[standardizedPath]
        }
        return result
    }

    private func distinctQualitySidecarPath(for input: ResolvedRawSidecarInput?) -> String? {
        guard let input,
            let qualitySidecarPath = input.qualitySidecarPath?.standardizedFileURL.path,
            qualitySidecarPath != input.sidecarPath.standardizedFileURL.path
        else {
            return nil
        }
        return qualitySidecarPath
    }

    private func targetInfos(
        groups: [NormalizationSourceGroup],
        assetsByID: [String: NormalizationSourceAsset],
        inputBasePath: String,
        configuration: ResolvedNormalizationConfiguration
    ) -> [TargetInfo] {
        groups.sorted { comparePaths($0.targetRelativePath, $1.targetRelativePath) }.map { group in
            let target = targetPath(
                group: group,
                assetsByID: assetsByID,
                inputBasePath: inputBasePath,
                outputDir: configuration.outputDir
            )
            return TargetInfo(group: group, targetPath: target.path, failure: target.failure)
        }
    }

    private func targetPath(
        group: NormalizationSourceGroup,
        assetsByID: [String: NormalizationSourceAsset],
        inputBasePath: String,
        outputDir: String?
    ) -> (path: String, failure: SidecarError?) {
        if let outputDir {
            return (
                relativeComponents(for: group.targetRelativePath).reduce(
                    absoluteURL(for: outputDir, fileManager: fileManager)
                ) {
                    $0.appendingPathComponent($1)
                }.standardizedFileURL.path,
                nil
            )
        }
        let representativeIDs = group.selectedAssetIDs.isEmpty ? group.memberAssetIDs : group.selectedAssetIDs
        if let sourcePath =
            representativeIDs
            .compactMap({ assetsByID[$0]?.sourcePath })
            .first
        {
            let target = URL(fileURLWithPath: sourcePath)
                .standardizedFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(group.groupBasename).xmp")
            return (target.path, nil)
        }
        let fallback = relativeComponents(for: group.targetRelativePath)
            .reduce(absoluteURL(for: inputBasePath, fileManager: fileManager)) { $0.appendingPathComponent($1) }
            .standardizedFileURL
            .path
        return (
            fallback,
            SidecarError(
                code: .sourceMissing,
                stage: .write,
                message:
                    "Unable to derive beside-source XMP path without a resolved source image: \(group.targetRelativePath)",
                recoverable: true
            )
        )
    }

    private func caseInsensitiveCollisionPaths(_ paths: [String]) -> Set<String> {
        Set(
            Dictionary(grouping: paths, by: { $0.lowercased() })
                .filter { $0.value.count > 1 }
                .keys
        )
    }

    private func groupWarnings(group: NormalizationSourceGroup, pairScope: XMPPairScope) -> [SidecarError] {
        var warnings: [SidecarError] = []
        if group.memberAssetIDs.count > 1 {
            warnings.append(
                SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message:
                        "Same-base-name group detected for \(group.targetRelativePath) using pair scope \(pairScope.rawValue).",
                    recoverable: true
                )
            )
        }
        if !group.skippedAssetIDs.isEmpty, pairScope != .union {
            warnings.append(
                SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message:
                        "Pair scope \(pairScope.rawValue) skipped \(group.skippedAssetIDs.count) member(s) for \(group.targetRelativePath).",
                    recoverable: true
                )
            )
        }
        return warnings
    }

    private func collisionError(targetPath: String, group: NormalizationSourceGroup) -> SidecarError {
        SidecarError(
            code: .sidecarCollision,
            stage: .write,
            message:
                "Case-insensitive XMP target collision for \(targetPath): \(group.memberAssetIDs.joined(separator: ", "))",
            recoverable: true
        )
    }

    private func emptySelectionError(group: NormalizationSourceGroup, pairScope: XMPPairScope) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Pair scope \(pairScope.rawValue) selected no source members for \(group.targetRelativePath).",
            recoverable: true
        )
    }

    private func skipReason(pairScope: XMPPairScope) -> XMPSourceMemberSkipReason? {
        switch pairScope {
        case .union:
            return nil
        case .rawOnly:
            return .pairScopeRawOnly
        case .jpegOnly:
            return .pairScopeJPEGOnly
        }
    }

    private func skippedCandidate(_ skip: NormalizationCandidateSkip) -> SkippedCandidate {
        SkippedCandidate(
            reason: CandidateSkipReasonBridge.skippedCandidateReason(for: skip.reason),
            candidate: nil,
            term: skip.term ?? skip.canonicalPath,
            normalizedTerm: skip.normalizedTerm
        )
    }

    private func extractedCandidate(from observation: CandidateObservation) -> ExtractedCandidate {
        ExtractedCandidate(
            term: observation.term,
            normalizedTerm: observation.normalizedTerm,
            confidence: observation.confidence,
            evidence: observation.evidence,
            provenance: observation.provenance
        )
    }
}

private struct UnsafeKeywordDecision {
    var decision: PerAssetNormalizationDecision
    var term: String
}

private struct TargetInfo {
    var group: NormalizationSourceGroup
    var targetPath: String
    var failure: SidecarError?
}

private struct PlannedKeywordAccumulator {
    var term: String
    var normalizedKey: String
    var bag: NormalizedXMPKeywordBag
    var decisions: [PerAssetNormalizationDecision] = []
    var candidates: [ExtractedCandidate] = []

    var provenance: NormalizedXMPKeywordProvenance {
        let sortedDecisions = decisions.sorted(by: compareDecisions)
        return NormalizedXMPKeywordProvenance(
            term: term,
            normalizedKey: normalizedKey,
            keywordBag: bag,
            decisionIDs: uniqueStrings(sortedDecisions.map(\.decisionID)),
            assetIDs: uniqueStrings(sortedDecisions.map(\.assetID)),
            stages: uniqueStages(sortedDecisions.map(\.stage)),
            candidateKinds: uniqueCandidateKinds(sortedDecisions.map(\.candidateKind)),
            canonicalPaths: uniqueStrings(sortedDecisions.compactMap(\.canonicalPath)),
            observationIDs: uniqueStrings(sortedDecisions.flatMap { $0.observations.map(\.observationID) }),
            sourceTexts: uniqueStrings(sortedDecisions.compactMap(\.sourceText)),
            contextTypes: uniqueContextTypes(sortedDecisions.compactMap(\.contextType)),
            governingRules: uniqueStrings(sortedDecisions.compactMap(\.governingRule)),
            supportingAssetIDs: uniqueStrings(sortedDecisions.flatMap(\.supportingAssetIDs))
        )
    }
}

private func compareDecisions(_ lhs: PerAssetNormalizationDecision, _ rhs: PerAssetNormalizationDecision) -> Bool {
    if lhs.assetID == rhs.assetID {
        return lhs.decisionID < rhs.decisionID
    }
    return lhs.assetID < rhs.assetID
}

private func compareSkips(_ lhs: NormalizationCandidateSkip, _ rhs: NormalizationCandidateSkip) -> Bool {
    lhs.skipID < rhs.skipID
}

private func compareExtractedCandidates(_ lhs: ExtractedCandidate, _ rhs: ExtractedCandidate) -> Bool {
    if lhs.provenance.sourceSidecar == rhs.provenance.sourceSidecar {
        if lhs.provenance.modelRunIndex == rhs.provenance.modelRunIndex {
            if lhs.provenance.sourceField == rhs.provenance.sourceField {
                return lhs.term < rhs.term
            }
            return lhs.provenance.sourceField.rawValue < rhs.provenance.sourceField.rawValue
        }
        return lhs.provenance.modelRunIndex < rhs.provenance.modelRunIndex
    }
    return comparePaths(lhs.provenance.sourceSidecar, rhs.provenance.sourceSidecar)
}

private func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
        result.append(value)
    }
    return result
}

private func uniqueStages(_ values: [NormalizationDecisionStage]) -> [NormalizationDecisionStage] {
    var seen = Set<String>()
    var result: [NormalizationDecisionStage] = []
    for value in values where seen.insert(value.rawValue).inserted {
        result.append(value)
    }
    return result
}

private func uniqueCandidateKinds(_ values: [NormalizedCandidateKind]) -> [NormalizedCandidateKind] {
    var seen = Set<String>()
    var result: [NormalizedCandidateKind] = []
    for value in values where seen.insert(value.rawValue).inserted {
        result.append(value)
    }
    return result
}

private func uniqueContextTypes(_ values: [NormalizationSessionContextType]) -> [NormalizationSessionContextType] {
    var seen = Set<String>()
    var result: [NormalizationSessionContextType] = []
    for value in values where seen.insert(value.rawValue).inserted {
        result.append(value)
    }
    return result
}

private func relativeComponents(for relativePath: String) -> [String] {
    relativePath.split(separator: "/").map(String.init)
}
