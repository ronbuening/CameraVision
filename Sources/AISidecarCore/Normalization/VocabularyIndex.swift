import Foundation

/// Deterministic lookup indexes derived from validated vocabulary entries.
public struct VocabularyIndex: Sendable, Equatable {
    private var byCanonicalPath: [String: ResolvedVocabularyEntry]
    private var canonicalPathByFoldedTerm: [String: String]
    private var canonicalFoldedTerms: Set<String>
    private var ambiguousCanonicalFoldedTerms: Set<String>
    private var ambiguousFoldedAliasTerms: Set<String>
    private var canonicalPathBySeparatorFoldedTerm: [String: String]
    private var ambiguousSeparatorFoldedTerms: Set<String>
    private var childrenByParentPath: [String: [String]]
    private var canonicalPathsByNamespace: [VocabularyNamespace: [String]]
    private var canonicalPathsByMutuallyExclusiveGroup: [String: [String]]

    public init(entries: [ResolvedVocabularyEntry]) {
        self.byCanonicalPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalPath, $0) })
        self.canonicalPathByFoldedTerm = [:]
        self.canonicalFoldedTerms = []
        self.ambiguousCanonicalFoldedTerms = []
        self.ambiguousFoldedAliasTerms = []
        self.canonicalPathBySeparatorFoldedTerm = [:]
        self.ambiguousSeparatorFoldedTerms = []
        self.childrenByParentPath = [:]
        self.canonicalPathsByNamespace = [:]
        self.canonicalPathsByMutuallyExclusiveGroup = [:]

        let sortedEntries = entries.sorted(by: { $0.canonicalPath < $1.canonicalPath })
        for entry in sortedEntries {
            insertCanonicalLookup(entry.canonicalPath, canonicalPath: entry.canonicalPath)
            insertSeparatorLookup(entry.canonicalPath, canonicalPath: entry.canonicalPath)
        }
        for entry in sortedEntries {
            insertAliasLookup(entry.flatKeyword, canonicalPath: entry.canonicalPath)
            insertSeparatorLookup(entry.flatKeyword, canonicalPath: entry.canonicalPath)
            for synonym in entry.synonyms {
                insertAliasLookup(synonym, canonicalPath: entry.canonicalPath)
                insertSeparatorLookup(synonym, canonicalPath: entry.canonicalPath)
            }
            if let parentPath = entry.parentPath {
                childrenByParentPath[parentPath, default: []].append(entry.canonicalPath)
            }
            canonicalPathsByNamespace[entry.namespace, default: []].append(entry.canonicalPath)
            if let group = entry.mutuallyExclusiveGroup {
                canonicalPathsByMutuallyExclusiveGroup[group, default: []].append(entry.canonicalPath)
            }
        }

        for key in childrenByParentPath.keys {
            childrenByParentPath[key]?.sort()
        }
        for namespace in canonicalPathsByNamespace.keys {
            canonicalPathsByNamespace[namespace]?.sort()
        }
        for group in canonicalPathsByMutuallyExclusiveGroup.keys {
            canonicalPathsByMutuallyExclusiveGroup[group]?.sort()
        }
    }

    public func entry(canonicalPath: String) -> ResolvedVocabularyEntry? {
        byCanonicalPath[canonicalPath]
    }

    public func entry(matching value: String) -> ResolvedVocabularyEntry? {
        let folded = VocabularyTextFolder.fold(value)
        let exactFoldIsAmbiguous =
            ambiguousCanonicalFoldedTerms.contains(folded)
            || ambiguousFoldedAliasTerms.contains(folded)
        // FR3-003b-1: an ambiguous primary key is terminal. Punctuation or
        // number fallbacks must not reinterpret a shared exact alias.
        guard !exactFoldIsAmbiguous else {
            return nil
        }
        if let canonicalPath = canonicalPathByFoldedTerm[folded] {
            return byCanonicalPath[canonicalPath]
        }

        // Exact FR3-003d folding stays authoritative. Fallback aliases are only
        // used when punctuation/number differences collapse to one canonical path.
        let separatorFolded = VocabularyTextFolder.separatorInsensitiveFold(value)
        if let canonicalPath = entryCanonicalPath(separatorFolded: separatorFolded) {
            return byCanonicalPath[canonicalPath]
        }

        for variantFolded in VocabularyTextFolder.finalTokenVariantSeparatorInsensitiveFolds(separatorFolded) {
            if let canonicalPath = entryCanonicalPath(separatorFolded: variantFolded) {
                return byCanonicalPath[canonicalPath]
            }
        }

        return nil
    }

    public func ancestors(of canonicalPath: String) -> [ResolvedVocabularyEntry] {
        var ancestors: [ResolvedVocabularyEntry] = []
        var parentPath = byCanonicalPath[canonicalPath]?.parentPath
        while let current = parentPath, let entry = byCanonicalPath[current] {
            ancestors.append(entry)
            parentPath = entry.parentPath
        }
        return ancestors
    }

    public func descendants(of canonicalPath: String) -> [ResolvedVocabularyEntry] {
        var results: [ResolvedVocabularyEntry] = []
        var pending = childrenByParentPath[canonicalPath] ?? []
        while let next = pending.first {
            pending.removeFirst()
            if let entry = byCanonicalPath[next] {
                results.append(entry)
                pending.append(contentsOf: childrenByParentPath[next] ?? [])
            }
        }
        return results.sorted { $0.canonicalPath < $1.canonicalPath }
    }

    public func siblings(of canonicalPath: String) -> [ResolvedVocabularyEntry] {
        guard let parentPath = byCanonicalPath[canonicalPath]?.parentPath else {
            return []
        }
        return (childrenByParentPath[parentPath] ?? [])
            .filter { $0 != canonicalPath }
            .compactMap { byCanonicalPath[$0] }
    }

    public func entries(in namespace: VocabularyNamespace) -> [ResolvedVocabularyEntry] {
        (canonicalPathsByNamespace[namespace] ?? []).compactMap { byCanonicalPath[$0] }
    }

    public func entries(mutuallyExclusiveGroup: String) -> [ResolvedVocabularyEntry] {
        (canonicalPathsByMutuallyExclusiveGroup[mutuallyExclusiveGroup] ?? []).compactMap { byCanonicalPath[$0] }
    }

    private mutating func insertCanonicalLookup(_ value: String, canonicalPath: String) {
        let folded = VocabularyTextFolder.fold(value)
        guard !folded.isEmpty, !ambiguousCanonicalFoldedTerms.contains(folded) else {
            return
        }
        canonicalFoldedTerms.insert(folded)
        if let existing = canonicalPathByFoldedTerm[folded], existing != canonicalPath {
            canonicalPathByFoldedTerm.removeValue(forKey: folded)
            ambiguousCanonicalFoldedTerms.insert(folded)
        } else {
            canonicalPathByFoldedTerm[folded] = canonicalPath
        }
    }

    private mutating func insertAliasLookup(_ value: String, canonicalPath: String) {
        let folded = VocabularyTextFolder.fold(value)
        let isReserved = canonicalFoldedTerms.contains(folded) || ambiguousFoldedAliasTerms.contains(folded)
        guard !folded.isEmpty, !isReserved else {
            return
        }
        if let existing = canonicalPathByFoldedTerm[folded], existing != canonicalPath {
            canonicalPathByFoldedTerm.removeValue(forKey: folded)
            ambiguousFoldedAliasTerms.insert(folded)
        } else {
            canonicalPathByFoldedTerm[folded] = canonicalPath
        }
    }

    private mutating func insertSeparatorLookup(_ value: String, canonicalPath: String) {
        let folded = VocabularyTextFolder.separatorInsensitiveFold(value)
        guard !folded.isEmpty, !ambiguousSeparatorFoldedTerms.contains(folded) else {
            return
        }
        if let existing = canonicalPathBySeparatorFoldedTerm[folded], existing != canonicalPath {
            canonicalPathBySeparatorFoldedTerm.removeValue(forKey: folded)
            ambiguousSeparatorFoldedTerms.insert(folded)
        } else {
            canonicalPathBySeparatorFoldedTerm[folded] = canonicalPath
        }
    }

    private func entryCanonicalPath(separatorFolded: String) -> String? {
        guard !ambiguousSeparatorFoldedTerms.contains(separatorFolded) else {
            return nil
        }
        return canonicalPathBySeparatorFoldedTerm[separatorFolded]
    }
}
