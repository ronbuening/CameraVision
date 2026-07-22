import Foundation

func assignDecisionIDs(_ decisions: inout [PerAssetNormalizationDecision]) {
    for index in decisions.indices {
        decisions[index].decisionID = String(format: "decision-%06d", index + 1)
    }
}
