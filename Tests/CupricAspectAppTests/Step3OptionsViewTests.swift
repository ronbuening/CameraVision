import AISidecarCore
import XCTest

@testable import CupricAspectApp

final class Step3OptionsViewTests: XCTestCase {
    func testQualityGradingVisibilityAndEnablementMatrix() {
        for action in WizardAction.allCases {
            for assessQuality in [false, true] {
                let availability = Step3OptionsView.qualityGradingAvailability(
                    action: action,
                    assessQuality: assessQuality
                )
                let shouldShow = action == .write || action == .normalize

                XCTAssertEqual(availability.isVisible, shouldShow, "action=\(action), assess=\(assessQuality)")
                XCTAssertEqual(
                    availability.controlsEnabled,
                    shouldShow && assessQuality,
                    "action=\(action), assess=\(assessQuality)"
                )
            }
        }
    }

    @MainActor
    func testEachQualityControlMapsOnlyItsOverrideField() {
        let options = AnalysisOptions(environment: [:])
        options.assessQuality = true
        options.qualityGradingEnabled = true
        options.qualityWriteRating = true
        options.qualityConflictPolicy = .refresh

        let overrides = effectiveOverrides(options: options, action: .write)

        XCTAssertEqual(overrides.enabled, true)
        XCTAssertEqual(overrides.writeRating, true)
        XCTAssertEqual(overrides.conflictPolicy, .refresh)
        XCTAssertNil(overrides.writeLabel)
        XCTAssertNil(overrides.writeUrgency)
        XCTAssertNil(overrides.writeFlag)
        XCTAssertNil(overrides.writeKeywords)
        XCTAssertNil(overrides.minimumConfidence)
    }

    @MainActor
    func testQualityBoolControlsMapToDistinctOverrideFields() {
        let options = AnalysisOptions(environment: [:])
        options.assessQuality = true
        options.qualityGradingEnabled = true
        options.qualityWriteRating = false

        var overrides = effectiveOverrides(options: options, action: .write)
        XCTAssertEqual(overrides.enabled, true)
        XCTAssertEqual(overrides.writeRating, false)

        options.qualityGradingEnabled = false
        options.qualityWriteRating = true

        overrides = effectiveOverrides(options: options, action: .write)
        XCTAssertEqual(overrides.enabled, false)
        XCTAssertEqual(overrides.writeRating, true)
    }

    @MainActor
    func testDisabledGroupForcesEffectiveGradingOffWithoutClearingRetainedChoices() {
        let options = AnalysisOptions(environment: [:])
        options.assessQuality = false
        options.qualityGradingEnabled = true
        options.qualityWriteRating = true
        options.qualityConflictPolicy = .overwrite

        let overrides = effectiveOverrides(options: options, action: .normalize)

        XCTAssertEqual(overrides.enabled, false)
        XCTAssertNil(overrides.writeRating)
        XCTAssertNil(overrides.conflictPolicy)
        XCTAssertTrue(options.qualityGradingEnabled)
        XCTAssertTrue(options.qualityWriteRating)
        XCTAssertEqual(options.qualityConflictPolicy, .overwrite)
    }

    @MainActor
    func testAnalyzeIdentityForcesGradingOffEvenWhenRetainedStateIsOn() throws {
        let options = AnalysisOptions(environment: [:])
        options.assessQuality = true
        options.qualityGradingEnabled = true
        options.qualityWriteRating = true
        options.qualityConflictPolicy = .overwrite

        let overrides = effectiveOverrides(options: options, action: .analyze)
        let configuration = try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(qualityGrading: overrides),
            environment: [:],
            defaultConfigPath: "\(NSTemporaryDirectory())cupric-step3-tests/\(UUID().uuidString)/missing.json"
        )

        XCTAssertEqual(overrides.enabled, false)
        XCTAssertNil(overrides.writeRating)
        XCTAssertNil(overrides.conflictPolicy)
        XCTAssertEqual(configuration.qualityGrading, .builtInDefaults)
    }

    @MainActor
    func testQualityScanModeMapsIntoRunConfiguration() throws {
        let missingConfig = "\(NSTemporaryDirectory())cupric-step3-tests/\(UUID().uuidString)/missing.json"
        let options = AnalysisOptions(environment: [:], defaultConfigPath: missingConfig)
        options.assessQuality = true
        options.qualityScanMode = .sequential

        let sequential = try options.buildConfiguration(recursive: false, outputDir: nil)
        XCTAssertEqual(sequential.taskProfile, .taggingWithQuality)
        XCTAssertEqual(sequential.qualityScanMode, .sequential)

        options.qualityScanMode = .combined
        let combined = try options.buildConfiguration(recursive: false, outputDir: nil)
        XCTAssertEqual(combined.qualityScanMode, .combined)
    }

    @MainActor
    func testQualityScanModeSeedsFromResolvedConfigDefaults() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cupric-step3-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let configPath = root.appendingPathComponent("config.json").path
        try Data(#"{"quality_assessment": true, "quality_scan_mode": "sequential"}"#.utf8)
            .write(to: URL(fileURLWithPath: configPath))

        let options = AnalysisOptions(environment: [:], defaultConfigPath: configPath)
        options.loadResolvedDefaults()

        XCTAssertTrue(options.assessQuality)
        XCTAssertEqual(options.qualityScanMode, .sequential)
    }

    func testQualityScanModeCopyIsPinned() {
        XCTAssertEqual(QualityScanMode.combined.wizardLabel, "Normal")
        XCTAssertEqual(QualityScanMode.sequential.wizardLabel, "High quality")
        XCTAssertEqual(
            Step3OptionsView.qualityScanFootnote,
            "Quality scan (when Step 2 assesses quality): Normal assesses in the same model call; "
                + "High quality runs a second pass per image — slower, "
                + "but keywords stay identical to a run without assessment."
        )
    }

    func testQualityGradingCopyIsPinnedToPlanWording() {
        XCTAssertEqual(ScalarConflictPolicy.preserve.wizardLabel, "Preserve — never replace existing values")
        XCTAssertEqual(ScalarConflictPolicy.refresh.wizardLabel, "Refresh — replace only values this app wrote before")
        XCTAssertEqual(ScalarConflictPolicy.overwrite.wizardLabel, "Overwrite — always replace")
        XCTAssertEqual(Step3OptionsView.ratingOptInRationale, "stars stay yours unless you opt in")
        XCTAssertEqual(
            Step3OptionsView.gradingRequiresAssessmentExplanation,
            "Assess image quality in Step 2 before this Wizard run can grade. "
                + "While assessment is off, grading stays off for this run — "
                + "even when your configuration enables it by default."
        )
    }

    @MainActor
    private func effectiveOverrides(
        options: AnalysisOptions,
        action: WizardAction
    ) -> QualityGradingConfigurationOverrides {
        let availability = Step3OptionsView.qualityGradingAvailability(
            action: action,
            assessQuality: options.assessQuality
        )
        return options.qualityGradingOverrides(controlsEnabled: availability.controlsEnabled)
    }
}
