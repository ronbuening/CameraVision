import CoreImage
import Foundation

extension ForegroundMaskProvider where Self == AppleVisionForegroundMaskProvider {
    /// Select the production foreground-mask implementation for the running OS.
    static func makeDefault() -> any ForegroundMaskProvider {
        if #available(macOS 15.0, *) {
            AppleVisionForegroundMaskProvider()
        } else {
            UnavailableForegroundMaskProvider()
        }
    }
}

/// Shared failed-attempt payload used when a mask provider throws.
struct SubjectIsolationFailure: Sendable, Equatable {
    var record: SubjectIsolationRecord
    var error: SidecarError

    static func make(
        from error: Error,
        prepared: PreparedSourceRender,
        configuration: ResolvedRunConfiguration,
        profile: ModelInputProfile
    ) -> SubjectIsolationFailure {
        let isolationError: SidecarError
        if let sidecarError = error as? SidecarError, sidecarError.stage == .isolate {
            isolationError = sidecarError
        } else {
            isolationError = SidecarError(
                code: .subjectIsolationFailed,
                stage: .isolate,
                message: "Unable to isolate subject: \(error.localizedDescription)",
                recoverable: true
            )
        }

        let analysisDimensions = prepared.analysisDimensions
        let fullDimensions = prepared.fullDimensions
        return SubjectIsolationFailure(
            record: SubjectIsolationRecord(
                status: .failed,
                instanceCount: 0,
                selectedInstanceIndices: [],
                mergedInstances: false,
                instances: [],
                analysisResolution: analysisDimensions,
                fullResolution: fullDimensions,
                scaleFactors: SubjectIsolationScaleFactors(
                    x: Double(fullDimensions.width) / Double(analysisDimensions.width),
                    y: Double(fullDimensions.height) / Double(analysisDimensions.height)
                ),
                selectedBoundingBox: nil,
                cropBoundingBox: nil,
                cropMarginFraction: configuration.subjectCropMarginFraction,
                cropMarginPixels: 0,
                mergeDominanceThreshold: configuration.subjectMergeDominanceThreshold,
                selectedToUnionAreaRatio: nil,
                matteRGB: profile.matteRGB,
                finalDimensions: nil,
                upscaled: false
            ),
            error: isolationError
        )
    }
}

struct UnavailableForegroundMaskProvider: ForegroundMaskProvider {
    func foregroundMasks(in _: CIImage, dimensions _: PixelDimensions) async throws -> ForegroundMaskResult {
        throw SidecarError(
            code: .subjectIsolationFailed,
            stage: .isolate,
            message: "Apple Vision foreground masking requires macOS 15 or newer.",
            recoverable: true
        )
    }
}
