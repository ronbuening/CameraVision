import Foundation
import XCTest

@testable import AISidecarCore

final class CandidateSkipReasonParityTests: XCTestCase {
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

    func testSkipReasonNamesShareOneEnum() {
        XCTAssertTrue(
            SkippedCandidateReason.self == NormalizationCandidateSkipReason.self,
            "the Phase 2 and Phase 3 skip-reason names must stay one shared enum"
        )
    }

    func testReasonRawValuesMatchPinnedContract() {
        XCTAssertEqual(NormalizationCandidateSkipReason.allCases.count, 27)
        XCTAssertEqual(Set(NormalizationCandidateSkipReason.allCases.map(\.rawValue)), expectedRawValues)
    }

    func testReasonsEncodeAsPinnedRawStrings() throws {
        let encoder = JSONEncoder()

        for reason in NormalizationCandidateSkipReason.allCases {
            XCTAssertEqual(try encoder.encode([reason]), Data("[\"\(reason.rawValue)\"]".utf8))
        }
    }
}
