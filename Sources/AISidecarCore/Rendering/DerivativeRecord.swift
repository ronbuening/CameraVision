import Foundation

/// Provenance for a rendered derivative stored outside the raw JSON sidecar.
///
/// The sidecar records paths and hashes, never image bytes, satisfying FR1-043
/// while preserving enough detail to identify the exact model input.
public struct DerivativeRecord: Codable, Sendable, Equatable {
    public var role: DerivativeRole
    public var cachePath: String
    public var debugPath: String?
    public var format: DerivativeFormat
    public var width: Int
    public var height: Int
    public var colorSpace: ModelInputColorSpace
    public var appliedOrientation: AppliedOrientation
    public var recipeVersion: String
    public var sha256: String
    public var sourceIdentity: SourceIdentity

    enum CodingKeys: String, CodingKey {
        case role
        case cachePath = "cache_path"
        case debugPath = "debug_path"
        case format
        case width
        case height
        case colorSpace = "color_space"
        case appliedOrientation = "applied_orientation"
        case recipeVersion = "recipe_version"
        case sha256
        case sourceIdentity = "source_identity"
    }

    public init(
        role: DerivativeRole,
        cachePath: String,
        debugPath: String? = nil,
        format: DerivativeFormat,
        width: Int,
        height: Int,
        colorSpace: ModelInputColorSpace,
        appliedOrientation: AppliedOrientation,
        recipeVersion: String,
        sha256: String,
        sourceIdentity: SourceIdentity
    ) {
        self.role = role
        self.cachePath = cachePath
        self.debugPath = debugPath
        self.format = format
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
        self.appliedOrientation = appliedOrientation
        self.recipeVersion = recipeVersion
        self.sha256 = sha256
        self.sourceIdentity = sourceIdentity
    }
}
