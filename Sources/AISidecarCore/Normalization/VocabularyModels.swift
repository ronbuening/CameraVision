import Foundation

/// Controlled vocabulary namespace supported by Phase 3 normalization.
public enum VocabularyNamespace: String, Codable, CaseIterable, Sendable, Hashable {
    case subject = "Subject"
    case speciesTaxonomy = "Species / Taxonomy"
    case habitat = "Habitat"
    case behavior = "Behavior"
    case scene = "Scene"
    case locationType = "Location Type"
    case lighting = "Lighting"
    case composition = "Composition"
    case technicalQuality = "Technical Quality"
    case event = "Event"
    case people = "People"
    case objects = "Objects"
    case textSignage = "Text / Signage"
    case workflow = "Workflow"
}

/// Direct-write policy for direct model observations and explicit user context.
public enum DirectApplyPolicy: String, Codable, CaseIterable, Sendable, Hashable {
    case allow
    case withhold
    case flatOnly = "flat_only"
    case userOnly = "user_only"
}

/// Propagation scope for cross-asset normalization decisions.
public enum PropagationScope: String, Codable, CaseIterable, Sendable, Hashable {
    case none
    case directOnly = "direct_only"
    case local
    case global
}

/// Specificity class used by later propagation thresholds.
public enum VocabularySpecificity: String, Codable, CaseIterable, Sendable, Hashable {
    case broad
    case mid
    case specific
}

/// JSON document for the Phase 3 controlled vocabulary schema.
public struct VocabularyDocument: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var entries: [VocabularyEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }

    public init(schemaVersion: String, entries: [VocabularyEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

/// One user-editable controlled vocabulary entry before defaults are derived.
public struct VocabularyEntry: Codable, Sendable, Hashable {
    public var canonicalPath: String
    public var flatKeyword: String
    public var namespace: VocabularyNamespace
    public var parentPath: String?
    public var synonyms: [String]
    public var requiresReview: Bool?
    public var autoApplyAllowed: Bool?
    public var directApplyPolicy: DirectApplyPolicy?
    public var mutuallyExclusiveGroup: String?
    public var exportFlatKeyword: Bool?
    public var exportHierarchicalKeyword: Bool?
    public var propagationScope: PropagationScope?
    public var specificity: VocabularySpecificity?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case canonicalPath = "canonical_path"
        case flatKeyword = "flat_keyword"
        case namespace
        case parentPath = "parent_path"
        case synonyms
        case requiresReview = "requires_review"
        case autoApplyAllowed = "auto_apply_allowed"
        case directApplyPolicy = "direct_apply_policy"
        case mutuallyExclusiveGroup = "mutually_exclusive_group"
        case exportFlatKeyword = "export_flat_keyword"
        case exportHierarchicalKeyword = "export_hierarchical_keyword"
        case propagationScope = "propagation_scope"
        case specificity
        case notes
    }

    public init(
        canonicalPath: String,
        flatKeyword: String,
        namespace: VocabularyNamespace,
        parentPath: String?,
        synonyms: [String] = [],
        requiresReview: Bool? = nil,
        autoApplyAllowed: Bool? = nil,
        directApplyPolicy: DirectApplyPolicy? = nil,
        mutuallyExclusiveGroup: String? = nil,
        exportFlatKeyword: Bool? = nil,
        exportHierarchicalKeyword: Bool? = nil,
        propagationScope: PropagationScope? = nil,
        specificity: VocabularySpecificity? = nil,
        notes: String? = nil
    ) {
        self.canonicalPath = canonicalPath
        self.flatKeyword = flatKeyword
        self.namespace = namespace
        self.parentPath = parentPath
        self.synonyms = synonyms
        self.requiresReview = requiresReview
        self.autoApplyAllowed = autoApplyAllowed
        self.directApplyPolicy = directApplyPolicy
        self.mutuallyExclusiveGroup = mutuallyExclusiveGroup
        self.exportFlatKeyword = exportFlatKeyword
        self.exportHierarchicalKeyword = exportHierarchicalKeyword
        self.propagationScope = propagationScope
        self.specificity = specificity
        self.notes = notes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalPath, forKey: .canonicalPath)
        try container.encode(flatKeyword, forKey: .flatKeyword)
        try container.encode(namespace, forKey: .namespace)
        try container.encode(parentPath, forKey: .parentPath)
        try container.encode(synonyms, forKey: .synonyms)
        try container.encodeIfPresent(requiresReview, forKey: .requiresReview)
        try container.encodeIfPresent(autoApplyAllowed, forKey: .autoApplyAllowed)
        try container.encodeIfPresent(directApplyPolicy, forKey: .directApplyPolicy)
        try container.encodeIfPresent(mutuallyExclusiveGroup, forKey: .mutuallyExclusiveGroup)
        try container.encodeIfPresent(exportFlatKeyword, forKey: .exportFlatKeyword)
        try container.encodeIfPresent(exportHierarchicalKeyword, forKey: .exportHierarchicalKeyword)
        try container.encodeIfPresent(propagationScope, forKey: .propagationScope)
        try container.encodeIfPresent(specificity, forKey: .specificity)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

/// Vocabulary entry after conservative Phase 3 defaults have been materialized.
public struct ResolvedVocabularyEntry: Codable, Sendable, Hashable {
    public var canonicalPath: String
    public var flatKeyword: String
    public var namespace: VocabularyNamespace
    public var parentPath: String?
    public var synonyms: [String]
    public var requiresReview: Bool
    public var autoApplyAllowed: Bool
    public var directApplyPolicy: DirectApplyPolicy
    public var mutuallyExclusiveGroup: String?
    public var exportFlatKeyword: Bool
    public var exportHierarchicalKeyword: Bool
    public var propagationScope: PropagationScope
    public var specificity: VocabularySpecificity
    public var notes: String?

    public var pathLevels: [String] {
        canonicalPath.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }

    public init(
        canonicalPath: String,
        flatKeyword: String,
        namespace: VocabularyNamespace,
        parentPath: String?,
        synonyms: [String],
        requiresReview: Bool,
        autoApplyAllowed: Bool,
        directApplyPolicy: DirectApplyPolicy,
        mutuallyExclusiveGroup: String?,
        exportFlatKeyword: Bool,
        exportHierarchicalKeyword: Bool,
        propagationScope: PropagationScope,
        specificity: VocabularySpecificity,
        notes: String?
    ) {
        self.canonicalPath = canonicalPath
        self.flatKeyword = flatKeyword
        self.namespace = namespace
        self.parentPath = parentPath
        self.synonyms = synonyms
        self.requiresReview = requiresReview
        self.autoApplyAllowed = autoApplyAllowed
        self.directApplyPolicy = directApplyPolicy
        self.mutuallyExclusiveGroup = mutuallyExclusiveGroup
        self.exportFlatKeyword = exportFlatKeyword
        self.exportHierarchicalKeyword = exportHierarchicalKeyword
        self.propagationScope = propagationScope
        self.specificity = specificity
        self.notes = notes
    }
}

/// Stable identity for the exact vocabulary bytes used by a run.
public struct VocabularyIdentity: Codable, Sendable, Equatable {
    public var path: String
    public var sha256: String
    public var schemaVersion: String

    enum CodingKeys: String, CodingKey {
        case path
        case sha256
        case schemaVersion = "schema_version"
    }

    public init(path: String, sha256: String, schemaVersion: String) {
        self.path = path
        self.sha256 = sha256
        self.schemaVersion = schemaVersion
    }
}

/// Loaded vocabulary document plus derived defaults and search indexes.
public struct LoadedVocabulary: Sendable, Equatable {
    public var identity: VocabularyIdentity
    public var document: VocabularyDocument
    public var entries: [ResolvedVocabularyEntry]
    public var index: VocabularyIndex

    public init(
        identity: VocabularyIdentity,
        document: VocabularyDocument,
        entries: [ResolvedVocabularyEntry],
        index: VocabularyIndex
    ) {
        self.identity = identity
        self.document = document
        self.entries = entries
        self.index = index
    }
}
