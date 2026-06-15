import Foundation

/// Post-write validation outcome for one XMP target.
public struct XMPMergeValidationResult: Codable, Sendable, Equatable {
    public var targetXMPPath: String
    public var valid: Bool
    public var expectedFlatKeywords: [String]
    public var expectedHierarchicalKeywords: [String]
    public var preservedFlatKeywords: [String]
    public var preservedHierarchicalKeywords: [String]
    public var unmanagedContentPreserved: Bool
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case targetXMPPath = "target_xmp_path"
        case valid
        case expectedFlatKeywords = "expected_flat_keywords"
        case expectedHierarchicalKeywords = "expected_hierarchical_keywords"
        case preservedFlatKeywords = "preserved_flat_keywords"
        case preservedHierarchicalKeywords = "preserved_hierarchical_keywords"
        case unmanagedContentPreserved = "unmanaged_content_preserved"
        case errors
    }

    public init(
        targetXMPPath: String,
        valid: Bool,
        expectedFlatKeywords: [String],
        expectedHierarchicalKeywords: [String],
        preservedFlatKeywords: [String],
        preservedHierarchicalKeywords: [String],
        unmanagedContentPreserved: Bool,
        errors: [SidecarError]
    ) {
        self.targetXMPPath = targetXMPPath
        self.valid = valid
        self.expectedFlatKeywords = expectedFlatKeywords
        self.expectedHierarchicalKeywords = expectedHierarchicalKeywords
        self.preservedFlatKeywords = preservedFlatKeywords
        self.preservedHierarchicalKeywords = preservedHierarchicalKeywords
        self.unmanagedContentPreserved = unmanagedContentPreserved
        self.errors = errors
    }
}

/// Validates expected keyword additions and semantic preservation after an XMP merge.
public struct XMPMergeValidator {
    public init() {}

    /// Compare pre-write and re-read post-write snapshots according to FR2-028.
    public func validate(
        plan: XMPChangePlan,
        preWriteSnapshot: XMPMetadataSnapshot,
        postWriteSnapshot: XMPMetadataSnapshot
    ) -> XMPMergeValidationResult {
        let expectedFlat = plan.flatKeywordsToAdd.map(\.term)
        let expectedHierarchical = plan.hierarchicalKeywordsToAdd.map(\.term)
        var errors: [SidecarError] = []

        let postFlatKeys = normalizedSet(postWriteSnapshot.flatKeywords)
        let postHierarchicalKeys = normalizedSet(postWriteSnapshot.hierarchicalKeywords)

        let missingFlat = expectedFlat.filter {
            !postFlatKeys.contains(KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)))
        }
        if !missingFlat.isEmpty {
            errors.append(validationError("Expected flat XMP keyword(s) missing after write: \(missingFlat.joined(separator: ", "))"))
        }

        let missingHierarchical = expectedHierarchical.filter {
            !postHierarchicalKeys.contains(KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)))
        }
        if !missingHierarchical.isEmpty {
            errors.append(validationError(
                "Expected hierarchical XMP keyword(s) missing after write: \(missingHierarchical.joined(separator: ", "))"
            ))
        }

        let missingPreFlat = preWriteSnapshot.flatKeywords.filter {
            !postFlatKeys.contains(KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)))
        }
        if !missingPreFlat.isEmpty {
            errors.append(validationError(
                "Pre-existing flat XMP keyword(s) were not preserved: \(missingPreFlat.joined(separator: ", "))"
            ))
        }

        let missingPreHierarchical = preWriteSnapshot.hierarchicalKeywords.filter {
            !postHierarchicalKeys.contains(KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)))
        }
        if !missingPreHierarchical.isEmpty {
            errors.append(validationError(
                "Pre-existing hierarchical XMP keyword(s) were not preserved: \(missingPreHierarchical.joined(separator: ", "))"
            ))
        }

        let unmanagedPreserved = !preWriteSnapshot.exists
            || preWriteSnapshot.unmanagedContentFingerprint == postWriteSnapshot.unmanagedContentFingerprint
        if !unmanagedPreserved {
            errors.append(validationError("Pre-existing unmanaged XMP/RDF content was not semantically preserved."))
        }

        return XMPMergeValidationResult(
            targetXMPPath: postWriteSnapshot.targetPath,
            valid: errors.isEmpty,
            expectedFlatKeywords: expectedFlat,
            expectedHierarchicalKeywords: expectedHierarchical,
            preservedFlatKeywords: preWriteSnapshot.flatKeywords.filter { !missingPreFlat.contains($0) },
            preservedHierarchicalKeywords: preWriteSnapshot.hierarchicalKeywords.filter {
                !missingPreHierarchical.contains($0)
            },
            unmanagedContentPreserved: unmanagedPreserved,
            errors: errors
        )
    }

    private func normalizedSet(_ keywords: [String]) -> Set<String> {
        Set(keywords.map { KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)) })
    }

    private func validationError(_ message: String) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .write, message: message, recoverable: true)
    }
}
