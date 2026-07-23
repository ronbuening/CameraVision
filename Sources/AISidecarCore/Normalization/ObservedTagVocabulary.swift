import CryptoKit
import Foundation

/// Builds the default Phase 3 normalization catalog from model-generated terms in the current batch.
public enum ObservedTagVocabulary {
    /// Stable pseudo-path recorded in sessions that use the generated observed-tags catalog.
    public static let identityPath = "observed-tags://generated"

    /// Build a synthetic flat vocabulary from Phase 2-filtered model terms in the current normalization batch.
    public static func load(
        extractionResults: [CandidateExtractionResult],
        configuration: ResolvedNormalizationConfiguration
    ) throws -> LoadedVocabulary {
        let entries = resolvedEntries(
            extractionResults: extractionResults,
            configuration: configuration
        )
        let document = VocabularyDocument(
            schemaVersion: NormalizationSchemaIdentifiers.vocabulary,
            entries: entries.map(vocabularyEntry)
        )
        let data = try canonicalData(for: document)
        let identity = VocabularyIdentity(
            path: identityPath,
            sha256: sha256(data),
            schemaVersion: document.schemaVersion,
            mode: .observedTags,
            entryCount: entries.count
        )
        return LoadedVocabulary(
            identity: identity,
            document: document,
            entries: entries,
            index: VocabularyIndex(entries: entries)
        )
    }

    /// Return the separator-insensitive key used to collapse singular/plural and punctuation variants.
    public static func observedKey(for normalizedTerm: String) -> String {
        VocabularyTextFolder.variantKey(for: normalizedTerm)
    }

    private static func resolvedEntries(
        extractionResults: [CandidateExtractionResult],
        configuration: ResolvedNormalizationConfiguration
    ) -> [ResolvedVocabularyEntry] {
        let blocked = blockedObservationKeys(extractionResults)
        var termsByObservedKey: [String: [String]] = [:]

        for result in extractionResults {
            for candidate in result.extractedCandidates {
                let normalizedTerm = candidate.normalizedTerm
                guard !normalizedTerm.isEmpty,
                    !normalizedTerm.contains("|"),
                    candidate.confidence >= configuration.minConfidence,
                    !blocked.contains(CandidateObservationKey(candidate: candidate))
                else {
                    continue
                }
                termsByObservedKey[observedKey(for: normalizedTerm), default: []].append(normalizedTerm)
            }
        }

        return termsByObservedKey.keys.sorted().map { key in
            let terms = termsByObservedKey[key, default: []]
            let displayTerm = DisplayTermRanking.preferredTerm(in: terms)
            let synonyms = stableUnique(terms.sorted())
                .filter { $0 != displayTerm }
            return ResolvedVocabularyEntry(
                canonicalPath: displayTerm,
                flatKeyword: displayTerm,
                namespace: .workflow,
                parentPath: nil,
                synonyms: synonyms,
                requiresReview: false,
                autoApplyAllowed: true,
                directApplyPolicy: .flatOnly,
                mutuallyExclusiveGroup: nil,
                exportFlatKeyword: true,
                exportHierarchicalKeyword: false,
                propagationScope: .local,
                specificity: .broad,
                notes: "Observed model tag generated for this normalization run."
            )
        }.sorted { $0.canonicalPath < $1.canonicalPath }
    }

    private static func blockedObservationKeys(_ extractionResults: [CandidateExtractionResult]) -> Set<
        CandidateObservationKey
    > {
        var blocked: Set<CandidateObservationKey> = []
        for result in extractionResults {
            for skipped in result.skippedCandidates {
                guard let candidate = skipped.candidate else {
                    continue
                }
                switch skipped.reason {
                case .coordinateLikeTerm, .gpsOnlyEvidence, .speciesWithoutBiologicalGenre, .specificTagPolicy:
                    blocked.insert(CandidateObservationKey(candidate: candidate))
                default:
                    continue
                }
            }
        }
        return blocked
    }

    private static func vocabularyEntry(_ entry: ResolvedVocabularyEntry) -> VocabularyEntry {
        VocabularyEntry(
            canonicalPath: entry.canonicalPath,
            flatKeyword: entry.flatKeyword,
            namespace: entry.namespace,
            parentPath: entry.parentPath,
            synonyms: entry.synonyms,
            requiresReview: entry.requiresReview,
            autoApplyAllowed: entry.autoApplyAllowed,
            directApplyPolicy: entry.directApplyPolicy,
            mutuallyExclusiveGroup: entry.mutuallyExclusiveGroup,
            exportFlatKeyword: entry.exportFlatKeyword,
            exportHierarchicalKeyword: entry.exportHierarchicalKeyword,
            propagationScope: entry.propagationScope,
            specificity: entry.specificity,
            notes: entry.notes
        )
    }

    private static func canonicalData(for document: VocabularyDocument) throws -> Data {
        let encoder = JSONCoding.jsonlEncoder(iso8601Dates: false)
        return try encoder.encode(document)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
