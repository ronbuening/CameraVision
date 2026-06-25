import Foundation

/// Source image bound into a Phase 3 normalization session.
///
/// This record persists the source identity needed by `apply-session` without
/// copying raw affinity metadata that the privacy policy keeps out of default
/// session artifacts.
public struct NormalizationSourceAsset: Codable, Sendable, Equatable {
    public var assetID: String
    public var sourcePath: String?
    public var sourceRelativePath: String
    public var fileName: String
    public var sourceType: SupportedImageType
    public var sourceIdentity: SourceIdentity
    public var sourceSidecarPath: String?
    public var sourceSidecarRelativePath: String?
    public var sourceIdentityStatus: SourceIdentityStatus?
    public var fileListIndex: Int?
    public var affinityInputs: AssetAffinityInputs

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case sourcePath = "source_path"
        case sourceRelativePath = "source_relative_path"
        case fileName = "file_name"
        case sourceType = "source_type"
        case sourceIdentity = "source_identity"
        case sourceSidecarPath = "source_sidecar_path"
        case sourceSidecarRelativePath = "source_sidecar_relative_path"
        case sourceIdentityStatus = "source_identity_status"
        case fileListIndex = "file_list_index"
        case affinityInputs = "affinity_inputs"
    }

    public init(
        assetID: String,
        sourcePath: String?,
        sourceRelativePath: String,
        fileName: String,
        sourceType: SupportedImageType,
        sourceIdentity: SourceIdentity,
        sourceSidecarPath: String?,
        sourceSidecarRelativePath: String?,
        sourceIdentityStatus: SourceIdentityStatus?,
        fileListIndex: Int?,
        affinityInputs: AssetAffinityInputs
    ) {
        self.assetID = assetID
        self.sourcePath = sourcePath
        self.sourceRelativePath = sourceRelativePath
        self.fileName = fileName
        self.sourceType = sourceType
        self.sourceIdentity = sourceIdentity
        self.sourceSidecarPath = sourceSidecarPath
        self.sourceSidecarRelativePath = sourceSidecarRelativePath
        self.sourceIdentityStatus = sourceIdentityStatus
        self.fileListIndex = fileListIndex
        self.affinityInputs = affinityInputs
    }
}

/// Raw sidecar provenance included in a Phase 3 session.
public struct NormalizationSourceAISidecarRecord: Codable, Sendable, Equatable {
    public var sidecarPath: String
    public var relativePath: String?
    public var sourceAssetID: String
    public var schemaVersion: String
    public var sourceIdentityStatus: SourceIdentityStatus
    public var warnings: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case sidecarPath = "sidecar_path"
        case relativePath = "relative_path"
        case sourceAssetID = "source_asset_id"
        case schemaVersion = "schema_version"
        case sourceIdentityStatus = "source_identity_status"
        case warnings
    }

    public init(
        sidecarPath: String,
        relativePath: String?,
        sourceAssetID: String,
        schemaVersion: String,
        sourceIdentityStatus: SourceIdentityStatus,
        warnings: [SidecarError]
    ) {
        self.sidecarPath = sidecarPath
        self.relativePath = relativePath
        self.sourceAssetID = sourceAssetID
        self.schemaVersion = schemaVersion
        self.sourceIdentityStatus = sourceIdentityStatus
        self.warnings = warnings
    }
}

/// Same-base-name normalization group used for one-vote affinity nodes and later XMP plans.
public struct NormalizationSourceGroup: Codable, Sendable, Equatable {
    public var groupID: String
    public var groupDirectory: String
    public var groupBasename: String
    public var targetRelativePath: String
    public var memberAssetIDs: [String]
    public var selectedAssetIDs: [String]
    public var skippedAssetIDs: [String]

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case groupDirectory = "group_directory"
        case groupBasename = "group_basename"
        case targetRelativePath = "target_relative_path"
        case memberAssetIDs = "member_asset_ids"
        case selectedAssetIDs = "selected_asset_ids"
        case skippedAssetIDs = "skipped_asset_ids"
    }

    public init(
        groupID: String,
        groupDirectory: String,
        groupBasename: String,
        targetRelativePath: String,
        memberAssetIDs: [String],
        selectedAssetIDs: [String],
        skippedAssetIDs: [String]
    ) {
        self.groupID = groupID
        self.groupDirectory = groupDirectory
        self.groupBasename = groupBasename
        self.targetRelativePath = targetRelativePath
        self.memberAssetIDs = memberAssetIDs
        self.selectedAssetIDs = selectedAssetIDs
        self.skippedAssetIDs = skippedAssetIDs
    }
}
