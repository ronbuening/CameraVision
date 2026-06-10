import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Output from rendering the whole-image derivative set for one source image.
public struct WholeImageRenderResult: Sendable, Equatable {
    public var fullResolution: DerivativeRecord
    public var wholeImage: DerivativeRecord

    public init(fullResolution: DerivativeRecord, wholeImage: DerivativeRecord) {
        self.fullResolution = fullResolution
        self.wholeImage = wholeImage
    }

    public var derivatives: [DerivativeRecord] {
        [fullResolution, wholeImage]
    }
}

/// Renders full-resolution and model-profile whole-image derivatives.
public struct ImageRenderer {
    private let cache: DerivativeCache
    private let context: CIContext

    public init(cache: DerivativeCache) {
        self.cache = cache
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            self.context = CIContext(options: [
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
        } else {
            self.context = CIContext()
        }
    }

    /// Render or reuse the full-resolution and whole-image derivatives.
    public func renderWholeImageSet(
        source: SourceImage,
        profile: ModelInputProfile,
        debugDerivatives: Bool
    ) throws -> WholeImageRenderResult {
        let recipe = RenderRecipe(profile: profile)
        let fullFormat = DerivativeFormat.tiff
        let wholeFormat = profile.preferredWholeImageFormat

        // The derivative set is consumed together by subject isolation;
        // if either role is absent or corrupt, regenerate both from the source.
        if var fullRecord = try cache.cachedRecord(
            source: source,
            recipeVersion: recipe.version,
            role: .fullResolution,
            format: fullFormat
        ), var wholeRecord = try cache.cachedRecord(
            source: source,
            recipeVersion: recipe.version,
            role: .wholeImage,
            format: wholeFormat
        ) {
            if debugDerivatives {
                fullRecord = try cache.copyDebugArtifact(record: fullRecord, source: source)
                wholeRecord = try cache.copyDebugArtifact(record: wholeRecord, source: source)
            }
            return WholeImageRenderResult(fullResolution: fullRecord, wholeImage: wholeRecord)
        }

        let loaded = try loadSourceImage(source)
        let orientation = try recipe.resolveOrientation(from: loaded.properties)
        let baked = recipe.bakeOrientation(loaded.image, orientation: orientation)
        let fullDimensions = PixelDimensions(width: Int(baked.extent.width), height: Int(baked.extent.height))
        let wholeDimensions = try recipe.wholeImageDimensions(for: baked)
        let wholeImage = recipe.resized(baked, to: wholeDimensions)

        var fullRecord = try cache.store(
            source: source,
            recipeVersion: recipe.version,
            role: .fullResolution,
            format: fullFormat,
            dimensions: fullDimensions,
            colorSpace: profile.colorSpace,
            appliedOrientation: orientation
        ) { destination in
            try writeTIFF(image: baked, to: destination)
        }

        var wholeRecord = try cache.store(
            source: source,
            recipeVersion: recipe.version,
            role: .wholeImage,
            format: wholeFormat,
            dimensions: wholeDimensions,
            colorSpace: profile.colorSpace,
            appliedOrientation: orientation
        ) { destination in
            try writeJPEG(image: wholeImage, to: destination, quality: profile.jpegQuality)
        }

        if debugDerivatives {
            fullRecord = try cache.copyDebugArtifact(record: fullRecord, source: source)
            wholeRecord = try cache.copyDebugArtifact(record: wholeRecord, source: source)
        }
        return WholeImageRenderResult(fullResolution: fullRecord, wholeImage: wholeRecord)
    }

    private func loadSourceImage(_ source: SourceImage) throws -> LoadedImage {
        let url = URL(fileURLWithPath: source.path)
        let properties = try imageProperties(at: url)
        if source.detectedType.isRAW {
            guard let filter = CIRAWFilter(imageURL: url), let outputImage = filter.outputImage else {
                throw SidecarError(
                    code: .decodeFailed,
                    stage: .render,
                    message: "Unable to decode RAW image: \(source.path)",
                    recoverable: true
                )
            }
            return LoadedImage(image: outputImage, properties: properties)
        }

        // Orientation is applied explicitly in RenderRecipe so every output
        // records the same EXIF value that was baked into pixels.
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: false]) else {
            throw SidecarError(
                code: .decodeFailed,
                stage: .render,
                message: "Unable to decode image: \(source.path)",
                recoverable: true
            )
        }
        return LoadedImage(image: image, properties: properties)
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw SidecarError(
                code: .decodeFailed,
                stage: .render,
                message: "Unable to open image metadata: \(url.path)",
                recoverable: true
            )
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties ?? [:]
    }

    private func writeTIFF(image: CIImage, to destination: URL) throws {
        do {
            try writeImageIO(image: image, to: destination, typeIdentifier: UTType.tiff.identifier, properties: [:])
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to encode TIFF derivative \(destination.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func writeJPEG(image: CIImage, to destination: URL, quality: Double) throws {
        do {
            try writeImageIO(
                image: image,
                to: destination,
                typeIdentifier: UTType.jpeg.identifier,
                properties: [kCGImageDestinationLossyCompressionQuality: quality]
            )
        } catch {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to encode JPEG derivative \(destination.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func writeImageIO(
        image: CIImage,
        to destination: URL,
        typeIdentifier: String,
        properties: [CFString: Any]
    ) throws {
        let colorSpace = try Self.sRGBColorSpace()
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to create encoded image pixels for \(destination.path).",
                recoverable: true
            )
        }
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to create image destination \(destination.path).",
                recoverable: true
            )
        }

        CGImageDestinationAddImage(imageDestination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to finalize image destination \(destination.path).",
                recoverable: true
            )
        }
    }

    private static func sRGBColorSpace() throws -> CGColorSpace {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw SidecarError(
                code: .renderFailed,
                stage: .render,
                message: "Unable to create sRGB color space.",
                recoverable: true
            )
        }
        return colorSpace
    }
}

private struct LoadedImage {
    var image: CIImage
    var properties: [CFString: Any]
}

private extension SupportedImageType {
    var isRAW: Bool {
        switch self {
        case .nef, .nrw, .cr3, .cr2, .arw, .raf, .orf, .rw2, .dng:
            return true
        case .jpg, .jpeg, .tif, .tiff, .heic, .png:
            return false
        }
    }
}
