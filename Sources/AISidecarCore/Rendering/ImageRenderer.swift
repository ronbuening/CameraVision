import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// In-memory source render shared by whole-image and subject-isolation branches.
///
/// The full-resolution image is intentionally not cache-backed; it exists only
/// while a source image is being prepared so subject crops can preserve native
/// pixels without writing an intermediate TIFF artifact.
public struct PreparedSourceRender: @unchecked Sendable {
    public var fullImage: CIImage
    public var fullDimensions: PixelDimensions
    public var analysisImage: CIImage
    public var analysisDimensions: PixelDimensions
    public var appliedOrientation: AppliedOrientation
    public var recipeVersion: String

    public init(
        fullImage: CIImage,
        fullDimensions: PixelDimensions,
        analysisImage: CIImage,
        analysisDimensions: PixelDimensions,
        appliedOrientation: AppliedOrientation,
        recipeVersion: String
    ) {
        self.fullImage = fullImage
        self.fullDimensions = fullDimensions
        self.analysisImage = analysisImage
        self.analysisDimensions = analysisDimensions
        self.appliedOrientation = appliedOrientation
        self.recipeVersion = recipeVersion
    }
}

/// Output from rendering the whole-image model input for one source image.
public struct WholeImageRenderResult: Sendable, Equatable {
    public var wholeImage: DerivativeRecord

    public init(wholeImage: DerivativeRecord) {
        self.wholeImage = wholeImage
    }

    public var derivatives: [DerivativeRecord] {
        [wholeImage]
    }
}

/// Prepares source pixels and writes model-input derivatives.
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

    /// Decode and orient source pixels, keeping the native render in memory only.
    public func prepareSourceRender(source: SourceImage, profile: ModelInputProfile) throws -> PreparedSourceRender {
        let recipe = RenderRecipe(profile: profile)
        let loaded = try loadSourceImage(source)
        let orientation = try recipe.resolveOrientation(from: loaded.properties)
        let baked = recipe.bakeOrientation(loaded.image, orientation: orientation)
        let fullExtent = baked.extent.integral
        let fullDimensions = PixelDimensions(width: Int(fullExtent.width), height: Int(fullExtent.height))
        let analysisDimensions = try recipe.wholeImageDimensions(for: baked)
        let analysisImage = recipe.resized(baked, to: analysisDimensions)
        return PreparedSourceRender(
            fullImage: baked,
            fullDimensions: fullDimensions,
            analysisImage: analysisImage,
            analysisDimensions: analysisDimensions,
            appliedOrientation: orientation,
            recipeVersion: recipe.version
        )
    }

    /// Render or reuse the whole-image model-input derivative.
    public func renderWholeImage(
        source: SourceImage,
        profile: ModelInputProfile,
        debugDerivatives: Bool
    ) throws -> WholeImageRenderResult {
        let recipe = RenderRecipe(profile: profile)
        let wholeFormat = profile.preferredWholeImageFormat

        if var wholeRecord = try cache.cachedRecord(
            source: source,
            recipeVersion: recipe.version,
            role: .wholeImage,
            format: wholeFormat
        ) {
            if debugDerivatives {
                wholeRecord = try cache.copyDebugArtifact(record: wholeRecord, source: source)
            }
            return WholeImageRenderResult(wholeImage: wholeRecord)
        }

        let prepared = try prepareSourceRender(source: source, profile: profile)
        let wholeRecord = try renderWholeImageDerivative(
            source: source,
            prepared: prepared,
            profile: profile,
            debugDerivatives: debugDerivatives
        )
        return WholeImageRenderResult(wholeImage: wholeRecord)
    }

    /// Write or reuse the whole-image derivative from an already prepared source render.
    public func renderWholeImageDerivative(
        source: SourceImage,
        prepared: PreparedSourceRender,
        profile: ModelInputProfile,
        debugDerivatives: Bool
    ) throws -> DerivativeRecord {
        let format = profile.preferredWholeImageFormat
        if var cached = try cache.cachedRecord(
            source: source,
            recipeVersion: prepared.recipeVersion,
            role: .wholeImage,
            format: format
        ) {
            if debugDerivatives {
                cached = try cache.copyDebugArtifact(record: cached, source: source)
            }
            return cached
        }

        var wholeRecord = try cache.store(
            source: source,
            recipeVersion: prepared.recipeVersion,
            role: .wholeImage,
            format: format,
            dimensions: prepared.analysisDimensions,
            colorSpace: profile.colorSpace,
            appliedOrientation: prepared.appliedOrientation
        ) { destination in
            try writeJPEG(image: prepared.analysisImage, to: destination, quality: profile.jpegQuality)
        }

        if debugDerivatives {
            wholeRecord = try cache.copyDebugArtifact(record: wholeRecord, source: source)
        }
        return wholeRecord
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
