import Foundation

struct XMPChangePlanAssembler {
    struct Settings {
        var pairScope: XMPPairScope
        var conflictPolicy: XMPConflictPolicy
        var backupSidecars: Bool
        var writeFlatKeywords: Bool
        var writeHierarchicalKeywords: Bool
        var qualityGrading: ResolvedQualityGradingConfiguration
    }

    struct TargetContent {
        var targetXMPPath: String
        var targetRelativePath: String
        var sourceMembers: [SourceMemberPlan]
        var flatKeywords: [PlannedKeyword]
        var hierarchicalKeywords: [PlannedKeyword]
        var skippedCandidates: [SkippedCandidate]
        var candidateExtractionIssues: [CandidateExtractionIssue]
        var sourceVerificationWarnings: [SidecarError]
        var groupWarnings: [SidecarError]
        var failures: [SidecarError]
        var gradingInputs: [ResolvedRawSidecarInput]
    }

    struct SourceMemberContent {
        var sourcePath: String?
        var sourceRelativePath: String
        var sourceFileName: String
        var sourceType: SupportedImageType
        var sourceSidecarPath: String?
        var sourceSidecarRelativePath: String?
        var sourceIdentityStatus: SourceIdentityStatus
        var pairKind: XMPSourcePairKind
        var selected: Bool
        var flatKeywordContributionCount: Int
        var hierarchicalKeywordContributionCount: Int
        var qualityInput: ResolvedRawSidecarInput?
        var includesQualityProvenance: Bool
    }

    enum KeywordOrder {
        case stable
        case termSorted
    }

    enum CandidateOrder {
        case stable
        case provenanceSorted
    }

    func assemble(
        _ content: TargetContent,
        settings: Settings,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)?
    ) -> XMPChangePlan {
        var plan = XMPChangePlan(
            status: content.failures.isEmpty ? .planned : .failed,
            targetXMPPath: content.targetXMPPath,
            targetRelativePath: content.targetRelativePath,
            pairScope: settings.pairScope,
            sourceMembers: content.sourceMembers,
            flatKeywordsToAdd: content.flatKeywords,
            hierarchicalKeywordsToAdd: content.hierarchicalKeywords,
            skippedCandidates: content.skippedCandidates,
            candidateExtractionIssues: content.candidateExtractionIssues,
            sourceVerificationWarnings: content.sourceVerificationWarnings,
            groupWarnings: content.groupWarnings,
            existingPolicy: settings.conflictPolicy,
            backupPlan: BackupPlan(
                backupSidecars: settings.backupSidecars,
                backupRequiredBeforeMerge: settings.conflictPolicy == .backupAndMerge,
                conflictPolicy: settings.conflictPolicy
            ),
            // Execution turns this shared intent into post-write snapshot and fingerprint checks.
            validationPlan: .phase2Default,
            failures: content.failures
        )
        QualityGradingPlanApplier().apply(
            to: &plan,
            inputs: content.gradingInputs,
            grading: settings.qualityGrading,
            writeFlatKeywords: settings.writeFlatKeywords,
            writeHierarchicalKeywords: settings.writeHierarchicalKeywords,
            snapshotReader: snapshotReader
        )
        return plan
    }

    func sourceMemberPlan(
        _ content: SourceMemberContent,
        pairScope: XMPPairScope
    ) -> SourceMemberPlan {
        SourceMemberPlan(
            sourcePath: content.sourcePath,
            sourceRelativePath: content.sourceRelativePath,
            sourceFileName: content.sourceFileName,
            sourceType: content.sourceType,
            sourceSidecarPath: content.sourceSidecarPath,
            sourceSidecarRelativePath: content.sourceSidecarRelativePath,
            sourceIdentityStatus: content.sourceIdentityStatus,
            pairKind: content.pairKind,
            selected: content.selected,
            skipReason: content.selected ? nil : skipReason(pairScope: pairScope),
            flatKeywordContributionCount: content.flatKeywordContributionCount,
            hierarchicalKeywordContributionCount: content.hierarchicalKeywordContributionCount,
            qualitySidecarPath: content.selected && content.includesQualityProvenance
                ? distinctQualitySidecarPath(for: content.qualityInput)
                : nil
        )
    }

    func mergeKeywords(
        _ contributions: [PlannedKeyword],
        keywordOrder: KeywordOrder = .stable,
        candidateOrder: CandidateOrder = .stable
    ) -> [PlannedKeyword] {
        var keywords: [PlannedKeyword] = []
        var indexByKey: [String: Int] = [:]

        for contribution in contributions {
            if let index = indexByKey[contribution.normalizedKey] {
                keywords[index].candidates.append(contentsOf: contribution.candidates)
            } else {
                indexByKey[contribution.normalizedKey] = keywords.count
                keywords.append(contribution)
            }
        }

        if candidateOrder == .provenanceSorted {
            for index in keywords.indices {
                keywords[index].candidates.sort(by: Self.compareExtractedCandidates)
            }
        }
        if keywordOrder == .termSorted {
            keywords.sort { comparePaths($0.term, $1.term) }
        }
        return keywords
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

    private func distinctQualitySidecarPath(for input: ResolvedRawSidecarInput?) -> String? {
        guard let input,
            let qualitySidecarPath = input.qualitySidecarPath?.standardizedFileURL.path,
            qualitySidecarPath != input.sidecarPath.standardizedFileURL.path
        else {
            return nil
        }
        return qualitySidecarPath
    }

    private static func compareExtractedCandidates(_ lhs: ExtractedCandidate, _ rhs: ExtractedCandidate) -> Bool {
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
}
