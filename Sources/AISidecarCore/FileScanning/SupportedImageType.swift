import Foundation

/// Image file types accepted by Phase 1 scanning.
///
/// Support is extension-based at scan time; actual decode support is verified
/// later by the macOS rendering pipeline.
public enum SupportedImageType: String, Codable, CaseIterable, Sendable {
    case nef
    case nrw
    case cr3
    case cr2
    case arw
    case raf
    case orf
    case rw2
    case dng
    case jpg
    case jpeg
    case tif
    case tiff
    case heic
    case png

    /// Build a supported type from a path extension without requiring callers
    /// to normalize extension case first.
    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}
