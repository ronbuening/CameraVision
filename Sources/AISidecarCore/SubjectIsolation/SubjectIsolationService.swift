import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs the Phase 1 subject-isolation chain without caching native renders.
public struct SubjectIsolationService {
    private let cache: DerivativeCache
    private let maskProvider: any ForegroundMaskProvider
    private let context: CIContext

    public init(cache: DerivativeCache, maskProvider: any ForegroundMaskProvider) {
        self.cache = cache
        self.maskProvider = maskProvider
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            self.context = CIContext(options: [
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
        } else {
            self.context = CIContext()
        }
    }

    /// Create or reuse a subject-isolated derivative and return sidecar provenance.
    public func isolate(
        source: SourceImage,
        prepared: PreparedSourceRender,
        profile: ModelInputProfile,
        configuration: ResolvedRunConfiguration
    ) async throws -> SubjectIsolationResult {
        let analysisDimensions = prepared.analysisDimensions
        let fullDimensions = prepared.fullDimensions
        let scaleFactors = SubjectIsolationScaleFactors(
            x: Double(fullDimensions.width) / Double(analysisDimensions.width),
            y: Double(fullDimensions.height) / Double(analysisDimensions.height)
        )
        let matteRGB = normalizedMatteRGB(profile.matteRGB)
        // Vision runs at analysis resolution; all crop and matte work below maps
        // back to the in-memory native render to preserve subject pixels.
        let foreground = try await maskProvider.foregroundMasks(
            in: prepared.analysisImage,
            dimensions: analysisDimensions
        )
        let instances = foreground.instances.map(\.record).sorted { $0.index < $1.index }

        guard let decision = InstanceSelectionPolicy(
            mergeDominanceThreshold: configuration.subjectMergeDominanceThreshold
        ).select(from: instances) else {
            let error = SidecarError(
                code: .subjectIsolationNoForeground,
                stage: .isolate,
                message: "Apple Vision did not find a foreground subject.",
                recoverable: true
            )
            return SubjectIsolationResult(
                record: SubjectIsolationRecord(
                    status: .noForeground,
                    instanceCount: 0,
                    selectedInstanceIndices: [],
                    mergedInstances: false,
                    instances: [],
                    analysisResolution: analysisDimensions,
                    fullResolution: fullDimensions,
                    scaleFactors: scaleFactors,
                    selectedBoundingBox: nil,
                    cropBoundingBox: nil,
                    cropMarginFraction: configuration.subjectCropMarginFraction,
                    cropMarginPixels: 0,
                    mergeDominanceThreshold: configuration.subjectMergeDominanceThreshold,
                    selectedToUnionAreaRatio: nil,
                    matteRGB: matteRGB,
                    finalDimensions: nil,
                    upscaled: false
                ),
                derivative: nil,
                error: error
            )
        }

        let selectedFullBox = decision.selectedBoundingBox.scaled(to: fullDimensions)
        let marginPixels = Int(ceil(
            Double(max(selectedFullBox.width, selectedFullBox.height)) * configuration.subjectCropMarginFraction
        ))
        let cropBox = selectedFullBox.expanded(by: marginPixels, within: fullDimensions)
        let nativeDimensions = PixelDimensions(width: cropBox.width, height: cropBox.height)
        let finalDimensions = try profile.fittedDimensions(
            width: cropBox.width,
            height: cropBox.height,
            allowUpscale: profile.allowUpscaleSubjectByDefault
        )
        let upscaled = finalDimensions.width > cropBox.width || finalDimensions.height > cropBox.height
        let subjectRecipeVersion = self.subjectRecipeVersion(
            renderRecipeVersion: prepared.recipeVersion,
            configuration: configuration,
            matteRGB: matteRGB
        )
        let format = DerivativeFormat.jpeg
        let derivative = try subjectDerivative(
            source: source,
            prepared: prepared,
            profile: profile,
            recipeVersion: subjectRecipeVersion,
            format: format,
            finalDimensions: finalDimensions,
            cropBox: cropBox,
            fullDimensions: fullDimensions,
            selectedMasks: foreground.instances.filter { decision.selectedInstanceIndices.contains($0.record.index) },
            matteRGB: matteRGB,
            debugDerivatives: configuration.debugDerivatives
        )

        let record = SubjectIsolationRecord(
            status: .success,
            instanceCount: instances.count,
            selectedInstanceIndices: decision.selectedInstanceIndices,
            mergedInstances: decision.mergedInstances,
            instances: instances,
            analysisResolution: analysisDimensions,
            fullResolution: fullDimensions,
            scaleFactors: scaleFactors,
            selectedBoundingBox: decision.selectedBoundingBox,
            cropBoundingBox: cropBox,
            cropMarginFraction: configuration.subjectCropMarginFraction,
            cropMarginPixels: marginPixels,
            mergeDominanceThreshold: configuration.subjectMergeDominanceThreshold,
            selectedToUnionAreaRatio: decision.selectedToUnionAreaRatio,
            matteRGB: matteRGB,
            finalDimensions: nativeDimensions == finalDimensions ? nativeDimensions : finalDimensions,
            upscaled: upscaled
        )
        return SubjectIsolationResult(record: record, derivative: derivative, error: nil)
    }

    private func subjectDerivative(
        source: SourceImage,
        prepared: PreparedSourceRender,
        profile: ModelInputProfile,
        recipeVersion: String,
        format: DerivativeFormat,
        finalDimensions: PixelDimensions,
        cropBox: PixelBoundingBox,
        fullDimensions: PixelDimensions,
        selectedMasks: [ForegroundInstanceMask],
        matteRGB: [Int],
        debugDerivatives: Bool
    ) throws -> DerivativeRecord {
        if var cached = try cache.cachedRecord(
            source: source,
            recipeVersion: recipeVersion,
            role: .subjectIsolated,
            format: format
        ) {
            if debugDerivatives {
                cached = try cache.copyDebugArtifact(record: cached, source: source)
            }
            return cached
        }

        let composited = try subjectComposite(
            fullImage: prepared.fullImage,
            fullDimensions: fullDimensions,
            selectedMasks: selectedMasks,
            cropBox: cropBox,
            matteRGB: matteRGB
        )
        let recipe = RenderRecipe(profile: profile)
        let finalImage = recipe.resized(composited, to: finalDimensions)
        var record = try cache.store(
            source: source,
            recipeVersion: recipeVersion,
            role: .subjectIsolated,
            format: format,
            dimensions: finalDimensions,
            colorSpace: profile.colorSpace,
            appliedOrientation: prepared.appliedOrientation
        ) { destination in
            try writeJPEG(image: finalImage, to: destination, quality: profile.jpegQuality)
        }

        if debugDerivatives {
            record = try cache.copyDebugArtifact(record: record, source: source)
        }
        return record
    }

    private func subjectRecipeVersion(
        renderRecipeVersion: String,
        configuration: ResolvedRunConfiguration,
        matteRGB: [Int]
    ) -> String {
        // Subject crops depend on isolation policy as well as render recipe;
        // including both prevents stale cache hits after margin/merge changes.
        [
            renderRecipeVersion,
            "subject-v2",
            "margin-\(stableDecimal(configuration.subjectCropMarginFraction))",
            "merge-\(stableDecimal(configuration.subjectMergeDominanceThreshold))",
            "matte-\(matteRGB.map(String.init).joined(separator: "-"))"
        ].joined(separator: "-")
    }

    private func stableDecimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func subjectComposite(
        fullImage: CIImage,
        fullDimensions: PixelDimensions,
        selectedMasks: [ForegroundInstanceMask],
        cropBox: PixelBoundingBox,
        matteRGB: [Int]
    ) throws -> CIImage {
        guard !selectedMasks.isEmpty else {
            throw MaskGeometry.isolationFailed("No selected foreground masks were available for compositing.")
        }

        let analysisBounds = selectedMasks[0].maskImage.extent
        let unionMask = selectedMasks.dropFirst().reduce(selectedMasks[0].maskImage) { partial, instance in
            instance.maskImage.applyingFilter(
                "CIMaximumCompositing",
                parameters: [kCIInputBackgroundImageKey: partial]
            )
        }
        let scaleX = Double(fullDimensions.width) / Double(analysisBounds.width)
        let scaleY = Double(fullDimensions.height) / Double(analysisBounds.height)
        let fullMask = unionMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(x: 0, y: 0, width: fullDimensions.width, height: fullDimensions.height))
        let cropRect = cropBox.rect
        let croppedFull = fullImage.cropped(to: cropRect)
        let croppedMask = fullMask.cropped(to: cropRect)
        let matte = CIImage(
            color: CIColor(
                red: Double(matteRGB[0]) / 255.0,
                green: Double(matteRGB[1]) / 255.0,
                blue: Double(matteRGB[2]) / 255.0,
                alpha: 1
            )
        ).cropped(to: cropRect)
        let blended = croppedFull.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: matte,
                kCIInputMaskImageKey: croppedMask
            ]
        )
        return blended.transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
    }

    private func normalizedMatteRGB(_ values: [Int]) -> [Int] {
        guard values.count == 3 else {
            return [128, 128, 128]
        }
        return values.map { min(255, max(0, $0)) }
    }

    private func writeJPEG(image: CIImage, to destination: URL, quality: Double) throws {
        let colorSpace = try sRGBColorSpace()
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw MaskGeometry.isolationFailed("Unable to create subject-isolated pixels for \(destination.path).")
        }
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MaskGeometry.isolationFailed("Unable to create subject derivative destination \(destination.path).")
        }
        CGImageDestinationAddImage(
            imageDestination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(imageDestination) else {
            throw MaskGeometry.isolationFailed("Unable to finalize subject derivative \(destination.path).")
        }
    }

    private func sRGBColorSpace() throws -> CGColorSpace {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw MaskGeometry.isolationFailed("Unable to create sRGB color space for subject isolation.")
        }
        return colorSpace
    }
}
