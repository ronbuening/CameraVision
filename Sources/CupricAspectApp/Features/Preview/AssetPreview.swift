import AISidecarCore
import CoreGraphics
import Foundation
import ImageIO

/// Decoded images plus Core-provided preview facts for one asset.
struct AssetPreviewDetails: @unchecked Sendable, Equatable {
    var fullImage: CGImage?
    var subjectImage: CGImage?
    var instanceCount: Int?
    var selectedInstanceIndices: [Int] = []
    var isolationStatus: String?
    var modelRunCount = 0
    var keywordCandidateCount: Int?
    var sidecarErrors: [String] = []

    /// Load preview content for a source image.
    ///
    /// Preference order for the large image: the pipeline's cached
    /// `whole_image` derivative (already rendered, orientation applied,
    /// cache hits carry over from analysis) → downsampled source file.
    /// The subject panel appears only when the `subject_isolated`
    /// derivative still exists in the cache.
    static func load(
        sourcePath: String,
        relativePath: String,
        outputDir: String?,
        maxPixel: Int = 1600,
        fileManager: FileManager = .default
    ) -> AssetPreviewDetails {
        let presentation = AssetPreviewLoader(fileManager: fileManager).load(
            sourcePath: sourcePath,
            relativePath: relativePath,
            outputDir: outputDir
        )
        var details = AssetPreviewDetails(
            instanceCount: presentation.instanceCount,
            selectedInstanceIndices: presentation.selectedInstanceIndices,
            isolationStatus: presentation.isolationStatus,
            modelRunCount: presentation.modelRunCount,
            keywordCandidateCount: presentation.keywordCandidateCount,
            sidecarErrors: presentation.sidecarErrors
        )
        if let subjectPath = presentation.subjectImageDerivativePath {
            details.subjectImage = decodeImage(path: subjectPath, maxPixel: maxPixel)
        }
        details.fullImage = decodeImage(
            path: presentation.wholeImageDerivativePath ?? presentation.sourcePath,
            maxPixel: maxPixel
        )
        if details.fullImage == nil, presentation.wholeImageDerivativePath != nil {
            details.fullImage = decodeImage(path: presentation.sourcePath, maxPixel: maxPixel)
        }
        return details
    }

    private static func decodeImage(path: String, maxPixel: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
