import Foundation

/// Source image discovered by a Phase 1 scan.
///
/// `relativePath` is rooted at the scan root and is preserved for later output
/// tree mirroring. `fileExtension` keeps the source spelling while
/// `detectedType` stores the normalized supported type.
public struct SourceImage: Codable, Sendable, Equatable {
    public var path: String
    public var relativePath: String
    public var fileName: String
    public var fileExtension: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var detectedType: SupportedImageType
    public var identity: SourceIdentity

    enum CodingKeys: String, CodingKey {
        case path
        case relativePath = "relative_path"
        case fileName = "file_name"
        case fileExtension = "file_extension"
        case fileSize = "file_size"
        case modifiedAt = "modified_at"
        case detectedType = "detected_type"
        case identity
    }

    public init(
        path: String,
        relativePath: String,
        fileName: String,
        fileExtension: String,
        fileSize: Int64,
        modifiedAt: Date,
        detectedType: SupportedImageType,
        identity: SourceIdentity
    ) {
        self.path = path
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.detectedType = detectedType
        self.identity = identity
    }
}
