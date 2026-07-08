import Foundation

struct WrittenBannerContent: Equatable {
    var message: String
    var isWarning: Bool
}

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

    static func doneNeedsConfirmation(hasSession: Bool, restoredRecoveryDirty: Bool, exported: Bool) -> Bool {
        hasSession && restoredRecoveryDirty && !exported
    }

    static func writtenBanner(written: Int, failed: Int, cleanupRemoved: Int? = nil) -> WrittenBannerContent {
        if failed == 0 {
            let cleanupText: String
            if let cleanupRemoved, cleanupRemoved > 0 {
                cleanupText = " · \(cleanupRemoved) intermediate file\(cleanupRemoved == 1 ? "" : "s") removed"
            } else {
                cleanupText = ""
            }
            return WrittenBannerContent(
                message: "\(written) XMP sidecar\(written == 1 ? "" : "s") written · backups saved · validated\(cleanupText) — ready to import in Lightroom / Capture One",
                isWarning: false
            )
        }
        let total = written + failed
        return WrittenBannerContent(
            message: "\(written) of \(total) written - \(failed) failed; see the report below.",
            isWarning: true
        )
    }
}
