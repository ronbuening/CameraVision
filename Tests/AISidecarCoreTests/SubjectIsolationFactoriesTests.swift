import CoreImage
import XCTest

@testable import AISidecarCore

final class SubjectIsolationFactoriesTests: XCTestCase {
    func testDefaultProviderUsesAppleVisionOnSupportedSystems() {
        let provider: any ForegroundMaskProvider = .makeDefault()

        XCTAssertTrue(provider is AppleVisionForegroundMaskProvider)
    }

    func testUnavailableProviderPreservesCompatibilityError() async {
        let provider = UnavailableForegroundMaskProvider()

        do {
            _ = try await provider.foregroundMasks(
                in: CIImage(color: .black),
                dimensions: PixelDimensions(width: 1, height: 1)
            )
            XCTFail("Expected the unavailable provider to throw.")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .subjectIsolationFailed)
            XCTAssertEqual(error.stage, .isolate)
            XCTAssertEqual(error.message, "Apple Vision foreground masking requires macOS 15 or newer.")
            XCTAssertTrue(error.recoverable)
        } catch {
            XCTFail("Expected SidecarError, received \(error).")
        }
    }

    func testFailurePreservesIsolationErrorAndBuildsExactRecord() {
        let originalError = SidecarError(
            code: .subjectIsolationNoForeground,
            stage: .isolate,
            message: "Injected isolation error.",
            recoverable: false
        )
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.subjectCropMarginFraction = 0.17
        configuration.subjectMergeDominanceThreshold = 0.63
        var profile = ModelInputProfile.defaultProfile
        profile.matteRGB = [1, 2, 3]

        let failure = SubjectIsolationFailure.make(
            from: originalError,
            prepared: preparedRender(),
            configuration: configuration,
            profile: profile
        )

        XCTAssertEqual(failure.error, originalError)
        XCTAssertEqual(failure.record.status, .failed)
        XCTAssertEqual(failure.record.instanceCount, 0)
        XCTAssertEqual(failure.record.selectedInstanceIndices, [])
        XCTAssertFalse(failure.record.mergedInstances)
        XCTAssertEqual(failure.record.instances, [])
        XCTAssertEqual(failure.record.analysisResolution, PixelDimensions(width: 20, height: 10))
        XCTAssertEqual(failure.record.fullResolution, PixelDimensions(width: 100, height: 80))
        XCTAssertEqual(failure.record.scaleFactors, SubjectIsolationScaleFactors(x: 5, y: 8))
        XCTAssertNil(failure.record.selectedBoundingBox)
        XCTAssertNil(failure.record.cropBoundingBox)
        XCTAssertEqual(failure.record.cropMarginFraction, 0.17)
        XCTAssertEqual(failure.record.cropMarginPixels, 0)
        XCTAssertEqual(failure.record.mergeDominanceThreshold, 0.63)
        XCTAssertNil(failure.record.selectedToUnionAreaRatio)
        XCTAssertEqual(failure.record.matteRGB, [1, 2, 3])
        XCTAssertNil(failure.record.finalDimensions)
        XCTAssertFalse(failure.record.upscaled)
    }

    func testFailureWrapsNonIsolationErrorUsingLocalizedDescription() {
        let originalError = SidecarError(
            code: .renderFailed,
            stage: .render,
            message: "Injected render error.",
            recoverable: false
        )

        let failure = SubjectIsolationFailure.make(
            from: originalError,
            prepared: preparedRender(),
            configuration: .builtInDefaults,
            profile: .defaultProfile
        )

        XCTAssertEqual(
            failure.error,
            SidecarError(
                code: .subjectIsolationFailed,
                stage: .isolate,
                message: "Unable to isolate subject: E_RENDER_FAILED: Injected render error.",
                recoverable: true
            )
        )
    }

    private func preparedRender() -> PreparedSourceRender {
        PreparedSourceRender(
            fullImage: CIImage(color: .black),
            fullDimensions: PixelDimensions(width: 100, height: 80),
            analysisImage: CIImage(color: .black),
            analysisDimensions: PixelDimensions(width: 20, height: 10),
            appliedOrientation: AppliedOrientation(exifValue: 1),
            recipeVersion: "test-recipe"
        )
    }
}
