import Foundation

/// One discovered image with scan-time file metadata but no computed identity.
///
/// Inventory entries exist so interactive consumers (the Phase 4 GUI) can list
/// large folders without hashing; `SourceIdentity` is computed later, only when
/// a pipeline actually needs it (requirements FR4-046 lazy-identity policy).
public struct ScanInventoryEntry: Sendable, Equatable {
    public var path: String
    public var relativePath: String
    public var fileName: String
    public var fileExtension: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var detectedType: SupportedImageType

    public init(
        path: String,
        relativePath: String,
        fileName: String,
        fileExtension: String,
        fileSize: Int64,
        modifiedAt: Date,
        detectedType: SupportedImageType
    ) {
        self.path = path
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.detectedType = detectedType
    }
}

/// Discovery-only scan output (plan work item CORE-5).
///
/// Shares `ImageScanner`'s visibility, ignore, and supported-type rules with
/// the identity-computing `scan`, so the two can never disagree about what a
/// folder contains. In-process only — this is not a serialized artifact.
public struct ScanInventory: Sendable, Equatable {
    public var inputPath: String
    public var scanRoot: String
    public var recursive: Bool
    public var entries: [ScanInventoryEntry]
    public var errors: [ScanErrorRecord]

    public init(
        inputPath: String,
        scanRoot: String,
        recursive: Bool,
        entries: [ScanInventoryEntry],
        errors: [ScanErrorRecord]
    ) {
        self.inputPath = inputPath
        self.scanRoot = scanRoot
        self.recursive = recursive
        self.entries = entries
        self.errors = errors
    }
}
