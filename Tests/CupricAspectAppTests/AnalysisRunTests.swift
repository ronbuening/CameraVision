import AISidecarCore
import XCTest

@testable import CupricAspectApp

/// M2: options→configuration mapping and run-outcome reduction. The pipeline
/// itself is covered by Core's tests (CORE-1/2/3); these cover the GUI layer.
final class AnalysisRunTests: XCTestCase {
    @MainActor
    func testOptionsOverridesLandInResolvedConfiguration() throws {
        let options = AnalysisOptions()
        options.mode = .subject
        options.existing = .fail
        options.gps = .off
        options.concurrency = 3
        options.profile = "gemma4-26b-benchmark-1024"
        options.contextWindow = 4_096

        let configuration = try options.buildConfiguration(recursive: false, outputDir: "/tmp/out")

        XCTAssertEqual(configuration.mode, .subject)
        XCTAssertEqual(configuration.existing, .fail)
        XCTAssertEqual(configuration.gpsContext, .off)
        XCTAssertEqual(configuration.stageConcurrency, 3)
        XCTAssertEqual(configuration.profile, "gemma4-26b-benchmark-1024")
        XCTAssertEqual(configuration.modelContextWindow, 4_096)
        XCTAssertFalse(configuration.recursive)
        XCTAssertEqual(configuration.outputDir, "/tmp/out")
    }

    @MainActor
    func testModelOverrideResolvesForThisRunOnly() throws {
        let options = AnalysisOptions()
        options.modelOverride = "override:model"

        let configuration = try options.buildConfiguration(recursive: true, outputDir: nil)

        XCTAssertEqual(configuration.model, "override:model")
    }

    @MainActor
    func testNilModelOverrideFallsBackToResolvedConfigurationModel() throws {
        let expected = try ConfigurationResolver.resolve().model
        let options = AnalysisOptions()

        let configuration = try options.buildConfiguration(recursive: true, outputDir: nil)

        XCTAssertEqual(configuration.model, expected)
    }

    @MainActor
    func testLoadResolvedDefaultsPreservesRunScopedModelOverride() {
        let options = AnalysisOptions()
        options.modelOverride = "override:model"

        options.loadResolvedDefaults()

        XCTAssertEqual(options.modelOverride, "override:model")
    }

    @MainActor
    func testUserEditedOptionsSurviveRepeatedDefaultLoadsAndResetReseeds() throws {
        let configPath = try writeConfig(#"{ "existing": "fail", "stage_concurrency": 2 }"#)
        let options = AnalysisOptions(environment: [:], defaultConfigPath: configPath)

        options.loadResolvedDefaults()
        XCTAssertEqual(options.existing, .fail)
        XCTAssertEqual(options.concurrency, 2)

        options.existing = .overwrite
        options.concurrency = 4
        options.loadResolvedDefaults()

        XCTAssertEqual(options.existing, .overwrite)
        XCTAssertEqual(options.concurrency, 4)

        options.resetToResolvedDefaults()

        XCTAssertEqual(options.existing, .fail)
        XCTAssertEqual(options.concurrency, 2)
    }

    @MainActor
    func testRepeatedDefaultLoadsStillRefreshDisplayConfiguration() throws {
        let configPath = try writeConfig(#"{ "model": "first:model" }"#)
        let options = AnalysisOptions(environment: [:], defaultConfigPath: configPath)

        options.loadResolvedDefaults()
        XCTAssertEqual(options.resolvedModel, "first:model")
        options.existing = .overwrite

        try #"{ "model": "second:model" }"#.data(using: .utf8)!.write(to: URL(fileURLWithPath: configPath))
        options.loadResolvedDefaults()

        XCTAssertEqual(options.resolvedModel, "second:model")
        XCTAssertEqual(options.existing, .overwrite)
    }

    @MainActor
    func testXMPConflictPolicyDefaultMatchesCoreApplySessionDefault() {
        let options = AnalysisOptions()

        XCTAssertEqual(
            options.xmpConflictPolicy,
            ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy
        )
    }

    @MainActor
    func testLoadResolvedDefaultsSeedsXMPConflictPolicyFromConfig() throws {
        let configPath = try writeConfig(#"{ "xmp_conflict_policy": "merge" }"#)
        let options = AnalysisOptions(environment: [:], defaultConfigPath: configPath)

        options.loadResolvedDefaults()

        XCTAssertEqual(options.xmpConflictPolicy, .merge)
    }

    @MainActor
    func testLoadResolvedDefaultsFallsBackToCoreXMPConflictPolicyDefault() {
        let options = AnalysisOptions(environment: [:], defaultConfigPath: missingConfigPath())

        options.loadResolvedDefaults()

        XCTAssertEqual(options.xmpConflictPolicy, .backupAndMerge)
    }

    func testSecondsPerImageUsesProcessedCount() {
        XCTAssertEqual(AnalysisRunModel.secondsPerImage(elapsed: 60, done: 0), 0)
        XCTAssertEqual(AnalysisRunModel.secondsPerImage(elapsed: 0.25, done: 10), 0)
        XCTAssertEqual(AnalysisRunModel.secondsPerImage(elapsed: 60, done: 30), 2.0, accuracy: 0.001)
        XCTAssertEqual(AnalysisRunModel.secondsPerImage(elapsed: 60, done: 20), 3.0, accuracy: 0.001)
    }

    @MainActor
    func testSecondsPerImageExcludesInFlightImage() {
        let model = AnalysisRunModel()
        let start = Date(timeIntervalSinceReferenceDate: 0)

        // First image still processing (30s elapsed, none completed): no rate.
        model.applyTimingForTesting(done: 0, startedAt: start, lastCompletedAt: nil)
        XCTAssertEqual(model.secondsPerImage, 0)

        // Two images done at t=20s, but the third has been running for a
        // further 40s (now = t=60s). The average must reflect only the two
        // completed images (10 s/img), not the in-flight one.
        model.applyTimingForTesting(
            done: 2,
            startedAt: start,
            lastCompletedAt: start.addingTimeInterval(20)
        )
        XCTAssertEqual(model.secondsPerImage, 10.0, accuracy: 0.001)
    }

    @MainActor
    func testProgressFractionClampsToOneAndReconcilesStaleTotal() {
        let model = AnalysisRunModel()

        model.applyProgressForTesting(done: 12, total: 10)

        XCTAssertEqual(model.progressFraction, 1.0)
        XCTAssertEqual(model.total, 12)
    }

    @MainActor
    func testProgressFractionIsZeroWhenNoProgressExists() {
        let model = AnalysisRunModel()

        XCTAssertEqual(model.progressFraction, 0)
    }

    func testOutcomeReductionCountsStatusesAndAggregatesErrorCodes() {
        func record(_ status: ProgressStatus, codes: [SidecarErrorCode] = []) -> ProgressRecord {
            ProgressRecord(
                timestamp: Date(timeIntervalSince1970: 0),
                sourcePath: "/x/a.jpg",
                relativePath: "a.jpg",
                sidecarPath: nil,
                status: status,
                errors: codes.map {
                    SidecarError(code: $0, stage: .scan, message: "m", recoverable: true)
                },
                durationMs: 0
            )
        }

        let outcome = AnalysisRunModel.outcome(
            from: [
                record(.written), record(.written),
                record(.skippedExisting),
                record(.failed, codes: [.unsupportedFormat]),
                record(.failed, codes: [.unsupportedFormat]),
                record(.failed, codes: [.validationFailed]),
            ],
            interrupted: true
        )

        XCTAssertEqual(outcome.written, 2)
        XCTAssertEqual(outcome.skipped, 1)
        XCTAssertEqual(outcome.failed, 3)
        XCTAssertTrue(outcome.interrupted)
        XCTAssertEqual(outcome.errorSummaries, ["E_UNSUPPORTED_FORMAT × 2", "E_VALIDATION_FAILED × 1"])
    }

    private func missingConfigPath() -> String {
        "\(NSTemporaryDirectory())cupric-options-tests/\(UUID().uuidString)/missing-config.json"
    }

    private func writeConfig(_ contents: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cupric-options-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        try contents.data(using: .utf8)!.write(to: file)
        return file.path
    }
}
