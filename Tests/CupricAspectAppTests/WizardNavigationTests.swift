import XCTest
@testable import CupricAspectApp

/// R1-1: wizard step graph and re-run confirmation decisions.
@MainActor
final class WizardNavigationTests: XCTestCase {
    func testBackFromStep5SkipsWorkingWhenRunIsNotInFlight() {
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .finished(RunOutcome())), 3)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .idle), 3)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .failed(message: "x")), 3)
    }

    func testBackFromStep5DuringLiveRunStaysConventional() {
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .running), 4)
        XCTAssertEqual(WizardNavigation.backTarget(from: 5, phase: .cancelling), 4)
    }

    func testBackIsUnavailableOnStep1AndStep4AndDecrementsElsewhere() {
        XCTAssertNil(WizardNavigation.backTarget(from: 1, phase: .idle))
        XCTAssertNil(WizardNavigation.backTarget(from: 4, phase: .running))
        XCTAssertNil(WizardNavigation.backTarget(from: 4, phase: .finished(RunOutcome())))
        XCTAssertEqual(WizardNavigation.backTarget(from: 3, phase: .idle), 2)
        XCTAssertEqual(WizardNavigation.backTarget(from: 2, phase: .idle), 1)
    }

    func testRerunConfirmationRequiredOnlyWhenDataWouldBeLost() {
        XCTAssertTrue(WizardNavigation.needsRerunConfirmation(
            phase: .finished(RunOutcome()),
            hasReview: false,
            hasNormalizationSession: false
        ))
        XCTAssertTrue(WizardNavigation.needsRerunConfirmation(
            phase: .idle,
            hasReview: true,
            hasNormalizationSession: false
        ))
        XCTAssertTrue(WizardNavigation.needsRerunConfirmation(
            phase: .idle,
            hasReview: false,
            hasNormalizationSession: true
        ))
        XCTAssertFalse(WizardNavigation.needsRerunConfirmation(
            phase: .idle,
            hasReview: false,
            hasNormalizationSession: false
        ))
    }

    func testDoneConfirmsOnlyForUnsavedRestoredReviews() {
        XCTAssertTrue(WizardNavigation.doneNeedsConfirmation(
            hasSession: true,
            restoredRecoveryDirty: true,
            exported: false
        ))
        XCTAssertFalse(WizardNavigation.doneNeedsConfirmation(
            hasSession: true,
            restoredRecoveryDirty: true,
            exported: true
        ))
        XCTAssertFalse(WizardNavigation.doneNeedsConfirmation(
            hasSession: true,
            restoredRecoveryDirty: false,
            exported: false
        ))
        XCTAssertFalse(WizardNavigation.doneNeedsConfirmation(
            hasSession: false,
            restoredRecoveryDirty: true,
            exported: false
        ))
    }

    func testWrittenBannerCountsOnlySuccessfulTargetsAndWarnsOnFailures() {
        let clean = WizardNavigation.writtenBanner(written: 4, failed: 0)
        XCTAssertFalse(clean.isWarning)
        XCTAssertTrue(clean.message.hasPrefix("4 XMP sidecars written"))

        let singular = WizardNavigation.writtenBanner(written: 1, failed: 0)
        XCTAssertFalse(singular.isWarning)
        XCTAssertTrue(singular.message.hasPrefix("1 XMP sidecar written"))

        let mixed = WizardNavigation.writtenBanner(written: 3, failed: 2)
        XCTAssertTrue(mixed.isWarning)
        XCTAssertEqual(mixed.message, "3 of 5 written - 2 failed; see the report below.")

        let allFailed = WizardNavigation.writtenBanner(written: 0, failed: 5)
        XCTAssertTrue(allFailed.isWarning)
        XCTAssertEqual(allFailed.message, "0 of 5 written - 5 failed; see the report below.")
    }
}
