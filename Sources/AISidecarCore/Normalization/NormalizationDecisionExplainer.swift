import Foundation

// CaseIterable conformances so explainer coverage can be tested exhaustively;
// the raw values themselves are load-bearing and unchanged.
extension NormalizationDecisionStage: CaseIterable {
    public static var allCases: [NormalizationDecisionStage] {
        [
            .directModelObservation, .userSessionContext, .localAffinityPropagation, .globalBackstopPropagation,
            .phase2Fallback,
        ]
    }
}

extension NormalizationDecisionStatus: CaseIterable {
    public static var allCases: [NormalizationDecisionStatus] {
        [.accepted, .withheld, .skipped]
    }
}

extension NormalizedCandidateKind: CaseIterable {
    public static var allCases: [NormalizedCandidateKind] {
        [
            .canonicalVocabulary, .observedModelTag, .modelSpeciesFallback, .phase2Fallback, .userContextUnnormalized,
            .userEdited,
        ]
    }
}

/// Per-keyword rollup of a session's decisions — the shared shape behind the
/// GUI Normalization Inspector and `aisidecar explain-session` (FR4-055).
public struct KeywordDecisionSummary: Sendable, Equatable {
    /// One asset's contribution to the keyword, for expandable detail rows.
    public struct AssetDetail: Sendable, Equatable {
        public var decisionID: String
        public var assetID: String
        public var status: NormalizationDecisionStatus
        public var stage: NormalizationDecisionStage
        public var governingRule: String?
        public var skipReasons: [NormalizationCandidateSkipReason]
        public var supportUnits: Int
        public var conflictingCanonicalPaths: [String]
    }

    public var keyword: String
    public var canonicalPath: String?
    public var candidateKinds: [NormalizedCandidateKind]
    public var acceptedCount: Int
    public var withheldCount: Int
    public var skippedCount: Int
    public var stages: [NormalizationDecisionStage]
    public var governingRules: [String]
    public var skipReasonCounts: [NormalizationCandidateSkipReason: Int]
    public var supportingAssetCount: Int
    public var totalSupportUnits: Int
    public var requiresReview: Bool
    public var conflictingCanonicalPaths: [String]
    public var assetDetails: [AssetDetail]

    /// Number of assets carrying this keyword (distinct from
    /// `supportingAssetCount`, which counts affinity supporters).
    public var assetCount: Int { Set(assetDetails.map(\.assetID)).count }

    public var unmatchedVocabulary: Bool {
        canonicalPath == nil || skipReasonCounts[.unmatchedVocabulary] != nil
    }

    /// FR4-026 "needs attention": review-gated, conflicted, or unmatched.
    public var needsAttention: Bool {
        requiresReview || !conflictingCanonicalPaths.isEmpty || unmatchedVocabulary
    }
}

/// One mapping from normalization enums to user-facing language, plus the
/// session rollup both consumers render. Adding an enum case without a
/// sentence here is a compile error — that is the point.
public enum NormalizationDecisionExplainer {
    // MARK: - Enum → sentence

    public static func text(for stage: NormalizationDecisionStage) -> String {
        switch stage {
        case .directModelObservation:
            "the vision model observed this directly in the image"
        case .userSessionContext:
            "you supplied this as session context for the batch"
        case .localAffinityPropagation:
            "propagated from strongly related photos nearby in the batch"
        case .globalBackstopPropagation:
            "propagated by batch-wide consensus"
        case .phase2Fallback:
            "carried over as an unreviewed fallback tag"
        }
    }

    public static func text(for status: NormalizationDecisionStatus) -> String {
        switch status {
        case .accepted: "will be written to XMP"
        case .withheld: "decided but not exported"
        case .skipped: "no decision was made"
        }
    }

    public static func text(for kind: NormalizedCandidateKind) -> String {
        switch kind {
        case .canonicalVocabulary: "matched a vocabulary entry"
        case .observedModelTag: "model output with no vocabulary match"
        case .modelSpeciesFallback: "model species without a vocabulary hierarchy"
        case .phase2Fallback: "fallback term"
        case .userContextUnnormalized: "user context written without vocabulary normalization"
        case .userEdited: "keyword text edited during review"
        }
    }

    public static func text(for reason: NormalizationCandidateSkipReason) -> String {
        switch reason {
        case .belowConfidenceThreshold:
            "the model's confidence was below the minimum band"
        case .unmatchedVocabulary:
            "no vocabulary entry matches this term"
        case .directApplyWithheld:
            "the vocabulary marks this entry direct-apply: withhold"
        case .directApplyFlatOnly:
            "the vocabulary allows this entry as a flat keyword only"
        case .requiresReview:
            "the vocabulary marks this entry as requiring manual review"
        case .specificTagPolicy:
            "specific unmatched tags are disabled for this run"
        case .containsHierarchySeparator:
            "raw model text containing '|' is never exported as hierarchy"
        case .emptyAfterNormalization:
            "nothing remained after normalization folding"
        case .duplicate:
            "another decision already covers this keyword for the asset"
        case .disabledFlatExport:
            "flat keyword export is disabled for this run"
        case .disabledHierarchicalExport:
            "hierarchical keyword export is disabled for this run"
        case .coordinateLikeTerm:
            "the term looks like coordinates, which are never exported"
        case .gpsOnlyEvidence:
            "the only evidence is GPS context, which never becomes a keyword"
        case .speciesWithoutBiologicalGenre:
            "the model listed a species without a wildlife, bird, or plant genre"
        case .unknownSessionContextRejected:
            "session context did not match the vocabulary and the policy is reject"
        case .unknownSessionContextFlatOnly:
            "unmatched session context may be written as a flat keyword only"
        case .weakLocalAgreement:
            "nearby-photo agreement is below the consensus threshold"
        case .lowSupportMass:
            "too little weighted support across the batch"
        case .lowSupportingNeighborCount:
            "too few supporting neighbor photos"
        case .lowMaxSupportingAffinity:
            "no supporting photo is closely enough related"
        case .blockedDirectConflict:
            "the asset itself supports a competing keyword"
        case .blockedLocalConflictMass:
            "nearby photos support a competing keyword too strongly"
        case .gearOnlyAffinity:
            "photos are related only by camera gear, which cannot propagate content"
        case .globalBackstopThreshold:
            "batch-wide agreement is below the backstop threshold"
        case .sessionContextConflict:
            "this asset's own observations conflict with the session context"
        case .userReviewRejected:
            "rejected during review"
        case .userReviewDeferred:
            "deferred during review"
        }
    }

    // MARK: - Session rollup

    /// Roll a session's per-asset decisions up to per-keyword summaries,
    /// sorted by display keyword. Grouping key: canonical path when the
    /// vocabulary matched, otherwise the case/whitespace-folded term.
    public static func summaries(for session: NormalizationSessionDocument) -> [KeywordDecisionSummary] {
        var grouped: [String: [PerAssetNormalizationDecision]] = [:]
        for decision in session.perAssetDecisions {
            grouped[groupingKey(for: decision), default: []].append(decision)
        }
        return grouped.values
            .map(summarize)
            .sorted { $0.keyword.lowercased() < $1.keyword.lowercased() }
    }

    /// Summary for one keyword by display name, canonical path, or source
    /// text (folded comparison).
    public static func summary(
        for keyword: String,
        in session: NormalizationSessionDocument
    ) -> KeywordDecisionSummary? {
        let folded = fold(keyword)
        return summaries(for: session).first { summary in
            fold(summary.keyword) == folded
                || summary.canonicalPath.map(fold) == folded
                || fold(String(summary.keyword.split(separator: "|").last ?? "")) == folded
        }
    }

    public static func needsAttention(in session: NormalizationSessionDocument) -> [KeywordDecisionSummary] {
        summaries(for: session).filter(\.needsAttention)
    }

    private static func groupingKey(for decision: PerAssetNormalizationDecision) -> String {
        if let canonicalPath = decision.canonicalPath, !canonicalPath.isEmpty {
            return "c:" + canonicalPath
        }
        return "t:" + fold(displayKeyword(for: decision))
    }

    private static func displayKeyword(for decision: PerAssetNormalizationDecision) -> String {
        decision.canonicalPath
            ?? decision.hierarchicalKeyword
            ?? decision.flatKeyword
            ?? decision.sourceText
            ?? "(unnamed)"
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func summarize(_ decisions: [PerAssetNormalizationDecision]) -> KeywordDecisionSummary {
        let first = decisions[0]
        var stages: [NormalizationDecisionStage] = []
        var rules: [String] = []
        var kinds: [NormalizedCandidateKind] = []
        var reasonCounts: [NormalizationCandidateSkipReason: Int] = [:]
        var supporters: Set<String> = []
        var conflicts: [String] = []
        var details: [KeywordDecisionSummary.AssetDetail] = []

        for decision in decisions.sorted(by: { lhs, rhs in
            if lhs.assetID != rhs.assetID {
                return lhs.assetID < rhs.assetID
            }
            if lhs.decisionID != rhs.decisionID {
                return lhs.decisionID < rhs.decisionID
            }
            return lhs.stage.rawValue < rhs.stage.rawValue
        }) {
            if !stages.contains(decision.stage) { stages.append(decision.stage) }
            if let rule = decision.governingRule, !rules.contains(rule) { rules.append(rule) }
            if !kinds.contains(decision.candidateKind) { kinds.append(decision.candidateKind) }
            for reason in decision.skipReasons {
                reasonCounts[reason, default: 0] += 1
            }
            supporters.formUnion(decision.supportingAssetIDs)
            let decisionConflicts = decision.localConsensus?.conflictingCanonicalPaths ?? []
            for conflict in decisionConflicts where !conflicts.contains(conflict) {
                conflicts.append(conflict)
            }
            details.append(
                KeywordDecisionSummary.AssetDetail(
                    decisionID: decision.decisionID,
                    assetID: decision.assetID,
                    status: decision.status,
                    stage: decision.stage,
                    governingRule: decision.governingRule,
                    skipReasons: decision.skipReasons,
                    supportUnits: decision.supportUnits,
                    conflictingCanonicalPaths: decisionConflicts
                )
            )
        }

        return KeywordDecisionSummary(
            keyword: displayKeyword(for: first),
            canonicalPath: first.canonicalPath,
            candidateKinds: kinds,
            acceptedCount: decisions.count { $0.status == .accepted },
            withheldCount: decisions.count { $0.status == .withheld },
            skippedCount: decisions.count { $0.status == .skipped },
            stages: stages,
            governingRules: rules,
            skipReasonCounts: reasonCounts,
            supportingAssetCount: supporters.count,
            totalSupportUnits: decisions.reduce(0) { $0 + $1.supportUnits },
            requiresReview: decisions.contains { $0.requiresReview },
            conflictingCanonicalPaths: conflicts,
            assetDetails: details
        )
    }

    // MARK: - Text rendering (CLI-1 and anywhere else that wants lines)

    /// Multi-line plain-text explanation of one keyword summary.
    public static func renderLines(_ summary: KeywordDecisionSummary, verbose: Bool = false) -> [String] {
        var lines: [String] = []
        var header = summary.keyword
        if summary.needsAttention {
            header += "   [needs attention]"
        }
        lines.append(header)
        lines.append(
            "  outcome: \(summary.acceptedCount) accepted · \(summary.withheldCount) withheld · \(summary.skippedCount) skipped"
        )
        lines.append("  support: \(summary.assetCount) assets · \(summary.totalSupportUnits) units")
        lines.append("  origin:  " + summary.stages.map(text(for:)).joined(separator: "; "))
        if !summary.governingRules.isEmpty {
            lines.append("  rules:   " + summary.governingRules.joined(separator: ", "))
        }
        for (reason, count) in summary.skipReasonCounts.sorted(by: {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }) {
            lines.append("  skipped ×\(count): \(text(for: reason)) (\(reason.rawValue))")
        }
        if !summary.conflictingCanonicalPaths.isEmpty {
            lines.append("  conflicts with: " + summary.conflictingCanonicalPaths.joined(separator: ", "))
        }
        if summary.requiresReview {
            lines.append("  review:  the vocabulary marks this entry as requiring manual review")
        }
        if verbose {
            for detail in summary.assetDetails {
                var line = "    \(detail.assetID): \(detail.status.rawValue) — \(text(for: detail.stage))"
                if !detail.skipReasons.isEmpty {
                    line += " (" + detail.skipReasons.map(\.rawValue).joined(separator: ", ") + ")"
                }
                lines.append(line)
            }
        }
        return lines
    }
}
