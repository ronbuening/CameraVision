import AISidecarCore
import CoreGraphics
import Foundation
import ImageIO

/// Everything the preview surface needs about one asset, loaded off the main
/// actor from the raw sidecar and the shared derivative cache (M3; FR4-013/014
/// groundwork — the M4 review screen builds on the same loader).
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
        rawSidecarPath: String,
        maxPixel: Int = 1600,
        fileManager: FileManager = .default
    ) -> AssetPreviewDetails {
        var details = AssetPreviewDetails()

        var wholeDerivativePath: String?
        if fileManager.fileExists(atPath: rawSidecarPath) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = fileManager.contents(atPath: rawSidecarPath) else {
                details.sidecarErrors.append("sidecar unreadable: \(URL(fileURLWithPath: rawSidecarPath).lastPathComponent)")
                details.fullImage = decodeImage(path: sourcePath, maxPixel: maxPixel)
                return details
            }
            do {
                let sidecar = try decoder.decode(RawJSONSidecar.self, from: data)
                details.modelRunCount = sidecar.modelRuns.count
                details.sidecarErrors = sidecar.errors.map { "\($0.code.rawValue): \($0.message)" }
                if let isolation = sidecar.subjectIsolation {
                    details.instanceCount = isolation.instanceCount
                    details.selectedInstanceIndices = isolation.selectedInstanceIndices
                    details.isolationStatus = isolation.status.rawValue
                }
                for derivative in sidecar.derivatives {
                    switch derivative.role {
                    case .wholeImage where fileManager.fileExists(atPath: derivative.cachePath):
                        wholeDerivativePath = derivative.cachePath
                    case .subjectIsolated where fileManager.fileExists(atPath: derivative.cachePath):
                        details.subjectImage = decodeImage(path: derivative.cachePath, maxPixel: maxPixel)
                    default:
                        break
                    }
                }
            } catch {
                details.sidecarErrors.append("sidecar malformed: \(error.localizedDescription)")
            }
        }

        details.fullImage = decodeImage(path: wholeDerivativePath ?? sourcePath, maxPixel: maxPixel)
        if details.fullImage == nil, wholeDerivativePath != nil {
            details.fullImage = decodeImage(path: sourcePath, maxPixel: maxPixel)
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
