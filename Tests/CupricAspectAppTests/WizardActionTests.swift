import SwiftUI
import XCTest

@testable import CupricAspectApp

final class WizardActionTests: XCTestCase {
    func testQualityAssessmentSubtitleMatchesSelectedAction() {
        XCTAssertEqual(
            WizardAction.qualityAssessmentSubtitle(for: .analyze),
            "Verdicts are saved in the .ai.json sidecars; nothing touches XMP."
        )
        XCTAssertEqual(
            WizardAction.qualityAssessmentSubtitle(for: .write),
            "Verdicts are saved in the .ai.json sidecars. Enable Quality grading in Options to also write culling metadata."
        )
        XCTAssertEqual(
            WizardAction.qualityAssessmentSubtitle(for: .normalize),
            "Verdicts are saved in the .ai.json sidecars. Enable Quality grading in Options to write culling metadata after normalization."
        )
    }

    func testQualityAssessmentSubtitleUsesGenericCopyWithoutCardSelection() {
        let generic =
            "Ask the model to judge focus, exposure, composition, and more. The verdicts are saved in the sidecars for later; on XMP paths, enable Quality grading in Options to also write culling metadata — quality keywords, color labels, and Lightroom pick/reject flags."

        XCTAssertEqual(WizardAction.qualityAssessmentSubtitle(for: nil), generic)
        XCTAssertEqual(WizardAction.qualityAssessmentSubtitle(for: .apply), generic)
    }

    @MainActor
    func testAssessQualityBindingChangesOptionsWithoutChangingSelection() {
        let options = AnalysisOptions(environment: [:])
        var selection: WizardAction? = .write
        let view = Step2ActionView(
            selection: Binding(get: { selection }, set: { selection = $0 }),
            assessQuality: Binding(
                get: { options.assessQuality },
                set: { options.assessQuality = $0 }
            ),
            onApplySession: {}
        )

        view.assessQuality = true

        XCTAssertTrue(options.assessQuality)
        XCTAssertEqual(selection, .write)
        XCTAssertTrue(WizardAction.write.isAvailable)
    }
}
