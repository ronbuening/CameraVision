import Foundation

/// A human review verdict for one per-asset decision (Phase 4 candidate
/// review, FR4-017). Verdicts are stored *in* the session document via
/// decision status + user-review skip reasons, so a reviewed session remains
/// a plain Phase 3 session: `apply-session` writes exactly the approved set
/// with no new code paths (AC4-013).
public enum ReviewVerdict: String, Codable, Sendable, Equatable {
    case approved
    case rejected
    case deferred
}

/// Applies review verdicts and keyword edits onto a session document, and
/// reconstructs them from one — the sidecar-only durability mechanism for
/// review state (NFR4-008, FR4-046a).
public enum SessionReview {
    /// Flat user edits must remain valid Phase 2 keywords; hierarchy may only
    /// come from a controlled vocabulary canonical path, and GPS metadata or
    /// coordinate syntax cannot cross the XMP boundary (FR3-003g/h, invariant 3).
    public static func sanitizedEdit(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            !trimmed.contains("|"),
            !KeywordSafetyPolicy.isUnsafeKeyword(trimmed)
        else {
            return nil
        }
        return trimmed
    }

    /// Return a copy of `session` with verdicts and edits applied.
    ///
    /// - approved → `status = .accepted`, user-review reasons removed
    /// - rejected → `status = .withheld` + `user_review_rejected`
    /// - deferred → `status = .withheld` + `user_review_deferred`
    /// - edit     → flat keyword replaced (`user_edited` kind, original kept
    ///              in `source_text`), flat-only export
    ///
    /// Decisions without a verdict are left untouched, so machine-made
    /// decisions survive round trips unreviewed.
    public static func applying(
        verdicts: [String: ReviewVerdict],
        edits: [String: String] = [:],
        to session: NormalizationSessionDocument
    ) -> NormalizationSessionDocument {
        var reviewed = session
        reviewed.perAssetDecisions = session.perAssetDecisions.map { decision in
            var decision = decision
            guard !decision.isForwardCompatUnknown else {
                return decision
            }
            if let editedText = edits[decision.decisionID].flatMap(sanitizedEdit) {
                if decision.sourceText == nil {
                    decision.sourceText = decision.flatKeyword ?? decision.canonicalPath
                }
                decision.flatKeyword = editedText
                decision.hierarchicalKeyword = nil
                decision.canonicalPath = nil
                decision.candidateKind = .userEdited
                decision.exportFlatKeyword = true
                decision.exportHierarchicalKeyword = false
            }
            if let verdict = verdicts[decision.decisionID] {
                decision.skipReasons.removeAll { $0 == .userReviewRejected || $0 == .userReviewDeferred }
                switch verdict {
                case .approved:
                    decision.status = .accepted
                case .rejected:
                    decision.status = .withheld
                    decision.skipReasons.append(.userReviewRejected)
                case .deferred:
                    decision.status = .withheld
                    decision.skipReasons.append(.userReviewDeferred)
                }
            }
            return decision
        }
        return reviewed
    }

    /// Reconstruct the verdict map from a session's statuses and user-review
    /// reasons (session import / crash recovery). Decisions never touched by
    /// review reconstruct as `approved` when accepted and are omitted
    /// otherwise (machine-withheld/skipped decisions are not verdicts).
    public static func verdicts(in session: NormalizationSessionDocument) -> [String: ReviewVerdict] {
        var verdicts: [String: ReviewVerdict] = [:]
        for decision in session.perAssetDecisions {
            if decision.skipReasons.contains(.userReviewRejected) {
                verdicts[decision.decisionID] = .rejected
            } else if decision.skipReasons.contains(.userReviewDeferred) {
                verdicts[decision.decisionID] = .deferred
            } else if decision.status == .accepted {
                verdicts[decision.decisionID] = .approved
            }
        }
        return verdicts
    }

    /// Reconstruct keyword edits (decisionID → edited text) from a session.
    public static func edits(in session: NormalizationSessionDocument) -> [String: String] {
        var edits: [String: String] = [:]
        for decision in session.perAssetDecisions where decision.candidateKind == .userEdited {
            if let flatKeyword = decision.flatKeyword {
                edits[decision.decisionID] = flatKeyword
            }
        }
        return edits
    }
}
