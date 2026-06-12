import Foundation

/// Phase 1 model-response fields that can produce Phase 2 keyword candidates.
///
/// The raw string values are the JSON property names recorded in
/// `model_runs[*].parsed_response_json` and are preserved in later provenance.
public enum CandidateSourceField: String, Codable, CaseIterable, Hashable, Sendable {
    case genreOrPhotographyType = "genre_or_photography_type"
    case species
    case mainSubjects = "main_subjects"
    case secondarySubjects = "secondary_subjects"
    case sceneContext = "scene_context"
    case habitatOrSetting = "habitat_or_setting"
    case behaviorOrAction = "behavior_or_action"
    case proposedKeywords = "proposed_keywords"
}

/// Origin information for one candidate term inside a Phase 1 raw sidecar.
public struct CandidateProvenance: Codable, Sendable, Equatable {
    public var sourceField: CandidateSourceField
    public var inputRole: ModelInputRole
    public var sourceSidecar: String
    public var sourceImage: String
    public var modelRunIndex: Int

    enum CodingKeys: String, CodingKey {
        case sourceField = "source_field"
        case inputRole = "input_role"
        case sourceSidecar = "source_sidecar"
        case sourceImage = "source_image"
        case modelRunIndex = "model_run_index"
    }

    public init(
        sourceField: CandidateSourceField,
        inputRole: ModelInputRole,
        sourceSidecar: String,
        sourceImage: String,
        modelRunIndex: Int
    ) {
        self.sourceField = sourceField
        self.inputRole = inputRole
        self.sourceSidecar = sourceSidecar
        self.sourceImage = sourceImage
        self.modelRunIndex = modelRunIndex
    }
}

/// Syntactically valid candidate extracted before policy filtering.
public struct ExtractedCandidate: Codable, Sendable, Equatable {
    public var term: String
    public var normalizedTerm: String
    public var confidence: XMPMinimumConfidence
    public var evidence: String?
    public var provenance: CandidateProvenance

    enum CodingKeys: String, CodingKey {
        case term
        case normalizedTerm = "normalized_term"
        case confidence
        case evidence
        case provenance
    }

    public init(
        term: String,
        normalizedTerm: String,
        confidence: XMPMinimumConfidence,
        evidence: String?,
        provenance: CandidateProvenance
    ) {
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.confidence = confidence
        self.evidence = evidence
        self.provenance = provenance
    }
}

/// Keyword text accepted for a future XMP write plan.
///
/// `candidates` retains every contributing model term, including duplicates
/// that collapsed into this keyword after normalization and case-insensitive
/// de-duplication.
public struct ExportableKeyword: Codable, Sendable, Equatable {
    public var term: String
    public var normalizedKey: String
    public var candidates: [ExtractedCandidate]

    enum CodingKeys: String, CodingKey {
        case term
        case normalizedKey = "normalized_key"
        case candidates
    }

    public init(term: String, normalizedKey: String, candidates: [ExtractedCandidate]) {
        self.term = term
        self.normalizedKey = normalizedKey
        self.candidates = candidates
    }
}

/// Machine-readable reason a candidate or accepted keyword is absent from an output set.
public enum SkippedCandidateReason: String, Codable, Equatable, Sendable {
    case belowConfidenceThreshold = "below_confidence_threshold"
    case specificTagPolicy = "specific_tag_policy"
    case containsHierarchySeparator = "contains_hierarchy_separator"
    case emptyAfterNormalization = "empty_after_normalization"
    case duplicate
    case disabledFlatExport = "disabled_flat_export"
    case disabledHierarchicalExport = "disabled_hierarchical_export"
}

/// Diagnostic for a candidate or keyword that Milestone 2 did not export.
public struct SkippedCandidate: Codable, Sendable, Equatable {
    public var reason: SkippedCandidateReason
    public var candidate: ExtractedCandidate?
    public var term: String?
    public var normalizedTerm: String?

    enum CodingKeys: String, CodingKey {
        case reason
        case candidate
        case term
        case normalizedTerm = "normalized_term"
    }

    public init(
        reason: SkippedCandidateReason,
        candidate: ExtractedCandidate?,
        term: String? = nil,
        normalizedTerm: String? = nil
    ) {
        self.reason = reason
        self.candidate = candidate
        self.term = term ?? candidate?.term
        self.normalizedTerm = normalizedTerm ?? candidate?.normalizedTerm
    }
}

/// Non-fatal issue found while traversing parsed model-response JSON.
public struct CandidateExtractionIssue: Codable, Sendable, Equatable {
    public var reason: CandidateExtractionIssueReason
    public var sourceSidecar: String
    public var sourceImage: String
    public var modelRunIndex: Int?
    public var sourceField: CandidateSourceField?
    public var candidateIndex: Int?
    public var message: String

    enum CodingKeys: String, CodingKey {
        case reason
        case sourceSidecar = "source_sidecar"
        case sourceImage = "source_image"
        case modelRunIndex = "model_run_index"
        case sourceField = "source_field"
        case candidateIndex = "candidate_index"
        case message
    }

    public init(
        reason: CandidateExtractionIssueReason,
        sourceSidecar: String,
        sourceImage: String,
        modelRunIndex: Int?,
        sourceField: CandidateSourceField?,
        candidateIndex: Int?,
        message: String
    ) {
        self.reason = reason
        self.sourceSidecar = sourceSidecar
        self.sourceImage = sourceImage
        self.modelRunIndex = modelRunIndex
        self.sourceField = sourceField
        self.candidateIndex = candidateIndex
        self.message = message
    }
}

/// Stable categories for malformed candidate JSON that should not abort a batch.
public enum CandidateExtractionIssueReason: String, Codable, Equatable, Sendable {
    case missingParsedResponse = "missing_parsed_response"
    case malformedParsedResponse = "malformed_parsed_response"
    case malformedCandidateField = "malformed_candidate_field"
    case malformedCandidate = "malformed_candidate"
    case malformedEvidence = "malformed_evidence"
}

/// Candidate extraction output for one resolved raw sidecar input.
public struct CandidateExtractionResult: Codable, Sendable, Equatable {
    public var sourceSidecar: String
    public var sourceImage: String
    public var extractedCandidates: [ExtractedCandidate]
    public var flatKeywords: [ExportableKeyword]
    public var hierarchicalKeywords: [ExportableKeyword]
    public var skippedCandidates: [SkippedCandidate]
    public var issues: [CandidateExtractionIssue]

    enum CodingKeys: String, CodingKey {
        case sourceSidecar = "source_sidecar"
        case sourceImage = "source_image"
        case extractedCandidates = "extracted_candidates"
        case flatKeywords = "flat_keywords"
        case hierarchicalKeywords = "hierarchical_keywords"
        case skippedCandidates = "skipped_candidates"
        case issues
    }

    public init(
        sourceSidecar: String,
        sourceImage: String,
        extractedCandidates: [ExtractedCandidate],
        flatKeywords: [ExportableKeyword],
        hierarchicalKeywords: [ExportableKeyword],
        skippedCandidates: [SkippedCandidate],
        issues: [CandidateExtractionIssue]
    ) {
        self.sourceSidecar = sourceSidecar
        self.sourceImage = sourceImage
        self.extractedCandidates = extractedCandidates
        self.flatKeywords = flatKeywords
        self.hierarchicalKeywords = hierarchicalKeywords
        self.skippedCandidates = skippedCandidates
        self.issues = issues
    }
}

/// Normalizes model-supplied keyword text before filtering and de-duplication.
public enum KeywordTextNormalizer {
    /// Apply Phase 2 keyword normalization: NFC, trim, and internal whitespace collapse.
    public static func normalize(_ term: String) -> String {
        let nfc = term.precomposedStringWithCanonicalMapping
        return nfc
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    /// Case-insensitive key used for de-duplication after normalization.
    public static func deduplicationKey(for normalizedTerm: String) -> String {
        normalizedTerm.lowercased()
    }
}

/// Conservative Phase 2 heuristic for excluding specific tags before XMP export.
public struct SpecificTagPolicy {
    public init() {}

    /// Return true when a candidate should be skipped by FR2-019 specific-tag policy.
    public func shouldExclude(_ candidate: ExtractedCandidate, speciesKeysForRun: Set<String>) -> Bool {
        if candidate.provenance.sourceField == .species {
            return true
        }
        if speciesKeysForRun.contains(KeywordTextNormalizer.deduplicationKey(for: candidate.normalizedTerm)) {
            return true
        }
        if looksLikeLatinBinomial(candidate.normalizedTerm) {
            return true
        }
        if looksLikeCapitalizedProperName(candidate.normalizedTerm) {
            return true
        }
        if looksLikeNamedPlacePersonOrEvent(candidate.normalizedTerm) {
            return true
        }
        if evidenceIndicatesExactIdentification(candidate.evidence) {
            return true
        }
        return false
    }

    private func looksLikeLatinBinomial(_ term: String) -> Bool {
        let words = alphabeticWords(in: term)
        guard words.count == 2 || words.count == 3 else {
            return false
        }
        guard words.allSatisfy({ $0.count >= 3 }) else {
            return false
        }

        let first = words[0]
        let remaining = words.dropFirst()
        let firstLooksGenus = first.first?.isUppercase == true && first.dropFirst().allSatisfy(\.isLowercase)
        return firstLooksGenus && remaining.allSatisfy { $0.allSatisfy(\.isLowercase) }
    }

    private func looksLikeCapitalizedProperName(_ term: String) -> Bool {
        let words = alphabeticWords(in: term)
        guard words.count >= 2 else {
            return false
        }
        let capitalizedCount = words.filter { $0.first?.isUppercase == true }.count
        return capitalizedCount >= 2
    }

    private func looksLikeNamedPlacePersonOrEvent(_ term: String) -> Bool {
        let words = alphabeticWords(in: term)
        guard words.contains(where: { $0.first?.isUppercase == true }) else {
            return false
        }

        let lowercased = term.lowercased()
        let namedSignals = [
            " national park",
            " state park",
            " county",
            " city",
            " lake ",
            " river ",
            " mount ",
            " mountain",
            " trail",
            " festival",
            " parade",
            " marathon",
            " world cup",
            " super bowl",
            " olympics"
        ]
        let padded = " \(lowercased) "
        return namedSignals.contains { padded.contains($0) }
    }

    private func evidenceIndicatesExactIdentification(_ evidence: String?) -> Bool {
        guard let evidence else {
            return false
        }
        let lowercased = evidence.lowercased()
        let exactSignals = [
            "exact identification",
            "exact id",
            "identified as",
            "identifies it as",
            "identifies the",
            "species-level",
            "specific species",
            "field marks confirm",
            "confirmed by",
            "distinctive markings identify",
            "recognizable as",
            "known individual",
            "named person",
            "named place",
            "landmark"
        ]
        return exactSignals.contains { lowercased.contains($0) }
    }

    private func alphabeticWords(in term: String) -> [String] {
        term.split { character in
            !character.isLetter
        }.map(String.init)
    }
}

/// Extracts Phase 2 keyword candidates from resolved Phase 1 raw sidecars.
public struct CandidateExtractor {
    private let specificTagPolicy: SpecificTagPolicy

    public init(specificTagPolicy: SpecificTagPolicy = SpecificTagPolicy()) {
        self.specificTagPolicy = specificTagPolicy
    }

    /// Extract candidate results for every resolved raw sidecar input.
    public func extract(
        from inputs: [ResolvedRawSidecarInput],
        configuration: ResolvedXMPExportConfiguration
    ) -> [CandidateExtractionResult] {
        inputs.map { extract(from: $0, configuration: configuration) }
    }

    /// Extract candidate results for one resolved raw sidecar input.
    public func extract(
        from input: ResolvedRawSidecarInput,
        configuration: ResolvedXMPExportConfiguration
    ) -> CandidateExtractionResult {
        let sourceSidecar = input.sidecarPath.standardizedFileURL.path
        let sourceImage = input.sourcePath?.standardizedFileURL.path ?? input.document.sidecar.source.path
        let speciesKeysByRun = speciesKeysByRun(for: input)
        var extractedCandidates: [ExtractedCandidate] = []
        var skippedCandidates: [SkippedCandidate] = []
        var issues: [CandidateExtractionIssue] = []
        var acceptedKeywords: [ExportableKeyword] = []
        var acceptedIndexByKey: [String: Int] = [:]

        for (modelRunIndex, modelRun) in input.document.sidecar.modelRuns.enumerated() {
            guard let parsedResponseJSON = modelRun.parsedResponseJSON else {
                issues.append(issue(
                    .missingParsedResponse,
                    input: input,
                    sourceImage: sourceImage,
                    modelRunIndex: modelRunIndex,
                    message: "Model run has no parsed_response_json."
                ))
                continue
            }
            guard let responseObject = parsedResponseJSON.objectValue else {
                issues.append(issue(
                    .malformedParsedResponse,
                    input: input,
                    sourceImage: sourceImage,
                    modelRunIndex: modelRunIndex,
                    message: "Model run parsed_response_json is not a JSON object."
                ))
                continue
            }

            for field in CandidateSourceField.allCases {
                guard let fieldValue = responseObject[field.rawValue] else {
                    continue
                }
                guard let candidateValues = fieldValue.arrayValue else {
                    issues.append(issue(
                        .malformedCandidateField,
                        input: input,
                        sourceImage: sourceImage,
                        modelRunIndex: modelRunIndex,
                        sourceField: field,
                        message: "Candidate field \(field.rawValue) is not an array."
                    ))
                    continue
                }

                for (candidateIndex, candidateValue) in candidateValues.enumerated() {
                    guard let candidateObject = candidateValue.objectValue else {
                        issues.append(issue(
                            .malformedCandidate,
                            input: input,
                            sourceImage: sourceImage,
                            modelRunIndex: modelRunIndex,
                            sourceField: field,
                            candidateIndex: candidateIndex,
                            message: "Candidate entry is not an object."
                        ))
                        continue
                    }
                    guard let term = candidateObject["term"]?.stringValue else {
                        issues.append(issue(
                            .malformedCandidate,
                            input: input,
                            sourceImage: sourceImage,
                            modelRunIndex: modelRunIndex,
                            sourceField: field,
                            candidateIndex: candidateIndex,
                            message: "Candidate is missing a string term."
                        ))
                        continue
                    }
                    guard
                        let confidenceText = candidateObject["confidence"]?.stringValue,
                        let confidence = XMPMinimumConfidence(rawValue: confidenceText)
                    else {
                        issues.append(issue(
                            .malformedCandidate,
                            input: input,
                            sourceImage: sourceImage,
                            modelRunIndex: modelRunIndex,
                            sourceField: field,
                            candidateIndex: candidateIndex,
                            message: "Candidate is missing a valid confidence band."
                        ))
                        continue
                    }

                    let evidence: String?
                    if let evidenceValue = candidateObject["evidence"] {
                        if let evidenceText = evidenceValue.stringValue {
                            evidence = evidenceText
                        } else if evidenceValue == .null {
                            evidence = nil
                        } else {
                            evidence = nil
                            issues.append(issue(
                                .malformedEvidence,
                                input: input,
                                sourceImage: sourceImage,
                                modelRunIndex: modelRunIndex,
                                sourceField: field,
                                candidateIndex: candidateIndex,
                                message: "Candidate evidence is not a string."
                            ))
                        }
                    } else {
                        evidence = nil
                    }

                    let candidate = ExtractedCandidate(
                        term: term,
                        normalizedTerm: KeywordTextNormalizer.normalize(term),
                        confidence: confidence,
                        evidence: evidence,
                        provenance: CandidateProvenance(
                            sourceField: field,
                            inputRole: modelRun.inputRole,
                            sourceSidecar: sourceSidecar,
                            sourceImage: sourceImage,
                            modelRunIndex: modelRunIndex
                        )
                    )
                    extractedCandidates.append(candidate)

                    guard !candidate.normalizedTerm.isEmpty else {
                        skippedCandidates.append(SkippedCandidate(reason: .emptyAfterNormalization, candidate: candidate))
                        continue
                    }
                    guard !candidate.normalizedTerm.contains("|") else {
                        skippedCandidates.append(SkippedCandidate(reason: .containsHierarchySeparator, candidate: candidate))
                        continue
                    }
                    guard candidate.confidence >= configuration.minConfidence else {
                        skippedCandidates.append(SkippedCandidate(reason: .belowConfidenceThreshold, candidate: candidate))
                        continue
                    }

                    let runKey = ModelRunExtractionKey(sourceSidecar: sourceSidecar, modelRunIndex: modelRunIndex)
                    if !configuration.allowSpecificTags,
                       specificTagPolicy.shouldExclude(
                        candidate,
                        speciesKeysForRun: speciesKeysByRun[runKey] ?? []
                       ) {
                        skippedCandidates.append(SkippedCandidate(reason: .specificTagPolicy, candidate: candidate))
                        continue
                    }

                    let key = KeywordTextNormalizer.deduplicationKey(for: candidate.normalizedTerm)
                    if let acceptedIndex = acceptedIndexByKey[key] {
                        acceptedKeywords[acceptedIndex].candidates.append(candidate)
                        skippedCandidates.append(SkippedCandidate(reason: .duplicate, candidate: candidate))
                    } else {
                        acceptedIndexByKey[key] = acceptedKeywords.count
                        acceptedKeywords.append(
                            ExportableKeyword(
                                term: candidate.normalizedTerm,
                                normalizedKey: key,
                                candidates: [candidate]
                            )
                        )
                    }
                }
            }
        }

        let flatKeywords: [ExportableKeyword]
        if configuration.writeFlatKeywords {
            flatKeywords = acceptedKeywords
        } else {
            flatKeywords = []
            skippedCandidates.append(contentsOf: disabledSkips(
                for: acceptedKeywords,
                reason: .disabledFlatExport
            ))
        }

        let hierarchicalKeywords: [ExportableKeyword]
        if configuration.writeHierarchicalKeywords {
            // FR2-007a: Phase 2 writes one-level hierarchical entries identical to flat terms.
            hierarchicalKeywords = acceptedKeywords
        } else {
            hierarchicalKeywords = []
            skippedCandidates.append(contentsOf: disabledSkips(
                for: acceptedKeywords,
                reason: .disabledHierarchicalExport
            ))
        }

        return CandidateExtractionResult(
            sourceSidecar: sourceSidecar,
            sourceImage: sourceImage,
            extractedCandidates: extractedCandidates,
            flatKeywords: flatKeywords,
            hierarchicalKeywords: hierarchicalKeywords,
            skippedCandidates: skippedCandidates,
            issues: issues
        )
    }

    private func speciesKeysByRun(
        for input: ResolvedRawSidecarInput
    ) -> [ModelRunExtractionKey: Set<String>] {
        let sourceSidecar = input.sidecarPath.standardizedFileURL.path
        var result: [ModelRunExtractionKey: Set<String>] = [:]
        for (modelRunIndex, modelRun) in input.document.sidecar.modelRuns.enumerated() {
            guard
                let responseObject = modelRun.parsedResponseJSON?.objectValue,
                let speciesValues = responseObject[CandidateSourceField.species.rawValue]?.arrayValue
            else {
                continue
            }

            let keys = speciesValues.compactMap { value -> String? in
                guard let term = value.objectValue?["term"]?.stringValue else {
                    return nil
                }
                let normalized = KeywordTextNormalizer.normalize(term)
                guard !normalized.isEmpty else {
                    return nil
                }
                return KeywordTextNormalizer.deduplicationKey(for: normalized)
            }
            result[ModelRunExtractionKey(sourceSidecar: sourceSidecar, modelRunIndex: modelRunIndex)] = Set(keys)
        }
        return result
    }

    private func disabledSkips(
        for keywords: [ExportableKeyword],
        reason: SkippedCandidateReason
    ) -> [SkippedCandidate] {
        keywords.map { keyword in
            SkippedCandidate(
                reason: reason,
                candidate: keyword.candidates.first,
                term: keyword.term,
                normalizedTerm: keyword.term
            )
        }
    }

    private func issue(
        _ reason: CandidateExtractionIssueReason,
        input: ResolvedRawSidecarInput,
        sourceImage: String,
        modelRunIndex: Int?,
        sourceField: CandidateSourceField? = nil,
        candidateIndex: Int? = nil,
        message: String
    ) -> CandidateExtractionIssue {
        CandidateExtractionIssue(
            reason: reason,
            sourceSidecar: input.sidecarPath.standardizedFileURL.path,
            sourceImage: sourceImage,
            modelRunIndex: modelRunIndex,
            sourceField: sourceField,
            candidateIndex: candidateIndex,
            message: message
        )
    }
}

private struct ModelRunExtractionKey: Hashable {
    var sourceSidecar: String
    var modelRunIndex: Int
}
