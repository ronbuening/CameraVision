import Foundation

/// Runtime identity for the metadata writer used by export reports and validation records.
public struct MetadataWriteEngineContext: Codable, Sendable, Equatable {
    public var engineName: String
    public var engineVersion: String
    public var writerRecipeVersion: String

    enum CodingKeys: String, CodingKey {
        case engineName = "engine_name"
        case engineVersion = "engine_version"
        case writerRecipeVersion = "writer_recipe_version"
    }

    public init(engineName: String, engineVersion: String, writerRecipeVersion: String) {
        self.engineName = engineName
        self.engineVersion = engineVersion
        self.writerRecipeVersion = writerRecipeVersion
    }
}

/// One metadata-write request consumed by a `MetadataWriteEngine`.
public struct XMPWriteRequest: Codable, Sendable, Equatable {
    public var plan: XMPChangePlan

    public var ratingWrite: PlannedScalarWrite? { plan.ratingWrite }
    public var labelWrite: PlannedScalarWrite? { plan.labelWrite }
    public var urgencyWrite: PlannedScalarWrite? { plan.urgencyWrite }
    public var pickWrite: PlannedScalarWrite? { plan.pickWrite }
    public var goodWrite: PlannedScalarWrite? { plan.goodWrite }

    public init(plan: XMPChangePlan) {
        self.plan = plan
    }
}

/// Non-mutating view of the keyword merge an engine would perform for one XMP target.
public struct XMPWritePreview: Codable, Sendable, Equatable {
    public var targetXMPPath: String
    public var wouldCreate: Bool
    public var existingFlatKeywords: [String]
    public var existingHierarchicalKeywords: [String]
    public var resultingFlatKeywords: [String]
    public var resultingHierarchicalKeywords: [String]
    public var flatKeywordsToAdd: [String]
    public var hierarchicalKeywordsToAdd: [String]
    public var existingRating: String?
    public var resultingRating: String?
    public var existingLabel: String?
    public var resultingLabel: String?
    public var existingUrgency: String?
    public var resultingUrgency: String?
    public var existingPick: String?
    public var resultingPick: String?
    public var existingGood: String?
    public var resultingGood: String?
    public var warnings: [SidecarError]
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case targetXMPPath = "target_xmp_path"
        case wouldCreate = "would_create"
        case existingFlatKeywords = "existing_flat_keywords"
        case existingHierarchicalKeywords = "existing_hierarchical_keywords"
        case resultingFlatKeywords = "resulting_flat_keywords"
        case resultingHierarchicalKeywords = "resulting_hierarchical_keywords"
        case flatKeywordsToAdd = "flat_keywords_to_add"
        case hierarchicalKeywordsToAdd = "hierarchical_keywords_to_add"
        case existingRating = "existing_rating"
        case resultingRating = "resulting_rating"
        case existingLabel = "existing_label"
        case resultingLabel = "resulting_label"
        case existingUrgency = "existing_urgency"
        case resultingUrgency = "resulting_urgency"
        case existingPick = "existing_pick"
        case resultingPick = "resulting_pick"
        case existingGood = "existing_good"
        case resultingGood = "resulting_good"
        case warnings
        case errors
    }

    public init(
        targetXMPPath: String,
        wouldCreate: Bool,
        existingFlatKeywords: [String],
        existingHierarchicalKeywords: [String],
        resultingFlatKeywords: [String],
        resultingHierarchicalKeywords: [String],
        flatKeywordsToAdd: [String],
        hierarchicalKeywordsToAdd: [String],
        warnings: [SidecarError] = [],
        errors: [SidecarError] = [],
        existingRating: String? = nil,
        resultingRating: String? = nil,
        existingLabel: String? = nil,
        resultingLabel: String? = nil,
        existingUrgency: String? = nil,
        resultingUrgency: String? = nil,
        existingPick: String? = nil,
        resultingPick: String? = nil,
        existingGood: String? = nil,
        resultingGood: String? = nil
    ) {
        self.targetXMPPath = targetXMPPath
        self.wouldCreate = wouldCreate
        self.existingFlatKeywords = existingFlatKeywords
        self.existingHierarchicalKeywords = existingHierarchicalKeywords
        self.resultingFlatKeywords = resultingFlatKeywords
        self.resultingHierarchicalKeywords = resultingHierarchicalKeywords
        self.flatKeywordsToAdd = flatKeywordsToAdd
        self.hierarchicalKeywordsToAdd = hierarchicalKeywordsToAdd
        self.existingRating = existingRating
        self.resultingRating = resultingRating
        self.existingLabel = existingLabel
        self.resultingLabel = resultingLabel
        self.existingUrgency = existingUrgency
        self.resultingUrgency = resultingUrgency
        self.existingPick = existingPick
        self.resultingPick = resultingPick
        self.existingGood = existingGood
        self.resultingGood = resultingGood
        self.warnings = warnings
        self.errors = errors
    }
}

/// Result recorded after one XMP write attempt succeeds.
public struct XMPWriteResult: Codable, Sendable, Equatable {
    public var targetXMPPath: String
    public var created: Bool
    public var modified: Bool
    public var preWriteSnapshot: XMPMetadataSnapshot
    public var postWriteSnapshot: XMPMetadataSnapshot
    public var addedFlatKeywords: [String]
    public var addedHierarchicalKeywords: [String]
    public var existingRating: String?
    public var resultingRating: String?
    public var existingLabel: String?
    public var resultingLabel: String?
    public var existingUrgency: String?
    public var resultingUrgency: String?
    public var existingPick: String?
    public var resultingPick: String?
    public var existingGood: String?
    public var resultingGood: String?
    public var warnings: [SidecarError]
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case targetXMPPath = "target_xmp_path"
        case created
        case modified
        case preWriteSnapshot = "pre_write_snapshot"
        case postWriteSnapshot = "post_write_snapshot"
        case addedFlatKeywords = "added_flat_keywords"
        case addedHierarchicalKeywords = "added_hierarchical_keywords"
        case existingRating = "existing_rating"
        case resultingRating = "resulting_rating"
        case existingLabel = "existing_label"
        case resultingLabel = "resulting_label"
        case existingUrgency = "existing_urgency"
        case resultingUrgency = "resulting_urgency"
        case existingPick = "existing_pick"
        case resultingPick = "resulting_pick"
        case existingGood = "existing_good"
        case resultingGood = "resulting_good"
        case warnings
        case errors
    }

    public init(
        targetXMPPath: String,
        created: Bool,
        modified: Bool,
        preWriteSnapshot: XMPMetadataSnapshot,
        postWriteSnapshot: XMPMetadataSnapshot,
        addedFlatKeywords: [String],
        addedHierarchicalKeywords: [String],
        warnings: [SidecarError] = [],
        errors: [SidecarError] = [],
        existingRating: String? = nil,
        resultingRating: String? = nil,
        existingLabel: String? = nil,
        resultingLabel: String? = nil,
        existingUrgency: String? = nil,
        resultingUrgency: String? = nil,
        existingPick: String? = nil,
        resultingPick: String? = nil,
        existingGood: String? = nil,
        resultingGood: String? = nil
    ) {
        self.targetXMPPath = targetXMPPath
        self.created = created
        self.modified = modified
        self.preWriteSnapshot = preWriteSnapshot
        self.postWriteSnapshot = postWriteSnapshot
        self.addedFlatKeywords = addedFlatKeywords
        self.addedHierarchicalKeywords = addedHierarchicalKeywords
        self.existingRating = existingRating
        self.resultingRating = resultingRating
        self.existingLabel = existingLabel
        self.resultingLabel = resultingLabel
        self.existingUrgency = existingUrgency
        self.resultingUrgency = resultingUrgency
        self.existingPick = existingPick
        self.resultingPick = resultingPick
        self.existingGood = existingGood
        self.resultingGood = resultingGood
        self.warnings = warnings
        self.errors = errors
    }
}

/// Metadata-writer policy boundary used by Phase 2 and later export workflows.
public protocol MetadataWriteEngine: Sendable {
    /// Prepare engine identity before a batch starts.
    func prepare(configuration: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext

    /// Read managed keyword fields and unmanaged-content fingerprint for one target.
    func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot

    /// Render the intended keyword merge without writing a sidecar.
    func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview

    /// Apply one planned keyword merge.
    func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult

    /// Prove that a sidecar can be parsed by this engine.
    func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot

    /// Release any engine resources after a batch.
    func shutdown() throws
}

/// Deterministic metadata writer for tests that need export behavior without XML I/O.
public struct MockMetadataWriteEngine: MetadataWriteEngine {
    private let context: MetadataWriteEngineContext
    private let snapshotsByPath: [String: XMPMetadataSnapshot]
    private let previewResult: XMPWritePreview?
    private let applyResult: XMPWriteResult?

    public init(
        context: MetadataWriteEngineContext = MetadataWriteEngineContext(
            engineName: OwnedXMPSidecarEngine.engineName,
            engineVersion: OwnedXMPSidecarEngine.engineVersion,
            writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
        ),
        snapshotsByPath: [String: XMPMetadataSnapshot] = [:],
        previewResult: XMPWritePreview? = nil,
        applyResult: XMPWriteResult? = nil
    ) {
        self.context = context
        self.snapshotsByPath = snapshotsByPath
        self.previewResult = previewResult
        self.applyResult = applyResult
    }

    public func prepare(configuration _: ResolvedXMPExportConfiguration) throws -> MetadataWriteEngineContext {
        context
    }

    public func readSnapshot(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        snapshotsByPath[targetXMPPath] ?? XMPMetadataSnapshot.empty(targetPath: targetXMPPath, exists: false)
    }

    public func preview(_ request: XMPWriteRequest) throws -> XMPWritePreview {
        if let previewResult {
            return previewResult
        }
        let snapshot = try readSnapshot(at: request.plan.targetXMPPath)
        let flatTerms = request.plan.flatKeywordsToAdd.map(\.term)
        let hierarchicalTerms = request.plan.hierarchicalKeywordsToAdd.map(\.term)
        let resultingRating = resultingScalar(existing: snapshot.rating, write: request.ratingWrite)
        let resultingLabel = resultingScalar(existing: snapshot.label, write: request.labelWrite)
        let resultingUrgency = resultingScalar(existing: snapshot.urgency, write: request.urgencyWrite)
        let resultingPick = resultingScalar(existing: snapshot.pick, write: request.pickWrite)
        let resultingGood = resultingScalar(existing: snapshot.good, write: request.goodWrite)
        return XMPWritePreview(
            targetXMPPath: request.plan.targetXMPPath,
            wouldCreate: !snapshot.exists,
            existingFlatKeywords: snapshot.flatKeywords,
            existingHierarchicalKeywords: snapshot.hierarchicalKeywords,
            resultingFlatKeywords: snapshot.flatKeywords + flatTerms,
            resultingHierarchicalKeywords: snapshot.hierarchicalKeywords + hierarchicalTerms,
            flatKeywordsToAdd: flatTerms,
            hierarchicalKeywordsToAdd: hierarchicalTerms,
            existingRating: snapshot.rating,
            resultingRating: resultingRating,
            existingLabel: snapshot.label,
            resultingLabel: resultingLabel,
            existingUrgency: snapshot.urgency,
            resultingUrgency: resultingUrgency,
            existingPick: snapshot.pick,
            resultingPick: resultingPick,
            existingGood: snapshot.good,
            resultingGood: resultingGood
        )
    }

    public func apply(_ request: XMPWriteRequest) throws -> XMPWriteResult {
        if let applyResult {
            return applyResult
        }
        let preSnapshot = try readSnapshot(at: request.plan.targetXMPPath)
        let preview = try preview(request)
        let postSnapshot = XMPMetadataSnapshot(
            targetPath: request.plan.targetXMPPath,
            exists: true,
            flatKeywords: preview.resultingFlatKeywords,
            hierarchicalKeywords: preview.resultingHierarchicalKeywords,
            unmanagedContentFingerprint: preSnapshot.unmanagedContentFingerprint,
            rating: preview.resultingRating,
            label: preview.resultingLabel,
            urgency: preview.resultingUrgency,
            pick: preview.resultingPick,
            good: preview.resultingGood
        )
        return XMPWriteResult(
            targetXMPPath: request.plan.targetXMPPath,
            created: !preSnapshot.exists,
            modified: preSnapshot.exists,
            preWriteSnapshot: preSnapshot,
            postWriteSnapshot: postSnapshot,
            addedFlatKeywords: preview.flatKeywordsToAdd,
            addedHierarchicalKeywords: preview.hierarchicalKeywordsToAdd,
            existingRating: preview.existingRating,
            resultingRating: preview.resultingRating,
            existingLabel: preview.existingLabel,
            resultingLabel: preview.resultingLabel,
            existingUrgency: preview.existingUrgency,
            resultingUrgency: preview.resultingUrgency,
            existingPick: preview.existingPick,
            resultingPick: preview.resultingPick,
            existingGood: preview.existingGood,
            resultingGood: preview.resultingGood
        )
    }

    public func validateReadable(at targetXMPPath: String) throws -> XMPMetadataSnapshot {
        if let applyResult, applyResult.targetXMPPath == targetXMPPath {
            return applyResult.postWriteSnapshot
        }
        return try readSnapshot(at: targetXMPPath)
    }

    public func shutdown() throws {}

    private func resultingScalar(existing: String?, write: PlannedScalarWrite?) -> String? {
        switch write?.action {
        case .write, .overwrite:
            return write?.plannedValue
        case .skipExisting, nil:
            return existing
        }
    }
}
