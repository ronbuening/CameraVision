import Foundation

/// Target color spaces accepted by Phase 1 model-input profiles.
public enum ModelInputColorSpace: String, Codable, Sendable, Equatable {
    case sRGB = "sRGB"
}

/// Encoded derivative file formats produced by the Phase 1 renderer.
public enum DerivativeFormat: String, Codable, Sendable, Equatable {
    case jpeg
    case tiff
}

/// Rendered image roles persisted as derivative provenance.
public enum DerivativeRole: String, Codable, CaseIterable, Sendable, Equatable {
    case fullResolution = "full_resolution"
    case wholeImage = "whole_image"
    case subjectIsolated = "subject_isolated"
}

/// Integer pixel dimensions for rendered artifacts.
public struct PixelDimensions: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Model-facing image sizing and encoding policy.
///
/// Phase 1 ships one built-in profile. The full resolved profile is written to
/// sidecars so later model runs can be interpreted against the image the model
/// actually saw, not just a mutable profile name.
public struct ModelInputProfile: Codable, Sendable, Equatable {
    public var name: String
    public var maxLongEdge: Int
    public var maxTotalPixels: Int
    public var colorSpace: ModelInputColorSpace
    public var preferredWholeImageFormat: DerivativeFormat
    public var jpegQuality: Double
    public var preferredSubjectFormat: String
    public var matteRGB: [Int]
    public var allowUpscaleSubjectByDefault: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case maxLongEdge = "max_long_edge"
        case maxTotalPixels = "max_total_pixels"
        case colorSpace = "color_space"
        case preferredWholeImageFormat = "preferred_whole_image_format"
        case jpegQuality = "jpeg_quality"
        case preferredSubjectFormat = "preferred_subject_format"
        case matteRGB = "matte_rgb"
        case allowUpscaleSubjectByDefault = "allow_upscale_subject_by_default"
    }

    public init(
        name: String,
        maxLongEdge: Int,
        maxTotalPixels: Int,
        colorSpace: ModelInputColorSpace,
        preferredWholeImageFormat: DerivativeFormat,
        jpegQuality: Double,
        preferredSubjectFormat: String,
        matteRGB: [Int],
        allowUpscaleSubjectByDefault: Bool
    ) {
        self.name = name
        self.maxLongEdge = maxLongEdge
        self.maxTotalPixels = maxTotalPixels
        self.colorSpace = colorSpace
        self.preferredWholeImageFormat = preferredWholeImageFormat
        self.jpegQuality = jpegQuality
        self.preferredSubjectFormat = preferredSubjectFormat
        self.matteRGB = matteRGB
        self.allowUpscaleSubjectByDefault = allowUpscaleSubjectByDefault
    }

    public static let defaultProfile = ModelInputProfile(
        name: "gemma4-26b-default",
        maxLongEdge: 2_048,
        maxTotalPixels: 4_194_304,
        colorSpace: .sRGB,
        preferredWholeImageFormat: .jpeg,
        jpegQuality: 0.9,
        preferredSubjectFormat: "jpeg-neutral-matte",
        matteRGB: [128, 128, 128],
        allowUpscaleSubjectByDefault: false
    )

    /// Compute an aspect-preserving fit inside the profile's pixel ceilings.
    public func fittedDimensions(width: Int, height: Int, allowUpscale: Bool = false) throws -> PixelDimensions {
        guard width > 0, height > 0 else {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Invalid source dimensions \(width)x\(height).",
                recoverable: true
            )
        }

        let longEdgeScale = Double(maxLongEdge) / Double(max(width, height))
        let pixelScale = sqrt(Double(maxTotalPixels) / Double(width * height))
        let unconstrainedScale = min(longEdgeScale, pixelScale)
        let scale = allowUpscale ? unconstrainedScale : min(1.0, unconstrainedScale)
        let fittedWidth = max(1, Int(floor(Double(width) * scale)))
        let fittedHeight = max(1, Int(floor(Double(height) * scale)))
        return PixelDimensions(width: fittedWidth, height: fittedHeight)
    }
}

/// Resolves profile names accepted by Phase 1 configuration.
public enum ModelInputProfileRegistry {
    /// Return the built-in profile or fail configuration resolution.
    public static func resolve(name: String) throws -> ModelInputProfile {
        guard name == ModelInputProfile.defaultProfile.name else {
            throw SidecarError.configInvalid("Unknown model input profile: \(name)")
        }
        return .defaultProfile
    }
}
