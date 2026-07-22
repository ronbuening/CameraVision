import Foundation
import XCTest

@testable import AISidecarCore

final class CandidateSkipReasonBridgeTests: XCTestCase {
    private let expectedRawValues: Set<String> = [
        "below_confidence_threshold",
        "blocked_direct_conflict",
        "blocked_local_conflict_mass",
        "contains_hierarchy_separator",
        "coordinate_like_term",
        "direct_apply_flat_only",
        "direct_apply_withheld",
        "disabled_flat_export",
        "disabled_hierarchical_export",
        "duplicate",
        "empty_after_normalization",
        "gear_only_affinity",
        "global_backstop_threshold",
        "gps_only_evidence",
        "low_max_supporting_affinity",
        "low_support_mass",
        "low_supporting_neighbor_count",
        "requires_review",
        "session_context_conflict",
        "specific_tag_policy",
        "species_without_biological_genre",
        "unknown_session_context_flat_only",
        "unknown_session_context_rejected",
        "unmatched_vocabulary",
        "user_review_deferred",
        "user_review_rejected",
        "weak_local_agreement",
    ]

    func testReasonRawValuesMatchPinnedContract() {
        XCTAssertEqual(SkippedCandidateReason.allCases.count, 27)
        XCTAssertEqual(NormalizationCandidateSkipReason.allCases.count, 27)
        XCTAssertEqual(Set(SkippedCandidateReason.allCases.map(\.rawValue)), expectedRawValues)
        XCTAssertEqual(Set(NormalizationCandidateSkipReason.allCases.map(\.rawValue)), expectedRawValues)
    }

    func testEveryReasonRoundTripsThroughSharedBridge() {
        for reason in SkippedCandidateReason.allCases {
            let normalizationReason = CandidateSkipReasonBridge.normalizationReason(for: reason)
            XCTAssertEqual(normalizationReason.rawValue, reason.rawValue)
            XCTAssertEqual(CandidateSkipReasonBridge.skippedCandidateReason(for: normalizationReason), reason)
        }

        for reason in NormalizationCandidateSkipReason.allCases {
            let skippedReason = CandidateSkipReasonBridge.skippedCandidateReason(for: reason)
            XCTAssertEqual(skippedReason.rawValue, reason.rawValue)
            XCTAssertEqual(CandidateSkipReasonBridge.normalizationReason(for: skippedReason), reason)
        }
    }

    func testCorrespondingReasonsEncodeToIdenticalBytes() throws {
        let encoder = JSONEncoder()

        for reason in SkippedCandidateReason.allCases {
            let normalizationReason = CandidateSkipReasonBridge.normalizationReason(for: reason)
            XCTAssertEqual(try encoder.encode(reason), try encoder.encode(normalizationReason))
        }
    }
}
