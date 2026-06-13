import Foundation

/// Execution status for one planned XMP target.
public enum XMPTargetPlanStatus: String, Codable, Sendable, Equatable {
    case planned
    case failed
}

/// Reason a source member did not contribute candidates to a scoped group.
public enum XMPSourceMemberSkipReason: String, Codable, Sendable, Equatable {
    case pairScopeRawOnly = "pair_scope_raw_only"
    case pairScopeJPEGOnly = "pair_scope_jpeg_only"
}

/// Source-image member recorded in a dry-run XMP change plan.
public struct SourceMemberPlan: Codable, Sendable, Equatable {
    public var sourcePath: String?
    public var sourceRelativePath: String
    public var sourceFileName: String
    public var sourceType: SupportedImageType
    public var sourceSidecarPath: String
    public var sourceSidecarRelativePath: String?
    public var sourceIdentityStatus: SourceIdentityStatus
    public var pairKind: XMPSourcePairKind
    public var selected: Bool
    public var skipReason: XMPSourceMemberSkipReason?
    public var flatKeywordContributionCount: Int
    public var hierarchicalKeywordContributionCount: Int

    enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case sourceRelativePath = "source_relative_path"
        case sourceFileName = "source_file_name"
        case sourceType = "source_type"
        case sourceSidecarPath = "source_sidecar_path"
        case sourceSidecarRelativePath = "source_sidecar_relative_path"
        case sourceIdentityStatus = "source_identity_status"
        case pairKind = "pair_kind"
        case selected
        case skipReason = "skip_reason"
        case flatKeywordContributionCount = "flat_keyword_contribution_count"
        case hierarchicalKeywordContributionCount = "hierarchical_keyword_contribution_count"
    }

    public init(
        sourcePath: String?,
        sourceRelativePath: String,
        sourceFileName: String,
        sourceType: SupportedImageType,
        sourceSidecarPath: String,
        sourceSidecarRelativePath: String?,
        sourceIdentityStatus: SourceIdentityStatus,
        pairKind: XMPSourcePairKind,
        selected: Bool,
        skipReason: XMPSourceMemberSkipReason?,
        flatKeywordContributionCount: Int,
        hierarchicalKeywordContributionCount: Int
    ) {
        self.sourcePath = sourcePath
        self.sourceRelativePath = sourceRelativePath
        self.sourceFileName = sourceFileName
        self.sourceType = sourceType
        self.sourceSidecarPath = sourceSidecarPath
        self.sourceSidecarRelativePath = sourceSidecarRelativePath
        self.sourceIdentityStatus = sourceIdentityStatus
        self.pairKind = pairKind
        self.selected = selected
        self.skipReason = skipReason
        self.flatKeywordContributionCount = flatKeywordContributionCount
        self.hierarchicalKeywordContributionCount = hierarchicalKeywordContributionCount
    }
}

/// Keyword addition planned for one managed XMP keyword bag.
public struct PlannedKeyword: Codable, Sendable, Equatable {
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

/// Backup intent recorded before the backup manager milestone exists.
public struct BackupPlan: Codable, Sendable, Equatable {
    public var backupSidecars: Bool
    public var backupRequiredBeforeMerge: Bool
    public var conflictPolicy: XMPConflictPolicy

    enum CodingKeys: String, CodingKey {
        case backupSidecars = "backup_sidecars"
        case backupRequiredBeforeMerge = "backup_required_before_merge"
        case conflictPolicy = "conflict_policy"
    }

    public init(backupSidecars: Bool, backupRequiredBeforeMerge: Bool, conflictPolicy: XMPConflictPolicy) {
        self.backupSidecars = backupSidecars
        self.backupRequiredBeforeMerge = backupRequiredBeforeMerge
        self.conflictPolicy = conflictPolicy
    }
}

/// Validation intent recorded before owned XMP parsing and writing land.
public struct ValidationPlan: Codable, Sendable, Equatable {
    public var validateReadableXMP: Bool
    public var validateKeywordAdditions: Bool
    public var validateExistingKeywordPreservation: Bool
    public var validateUnmanagedContentPreservation: Bool

    enum CodingKeys: String, CodingKey {
        case validateReadableXMP = "validate_readable_xmp"
        case validateKeywordAdditions = "validate_keyword_additions"
        case validateExistingKeywordPreservation = "validate_existing_keyword_preservation"
        case validateUnmanagedContentPreservation = "validate_unmanaged_content_preservation"
    }

    public init(
        validateReadableXMP: Bool,
        validateKeywordAdditions: Bool,
        validateExistingKeywordPreservation: Bool,
        validateUnmanagedContentPreservation: Bool
    ) {
        self.validateReadableXMP = validateReadableXMP
        self.validateKeywordAdditions = validateKeywordAdditions
        self.validateExistingKeywordPreservation = validateExistingKeywordPreservation
        self.validateUnmanagedContentPreservation = validateUnmanagedContentPreservation
    }

    public static let phase2Default = ValidationPlan(
        validateReadableXMP: true,
        validateKeywordAdditions: true,
        validateExistingKeywordPreservation: true,
        validateUnmanagedContentPreservation: true
    )
}

/// Planned changes for one target XMP sidecar.
public struct XMPChangePlan: Codable, Sendable, Equatable {
    public var status: XMPTargetPlanStatus
    public var targetXMPPath: String
    public var targetRelativePath: String
    public var pairScope: XMPPairScope
    public var sourceMembers: [SourceMemberPlan]
    public var flatKeywordsToAdd: [PlannedKeyword]
    public var hierarchicalKeywordsToAdd: [PlannedKeyword]
    public var skippedCandidates: [SkippedCandidate]
    public var candidateExtractionIssues: [CandidateExtractionIssue]
    public var sourceVerificationWarnings: [SidecarError]
    public var groupWarnings: [SidecarError]
    public var existingPolicy: XMPConflictPolicy
    public var backupPlan: BackupPlan
    public var validationPlan: ValidationPlan
    public var preview: XMPWritePreview?
    public var failures: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case status
        case targetXMPPath = "target_xmp_path"
        case targetRelativePath = "target_relative_path"
        case pairScope = "pair_scope"
        case sourceMembers = "source_members"
        case flatKeywordsToAdd = "flat_keywords_to_add"
        case hierarchicalKeywordsToAdd = "hierarchical_keywords_to_add"
        case skippedCandidates = "skipped_candidates"
        case candidateExtractionIssues = "candidate_extraction_issues"
        case sourceVerificationWarnings = "source_verification_warnings"
        case groupWarnings = "group_warnings"
        case existingPolicy = "existing_policy"
        case backupPlan = "backup_plan"
        case validationPlan = "validation_plan"
        case preview
        case failures
    }

    public init(
        status: XMPTargetPlanStatus,
        targetXMPPath: String,
        targetRelativePath: String,
        pairScope: XMPPairScope,
        sourceMembers: [SourceMemberPlan],
        flatKeywordsToAdd: [PlannedKeyword],
        hierarchicalKeywordsToAdd: [PlannedKeyword],
        skippedCandidates: [SkippedCandidate],
        candidateExtractionIssues: [CandidateExtractionIssue],
        sourceVerificationWarnings: [SidecarError],
        groupWarnings: [SidecarError],
        existingPolicy: XMPConflictPolicy,
        backupPlan: BackupPlan,
        validationPlan: ValidationPlan,
        preview: XMPWritePreview? = nil,
        failures: [SidecarError]
    ) {
        self.status = status
        self.targetXMPPath = targetXMPPath
        self.targetRelativePath = targetRelativePath
        self.pairScope = pairScope
        self.sourceMembers = sourceMembers
        self.flatKeywordsToAdd = flatKeywordsToAdd
        self.hierarchicalKeywordsToAdd = hierarchicalKeywordsToAdd
        self.skippedCandidates = skippedCandidates
        self.candidateExtractionIssues = candidateExtractionIssues
        self.sourceVerificationWarnings = sourceVerificationWarnings
        self.groupWarnings = groupWarnings
        self.existingPolicy = existingPolicy
        self.backupPlan = backupPlan
        self.validationPlan = validationPlan
        self.preview = preview
        self.failures = failures
    }
}

/// Raw-sidecar input failure carried into the dry-run document.
public struct XMPChangePlanInputFailure: Codable, Sendable, Equatable {
    public var sidecarPath: String
    public var relativePath: String?
    public var error: SidecarError

    enum CodingKeys: String, CodingKey {
        case sidecarPath = "sidecar_path"
        case relativePath = "relative_path"
        case error
    }

    public init(sidecarPath: String, relativePath: String?, error: SidecarError) {
        self.sidecarPath = sidecarPath
        self.relativePath = relativePath
        self.error = error
    }
}

/// Top-level dry-run document for Phase 2 XMP change planning.
public struct XMPChangePlanDocument: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var dryRun: Bool
    public var targetPlans: [XMPChangePlan]
    public var inputFailures: [XMPChangePlanInputFailure]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case dryRun = "dry_run"
        case targetPlans = "target_plans"
        case inputFailures = "input_failures"
    }

    public init(
        schemaVersion: String = XMPExportSchemaIdentifiers.changePlan,
        dryRun: Bool,
        targetPlans: [XMPChangePlan],
        inputFailures: [XMPChangePlanInputFailure]
    ) {
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
        self.targetPlans = targetPlans
        self.inputFailures = inputFailures
    }
}

/// Builds Phase 2 dry-run change plans from resolved raw sidecars and extracted candidates.
public struct XMPChangePlanner {
    private let naming: XMPNaming
    private let groupResolver: SameBaseNameGroupResolver

    public init(
        naming: XMPNaming = XMPNaming(),
        groupResolver: SameBaseNameGroupResolver = SameBaseNameGroupResolver()
    ) {
        self.naming = naming
        self.groupResolver = groupResolver
    }

    /// Build the shared plan used by dry-run output and future write execution.
    public func plan(
        inputBatch: RawJSONSidecarInputBatch,
        extractionResults: [CandidateExtractionResult],
        configuration: ResolvedXMPExportConfiguration
    ) -> XMPChangePlanDocument {
        let extractionBySidecar = Dictionary(uniqueKeysWithValues: extractionResults.map {
            ($0.sourceSidecar, $0)
        })
        var entries: [XMPNamingEntry] = []
        var inputFailures = inputBatch.failures.map { failure in
            XMPChangePlanInputFailure(
                sidecarPath: failure.sidecarPath.standardizedFileURL.path,
                relativePath: failure.relativePath,
                error: failure.error
            )
        }

        for input in inputBatch.inputs {
            do {
                let destination = try naming.destination(for: input, configuration: configuration)
                entries.append(XMPNamingEntry(input: input, destination: destination))
            } catch let error as SidecarError {
                inputFailures.append(
                    XMPChangePlanInputFailure(
                        sidecarPath: input.sidecarPath.standardizedFileURL.path,
                        relativePath: input.relativePath,
                        error: error
                    )
                )
            } catch {
                inputFailures.append(
                    XMPChangePlanInputFailure(
                        sidecarPath: input.sidecarPath.standardizedFileURL.path,
                        relativePath: input.relativePath,
                        error: SidecarError(
                            code: .validationFailed,
                            stage: .write,
                            message: "Unable to derive XMP plan for \(input.sidecarPath.path): \(error.localizedDescription)",
                            recoverable: true
                        )
                    )
                )
            }
        }

        let groups = groupResolver.resolve(
            entries: entries,
            extractionResults: extractionBySidecar,
            pairScope: configuration.pairScope
        )
        return XMPChangePlanDocument(
            dryRun: configuration.dryRun,
            targetPlans: groups.map { targetPlan(for: $0, configuration: configuration) },
            inputFailures: inputFailures.sorted { comparePaths($0.sidecarPath, $1.sidecarPath) }
        )
    }

    private func targetPlan(
        for selectedGroup: SameBaseNameSelectedGroup,
        configuration: ResolvedXMPExportConfiguration
    ) -> XMPChangePlan {
        let selectedSidecars = Set(selectedGroup.selectedMembers.map { $0.input.sidecarPath.standardizedFileURL.path })
        let sourceMembers = selectedGroup.group.members.map { member in
            sourceMemberPlan(
                for: member,
                selected: selectedSidecars.contains(member.input.sidecarPath.standardizedFileURL.path),
                pairScope: configuration.pairScope
            )
        }
        let flatKeywords = plannedKeywords(from: selectedGroup.selectedMembers, keyPath: \.flatKeywords)
        let hierarchicalKeywords = plannedKeywords(from: selectedGroup.selectedMembers, keyPath: \.hierarchicalKeywords)
        let selectedResults = selectedGroup.selectedMembers.map(\.extractionResult)
        let sourceVerificationWarnings = selectedGroup.group.members.flatMap(\.input.warnings)

        return XMPChangePlan(
            status: selectedGroup.failures.isEmpty ? .planned : .failed,
            targetXMPPath: selectedGroup.group.targetXMPPath,
            targetRelativePath: selectedGroup.group.targetRelativePath,
            pairScope: configuration.pairScope,
            sourceMembers: sourceMembers,
            flatKeywordsToAdd: flatKeywords,
            hierarchicalKeywordsToAdd: hierarchicalKeywords,
            skippedCandidates: selectedResults.flatMap(\.skippedCandidates),
            candidateExtractionIssues: selectedResults.flatMap(\.issues),
            sourceVerificationWarnings: sourceVerificationWarnings,
            groupWarnings: selectedGroup.warnings,
            existingPolicy: configuration.xmpConflictPolicy,
            backupPlan: BackupPlan(
                backupSidecars: configuration.backupSidecars,
                backupRequiredBeforeMerge: configuration.xmpConflictPolicy == .backupAndMerge,
                conflictPolicy: configuration.xmpConflictPolicy
            ),
            // The planner records validation intent; the export pipeline turns
            // these flags into post-write snapshot and fingerprint checks.
            validationPlan: .phase2Default,
            failures: selectedGroup.failures
        )
    }

    private func sourceMemberPlan(
        for member: SameBaseNameGroupMember,
        selected: Bool,
        pairScope: XMPPairScope
    ) -> SourceMemberPlan {
        let source = member.input.document.sidecar.source
        return SourceMemberPlan(
            sourcePath: member.input.sourcePath?.standardizedFileURL.path,
            sourceRelativePath: source.relativePath,
            sourceFileName: source.fileName,
            sourceType: source.detectedType,
            sourceSidecarPath: member.input.sidecarPath.standardizedFileURL.path,
            sourceSidecarRelativePath: member.input.relativePath,
            sourceIdentityStatus: member.input.sourceIdentityStatus,
            pairKind: member.pairKind,
            selected: selected,
            skipReason: selected ? nil : skipReason(pairScope: pairScope),
            flatKeywordContributionCount: selected ? member.extractionResult.flatKeywords.count : 0,
            hierarchicalKeywordContributionCount: selected ? member.extractionResult.hierarchicalKeywords.count : 0
        )
    }

    private func skipReason(pairScope: XMPPairScope) -> XMPSourceMemberSkipReason? {
        switch pairScope {
        case .union:
            return nil
        case .rawOnly:
            return .pairScopeRawOnly
        case .jpegOnly:
            return .pairScopeJPEGOnly
        }
    }

    private func plannedKeywords(
        from members: [SameBaseNameGroupMember],
        keyPath: KeyPath<CandidateExtractionResult, [ExportableKeyword]>
    ) -> [PlannedKeyword] {
        var keywords: [PlannedKeyword] = []
        var indexByKey: [String: Int] = [:]

        for member in members {
            for keyword in member.extractionResult[keyPath: keyPath] {
                if let index = indexByKey[keyword.normalizedKey] {
                    keywords[index].candidates.append(contentsOf: keyword.candidates)
                } else {
                    indexByKey[keyword.normalizedKey] = keywords.count
                    keywords.append(
                        PlannedKeyword(
                            term: keyword.term,
                            normalizedKey: keyword.normalizedKey,
                            candidates: keyword.candidates
                        )
                    )
                }
            }
        }

        return keywords
    }
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
