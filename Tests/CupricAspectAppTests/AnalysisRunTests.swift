import XCTest
import AISidecarCore
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

        let configuration = try options.buildConfiguration(recursive: false, outputDir: "/tmp/out")

        XCTAssertEqual(configuration.mode, .subject)
        XCTAssertEqual(configuration.existing, .fail)
        XCTAssertEqual(configuration.gpsContext, .off)
        XCTAssertEqual(configuration.stageConcurrency, 3)
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
}
