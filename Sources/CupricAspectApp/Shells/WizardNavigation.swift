import Foundation

/// Pure wizard step-graph decisions kept outside the view for focused tests.
@MainActor
enum WizardNavigation {
    static func isInFlight(_ phase: AnalysisRunModel.Phase) -> Bool {
        phase == .running || phase == .cancelling
    }

    /// Step 4 is only a valid Back destination while a run is in flight.
    static func backTarget(from step: Int, phase: AnalysisRunModel.Phase) -> Int? {
        switch step {
        case ...1:
            nil
        case 4:
            nil
        case 5 where !isInFlight(phase):
            3
        default:
            step - 1
        }
    }

    /// Re-running from Step 3 discards completed results or restored sessions.
    static func needsRerunConfirmation(
        phase: AnalysisRunModel.Phase,
        hasReview: Bool,
        hasNormalizationSession: Bool
    ) -> Bool {
        switch phase {
        case .finished, .cancelling:
            true
        default:
            hasReview || hasNormalizationSession
        }
    }
}
