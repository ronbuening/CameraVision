import Foundation

/// Stable phase for one normalization progress record.
public enum NormalizationProgressStage: String, Codable, Sendable, Equatable {
    case inputResolution = "input_resolution"
    case normalization
    case xmpPlanning = "xmp_planning"
    case xmpTarget = "xmp_target"
    case artifactWrite = "artifact_write"
}

/// Stable status for one normalization progress record.
public enum NormalizationProgressStatus: String, Codable, Sendable, Equatable {
    case completed
    case planned
    case skipped
    case failed
}

/// Self-contained JSONL progress record for Phase 3 normalization.
public struct NormalizationProgressRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var stage: NormalizationProgressStage
    public var status: NormalizationProgressStatus
    public var message: String
    public var sourceAssetCount: Int?
    public var perAssetDecisionCount: Int?
    public var xmpWritePlanCount: Int?
    public var targetXMPPath: String?
    public var targetRelativePath: String?
    public var plannedFlatKeywords: [String]
    public var plannedHierarchicalKeywords: [String]
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case stage
        case status
        case message
        case sourceAssetCount = "source_asset_count"
        case perAssetDecisionCount = "per_asset_decision_count"
        case xmpWritePlanCount = "xmp_write_plan_count"
        case targetXMPPath = "target_xmp_path"
        case targetRelativePath = "target_relative_path"
        case plannedFlatKeywords = "planned_flat_keywords"
        case plannedHierarchicalKeywords = "planned_hierarchical_keywords"
        case errors
    }

    public init(
        timestamp: Date = Date(),
        stage: NormalizationProgressStage,
        status: NormalizationProgressStatus,
        message: String,
        sourceAssetCount: Int? = nil,
        perAssetDecisionCount: Int? = nil,
        xmpWritePlanCount: Int? = nil,
        targetXMPPath: String? = nil,
        targetRelativePath: String? = nil,
        plannedFlatKeywords: [String] = [],
        plannedHierarchicalKeywords: [String] = [],
        errors: [SidecarError] = []
    ) {
        self.timestamp = timestamp
        self.stage = stage
        self.status = status
        self.message = message
        self.sourceAssetCount = sourceAssetCount
        self.perAssetDecisionCount = perAssetDecisionCount
        self.xmpWritePlanCount = xmpWritePlanCount
        self.targetXMPPath = targetXMPPath
        self.targetRelativePath = targetRelativePath
        self.plannedFlatKeywords = plannedFlatKeywords
        self.plannedHierarchicalKeywords = plannedHierarchicalKeywords
        self.errors = errors
    }
}

/// Append-only JSONL writer for normalization progress records.
public final class NormalizationProgressLog {
    private let writer: JSONLWriter<NormalizationProgressRecord>

    public var path: String { writer.path }

    /// Create or reopen the JSONL progress file at its final artifact path.
    public init(path: String, fileManager: FileManager = .default) throws {
        self.writer = try JSONLWriter(path: path, label: "normalization progress log", fileManager: fileManager)
    }

    /// Append and flush one progress record before the next stage advances.
    public func append(_ record: NormalizationProgressRecord) throws {
        try writer.append(record)
    }

    /// Close the underlying file handle, surfacing close failures as write errors.
    public func close() throws {
        try writer.close()
    }
}
