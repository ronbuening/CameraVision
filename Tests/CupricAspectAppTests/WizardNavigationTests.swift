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
}
