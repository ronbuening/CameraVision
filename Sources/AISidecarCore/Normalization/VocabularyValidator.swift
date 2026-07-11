import Foundation

/// Integrity validation and conservative default derivation for Phase 3 vocabularies.
public enum VocabularyValidator {
    public static func validate(_ document: VocabularyDocument) throws -> [ResolvedVocabularyEntry] {
        guard document.schemaVersion == NormalizationSchemaIdentifiers.vocabulary else {
            throw vocabularyInvalid("Unsupported vocabulary schema_version: \(document.schemaVersion)")
        }
        guard !document.entries.isEmpty else {
            throw vocabularyInvalid("Vocabulary must contain at least one entry.")
        }

        try validateCanonicalPaths(document.entries)
        try validateSynonyms(document.entries)
        try validateFlatKeywords(document.entries)
        try validateParentsAndCycles(document.entries)

        let resolvedEntries = document.entries.map(resolveDefaults)
        try validateResolvedPolicies(resolvedEntries)
        return resolvedEntries.sorted { $0.canonicalPath < $1.canonicalPath }
    }

    private static func validateCanonicalPaths(_ entries: [VocabularyEntry]) throws {
        var seen: [String: String] = [:]
        for entry in entries {
            let path = entry.canonicalPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path == entry.canonicalPath, !path.isEmpty else {
                throw vocabularyInvalid("canonical_path must be non-empty and must not have leading or trailing whitespace.")
            }
            let levels = path.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard levels.allSatisfy({ !$0.isEmpty }) else {
                throw vocabularyInvalid("canonical_path contains an empty hierarchy level: \(entry.canonicalPath)")
            }
            if let existing = seen[path] {
                throw vocabularyInvalid("Duplicate canonical_path values: \(existing), \(entry.canonicalPath)")
            }
            seen[path] = entry.canonicalPath
            guard !entry.flatKeyword.contains("|") else {
                throw vocabularyInvalid("flat_keyword must not contain '|': \(entry.canonicalPath)")
            }
            guard !entry.flatKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw vocabularyInvalid("flat_keyword must be non-empty: \(entry.canonicalPath)")
            }
            if entry.parentPath == nil, entry.canonicalPath.contains("|") {
                throw vocabularyInvalid("Non-root vocabulary entry is missing parent_path: \(entry.canonicalPath)")
            }
        }
    }

    private static func validateSynonyms(_ entries: [VocabularyEntry]) throws {
        var synonymOwnerByFoldedTerm: [String: String] = [:]
        let foldedCanonicalPaths = Set(entries.map { VocabularyTextFolder.fold($0.canonicalPath) })

        for entry in entries {
            var localSynonyms = Set<String>()
            for synonym in entry.synonyms {
                let folded = VocabularyTextFolder.fold(synonym)
                guard !folded.isEmpty else {
                    throw vocabularyInvalid("synonyms must not be empty: \(entry.canonicalPath)")
                }
                guard !foldedCanonicalPaths.contains(folded) else {
                    throw vocabularyInvalid("Synonym collides with a canonical_path: \(synonym)")
                }
                guard localSynonyms.insert(folded).inserted else {
                    throw vocabularyInvalid("Duplicate synonym within \(entry.canonicalPath): \(synonym)")
                }
                if let existing = synonymOwnerByFoldedTerm[folded] {
                    throw vocabularyInvalid("Synonym maps to multiple entries: \(synonym) under \(existing) and \(entry.canonicalPath)")
                }
                synonymOwnerByFoldedTerm[folded] = entry.canonicalPath
            }
        }
    }

    private static func validateFlatKeywords(_ entries: [VocabularyEntry]) throws {
        var canonicalOwnersByFoldedTerm: [String: [String]] = [:]
        var flatOwnersByFoldedTerm: [String: [String]] = [:]
        var synonymOwnersByFoldedTerm: [String: [String]] = [:]

        for entry in entries {
            canonicalOwnersByFoldedTerm[VocabularyTextFolder.fold(entry.canonicalPath), default: []]
                .append(entry.canonicalPath)
            flatOwnersByFoldedTerm[VocabularyTextFolder.fold(entry.flatKeyword), default: []]
                .append(entry.canonicalPath)
            for synonym in entry.synonyms {
                synonymOwnersByFoldedTerm[VocabularyTextFolder.fold(synonym), default: []]
                    .append(entry.canonicalPath)
            }
        }

        var collisions: [String] = []
        for (folded, owners) in canonicalOwnersByFoldedTerm where Set(owners).count > 1 {
            collisions.append("folded canonical_path '\(folded)' maps to \(owners.sorted().joined(separator: ", "))")
        }
        for (folded, flatOwners) in flatOwnersByFoldedTerm {
            if let canonicalOwners = canonicalOwnersByFoldedTerm[folded] {
                let distinctFlatOwners = Set(flatOwners)
                for flatOwner in flatOwners {
                    for canonicalOwner in canonicalOwners where canonicalOwner != flatOwner {
                        // A canonical entry and another entry may intentionally share one display
                        // keyword; duplicate flat labels remain runtime-ambiguity-guarded.
                        guard !distinctFlatOwners.contains(canonicalOwner) else {
                            continue
                        }
                        collisions.append(
                            "flat_keyword under \(flatOwner) collides with canonical_path \(canonicalOwner)"
                        )
                    }
                }
            }
            if let synonymOwners = synonymOwnersByFoldedTerm[folded] {
                for flatOwner in flatOwners {
                    for synonymOwner in synonymOwners where synonymOwner != flatOwner {
                        collisions.append(
                            "flat_keyword under \(flatOwner) collides with synonym under \(synonymOwner)"
                        )
                    }
                }
            }
        }

        guard !collisions.isEmpty else {
            return
        }
        let collisionList = Set(collisions).sorted().joined(separator: "; ")
        throw vocabularyInvalid("Vocabulary alias collisions: \(collisionList)")
    }

    private static func validateParentsAndCycles(_ entries: [VocabularyEntry]) throws {
        let entryByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalPath, $0) })
        for entry in entries {
            guard let parentPath = entry.parentPath else {
                continue
            }
            guard !parentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw vocabularyInvalid("parent_path must not be empty: \(entry.canonicalPath)")
            }
            guard entryByPath[parentPath] != nil else {
                throw vocabularyInvalid("Orphan parent_path \(parentPath) for \(entry.canonicalPath)")
            }
        }

        var visiting = Set<String>()
        var visited = Set<String>()
        for entry in entries {
            try visit(entry.canonicalPath, entryByPath: entryByPath, visiting: &visiting, visited: &visited)
        }
    }

    private static func visit(
        _ path: String,
        entryByPath: [String: VocabularyEntry],
        visiting: inout Set<String>,
        visited: inout Set<String>
    ) throws {
        if visited.contains(path) {
            return
        }
        guard visiting.insert(path).inserted else {
            throw vocabularyInvalid("Vocabulary hierarchy contains a cycle at \(path)")
        }
        if let parentPath = entryByPath[path]?.parentPath {
            try visit(parentPath, entryByPath: entryByPath, visiting: &visiting, visited: &visited)
        }
        visiting.remove(path)
        visited.insert(path)
    }

    private static func resolveDefaults(_ entry: VocabularyEntry) -> ResolvedVocabularyEntry {
        let requiresReview = entry.requiresReview ?? defaultRequiresReview(entry)
        let specificity = entry.specificity ?? defaultSpecificity(entry, requiresReview: requiresReview)
        let propagationScope = entry.propagationScope ?? defaultPropagationScope(
            entry,
            requiresReview: requiresReview,
            specificity: specificity
        )
        let directApplyPolicy = entry.directApplyPolicy ?? defaultDirectApplyPolicy(
            entry,
            requiresReview: requiresReview
        )
        let autoApplyAllowed = entry.autoApplyAllowed ?? (!requiresReview && (propagationScope == .local || propagationScope == .global))

        return ResolvedVocabularyEntry(
            canonicalPath: entry.canonicalPath,
            flatKeyword: entry.flatKeyword,
            namespace: entry.namespace,
            parentPath: entry.parentPath,
            synonyms: entry.synonyms,
            requiresReview: requiresReview,
            autoApplyAllowed: autoApplyAllowed,
            directApplyPolicy: directApplyPolicy,
            mutuallyExclusiveGroup: entry.mutuallyExclusiveGroup,
            exportFlatKeyword: entry.exportFlatKeyword ?? true,
            exportHierarchicalKeyword: entry.exportHierarchicalKeyword ?? true,
            propagationScope: propagationScope,
            specificity: specificity,
            notes: entry.notes
        )
    }

    private static func defaultRequiresReview(_ entry: VocabularyEntry) -> Bool {
        guard entry.parentPath != nil else {
            return false
        }
        switch entry.namespace {
        case .speciesTaxonomy:
            return entry.canonicalPath.split(separator: "|").count >= 3
        case .people, .event:
            return true
        case .locationType:
            return entry.canonicalPath.split(separator: "|").count >= 3
        default:
            return false
        }
    }

    private static func defaultSpecificity(
        _ entry: VocabularyEntry,
        requiresReview: Bool
    ) -> VocabularySpecificity {
        if requiresReview {
            return .specific
        }
        let depth = entry.canonicalPath.split(separator: "|").count
        if entry.parentPath == nil || depth <= 2 {
            return .broad
        }
        switch entry.namespace {
        case .subject, .habitat, .scene:
            return depth <= 3 ? .mid : .specific
        case .speciesTaxonomy:
            return depth <= 2 ? .broad : .specific
        default:
            return .mid
        }
    }

    private static func defaultPropagationScope(
        _ entry: VocabularyEntry,
        requiresReview: Bool,
        specificity: VocabularySpecificity
    ) -> PropagationScope {
        if requiresReview || entry.parentPath == nil {
            return .none
        }
        if specificity == .specific {
            return .directOnly
        }
        switch entry.namespace {
        case .lighting, .composition, .technicalQuality:
            return .directOnly
        case .workflow:
            return .directOnly
        default:
            return .local
        }
    }

    private static func defaultDirectApplyPolicy(
        _ entry: VocabularyEntry,
        requiresReview: Bool
    ) -> DirectApplyPolicy {
        if requiresReview {
            return .withhold
        }
        if entry.parentPath == nil {
            return .withhold
        }
        return .allow
    }

    private static func validateResolvedPolicies(_ entries: [ResolvedVocabularyEntry]) throws {
        for entry in entries {
            if entry.propagationScope == .global, entry.specificity != .broad {
                throw vocabularyInvalid("global propagation_scope requires broad specificity: \(entry.canonicalPath)")
            }
            if entry.requiresReview, entry.autoApplyAllowed {
                throw vocabularyInvalid("requires_review entries cannot auto-apply by default: \(entry.canonicalPath)")
            }
        }
    }
}

func vocabularyInvalid(_ message: String) -> SidecarError {
    SidecarError(code: .vocabularyInvalid, stage: .normalize, message: message, recoverable: false)
}
