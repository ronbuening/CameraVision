import CoreGraphics
import Foundation
import ImageIO
import Observation

/// An immutable decoded thumbnail. `CGImage` is immutable after creation, so
/// crossing isolation boundaries is safe despite the missing Sendable stamp.
struct Thumbnail: @unchecked Sendable, Equatable {
    let image: CGImage
}

/// In-memory thumbnail provider for the asset grid (M3, FR4-039 groundwork).
///
/// Decodes small previews through ImageIO — using the file's embedded
/// thumbnail when present (RAW embedded previews decode far faster than the
/// RAW itself) — and keeps them in a byte-capped `NSCache`. No disk cache:
/// the shared derivative cache belongs to the pipelines, and thumbnails are
/// cheap to re-decode.
@MainActor
final class ThumbnailStore {
    nonisolated static let pixelSize = 256

    private let cache = NSCache<NSString, ThumbnailBox>()
    private let decodeProvider: @Sendable (String, Int) -> Thumbnail?
    private var inFlight: [String: Task<Thumbnail?, Never>] = [:]

    init(
        costLimitBytes: Int = 256 * 1024 * 1024,
        decodeProvider: @escaping @Sendable (String, Int) -> Thumbnail? = ThumbnailStore.decodeThumbnail
    ) {
        cache.totalCostLimit = costLimitBytes
        self.decodeProvider = decodeProvider
    }

    func cachedThumbnail(for path: String) -> Thumbnail? {
        cache.object(forKey: path as NSString)?.thumbnail
    }

    /// Load (or await the already-loading) thumbnail for a file. Concurrent
    /// requests for the same path share one decode.
    func thumbnail(for path: String) async -> Thumbnail? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached.thumbnail
        }
        if let task = inFlight[path] {
            return await task.value
        }
        let decodeProvider = decodeProvider
        let task = Task.detached(priority: .utility) {
            decodeProvider(path, Self.pixelSize)
        }
        inFlight[path] = task
        let thumbnail = await task.value
        inFlight[path] = nil
        cache.setObject(
            ThumbnailBox(thumbnail),
            forKey: path as NSString,
            cost: thumbnail.map { $0.image.bytesPerRow * $0.image.height } ?? 1_024
        )
        return thumbnail
    }

    nonisolated static func decodeThumbnail(path: String, maxPixel: Int) -> Thumbnail? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Thumbnail(image: image)
    }
}

private final class ThumbnailBox {
    let thumbnail: Thumbnail?
    init(_ thumbnail: Thumbnail?) { self.thumbnail = thumbnail }
}
