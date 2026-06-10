import Foundation

public struct ScanErrorRecord: Codable, Sendable, Equatable {
    public var path: String
    public var relativePath: String?
    public var error: SidecarError

    enum CodingKeys: String, CodingKey {
        case path
        case relativePath = "relative_path"
        case error
    }

    public init(path: String, relativePath: String?, error: SidecarError) {
        self.path = path
        self.relativePath = relativePath
        self.error = error
    }
}

public struct ScanResult: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var inputPath: String
    public var scanRoot: String
    public var recursive: Bool
    public var identityPolicy: SourceIdentityPolicy
    public var images: [SourceImage]
    public var errors: [ScanErrorRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case inputPath = "input_path"
        case scanRoot = "scan_root"
        case recursive
        case identityPolicy = "identity_policy"
        case images
        case errors
    }

    public init(
        schemaVersion: String = "ai-sidecar-scan/1.0",
        inputPath: String,
        scanRoot: String,
        recursive: Bool,
        identityPolicy: SourceIdentityPolicy,
        images: [SourceImage],
        errors: [ScanErrorRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.inputPath = inputPath
        self.scanRoot = scanRoot
        self.recursive = recursive
        self.identityPolicy = identityPolicy
        self.images = images
        self.errors = errors
    }
}
