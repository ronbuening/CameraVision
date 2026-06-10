import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// EXIF orientation value applied to rendered pixels.
public struct AppliedOrientation: Codable, Sendable, Equatable {
    public var exifValue: Int

    enum CodingKeys: String, CodingKey {
        case exifValue = "exif_value"
    }

    public init(exifValue: Int) {
        self.exifValue = exifValue
    }
}

/// Rendering policy that turns source pixels into cacheable Phase 1 derivatives.
public struct RenderRecipe: Sendable, Equatable {
    public var version: String
    public var profile: ModelInputProfile

    public init(profile: ModelInputProfile) {
        self.profile = profile
        // The profile name participates in the recipe version so cache keys
        // cannot collide when future profiles produce different dimensions.
        self.version = "render-v1-\(profile.name)"
    }

    /// Resolve Image I/O orientation metadata, defaulting absent orientation to 1.
    public func resolveOrientation(from properties: [CFString: Any]) throws -> AppliedOrientation {
        guard let rawValue = properties[kCGImagePropertyOrientation] else {
            return AppliedOrientation(exifValue: 1)
        }

        let value: Int?
        if let intValue = rawValue as? Int {
            value = intValue
        } else if let number = rawValue as? NSNumber {
            value = number.intValue
        } else {
            value = nil
        }

        guard let value, (1...8).contains(value) else {
            throw SidecarError(
                code: .orientationUnresolved,
                stage: .render,
                message: "Unable to resolve EXIF orientation value: \(rawValue).",
                recoverable: true
            )
        }
        return AppliedOrientation(exifValue: value)
    }

    /// Apply EXIF orientation and normalize the resulting extent to origin zero.
    public func bakeOrientation(_ image: CIImage, orientation: AppliedOrientation) -> CIImage {
        let oriented = image.oriented(forExifOrientation: Int32(orientation.exifValue))
        let extent = oriented.extent
        guard extent.origin != .zero else {
            return oriented
        }
        return oriented.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    /// Compute the whole-image derivative dimensions without upscaling.
    public func wholeImageDimensions(for image: CIImage) throws -> PixelDimensions {
        let extent = image.extent.integral
        return try profile.fittedDimensions(
            width: Int(extent.width),
            height: Int(extent.height),
            allowUpscale: false
        )
    }

    /// Resize while keeping the image extent origin normalized for encoders.
    public func resized(_ image: CIImage, to dimensions: PixelDimensions) -> CIImage {
        let extent = image.extent.integral
        let xScale = Double(dimensions.width) / Double(extent.width)
        let yScale = Double(dimensions.height) / Double(extent.height)
        return image
            .transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
