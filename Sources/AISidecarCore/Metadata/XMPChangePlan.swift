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
    public var sourceSidecarPath: String?
    public var sourceSidecarRelativePath: String?
    public var sourceIdentityStatus: SourceIdentityStatus
    public var pairKind: XMPSourcePairKind
    public var selected: Bool
    public var skipReason: XMPSourceMemberSkipReason?
    public var flatKeywordContributionCount: Int
    public var hierarchicalKeywordContributionCount: Int
    public var qualitySidecarPath: String?

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
        case qualitySidecarPath = "quality_sidecar_path"
    }

    public init(
        sourcePath: String?,
        sourceRelativePath: String,
        sourceFileName: String,
        sourceType: SupportedImageType,
        sourceSidecarPath: String?,
        sourceSidecarRelativePath: String?,
        sourceIdentityStatus: SourceIdentityStatus,
        pairKind: XMPSourcePairKind,
        selected: Bool,
        skipReason: XMPSourceMemberSkipReason?,
        flatKeywordContributionCount: Int,
        hierarchicalKeywordContributionCount: Int,
        qualitySidecarPath: String? = nil
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
        self.qualitySidecarPath = qualitySidecarPath
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

/// One planned write to a managed XMP scalar property.
public struct PlannedScalarWrite: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable {
        case write
        case skipExisting = "skip_existing"
        case overwrite
    }

    public let field: String
    public let plannedValue: String
    public let existingValue: String?
    public let action: Action

    enum CodingKeys: String, CodingKey {
        case field
        case plannedValue = "planned_value"
        case existingValue = "existing_value"
        case action
    }

    public init(field: String, plannedValue: String, existingValue: String?, action: Action) {
        self.field = field
        self.plannedValue = plannedValue
        self.existingValue = existingValue
        self.action = action
    }
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
    public var ratingWrite: PlannedScalarWrite?
    public var labelWrite: PlannedScalarWrite?
    public var urgencyWrite: PlannedScalarWrite?
    public var pickWrite: PlannedScalarWrite?
    public var goodWrite: PlannedScalarWrite?
    public var qualityExplanation: [String]?
    public var qualityTier: QualityTier?

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
        case ratingWrite = "rating_write"
        case labelWrite = "label_write"
        case urgencyWrite = "urgency_write"
        case pickWrite = "pick_write"
        case goodWrite = "good_write"
        case qualityExplanation = "quality_explanation"
        case qualityTier = "quality_tier"
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
        failures: [SidecarError],
        ratingWrite: PlannedScalarWrite? = nil,
        labelWrite: PlannedScalarWrite? = nil,
        urgencyWrite: PlannedScalarWrite? = nil,
        pickWrite: PlannedScalarWrite? = nil,
        goodWrite: PlannedScalarWrite? = nil,
        qualityExplanation: [String]? = nil,
        qualityTier: QualityTier? = nil
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
        self.ratingWrite = ratingWrite
        self.labelWrite = labelWrite
        self.urgencyWrite = urgencyWrite
        self.pickWrite = pickWrite
        self.goodWrite = goodWrite
        self.qualityExplanation = qualityExplanation
        self.qualityTier = qualityTier
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

    /// Planned-failure count for batch exit derivation when no export report
    /// exists (dry runs): unresolvable inputs plus target plans that already
    /// carry failures. Mirrors `XMPExportReport.failedCount`.
    public var failedCount: Int {
        targetPlans.filter { $0.status == .failed || !$0.failures.isEmpty }.count
            + inputFailures.count
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
        configuration: ResolvedXMPExportConfiguration,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)? = nil
    ) -> XMPChangePlanDocument {
        var entries: [XMPNamingEntry] = []
        var inputFailures = inputBatch.failures.map { failure in
            XMPChangePlanInputFailure(
                sidecarPath: failure.sidecarPath.standardizedFileURL.path,
                relativePath: failure.relativePath,
                error: failure.error
            )
        }
        var extractionBySidecar: [String: CandidateExtractionResult] = [:]
        extractionBySidecar.reserveCapacity(extractionResults.count)
        for result in extractionResults {
            guard extractionBySidecar[result.sourceSidecar] == nil else {
                inputFailures.append(
                    XMPChangePlanInputFailure(
                        sidecarPath: result.sourceSidecar,
                        relativePath: nil,
                        error: SidecarError(
                            code: .validationFailed,
                            stage: .write,
                            message: "Duplicate source sidecar in input batch: \(result.sourceSidecar)",
                            recoverable: true
                        )
                    )
                )
                continue
            }
            extractionBySidecar[result.sourceSidecar] = result
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
                            message:
                                "Unable to derive XMP plan for \(input.sidecarPath.path): \(error.localizedDescription)",
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
            targetPlans: groups.map {
                targetPlan(
                    for: $0,
                    configuration: configuration,
                    snapshotReader: snapshotReader
                )
            },
            inputFailures: inputFailures.sorted { comparePaths($0.sidecarPath, $1.sidecarPath) }
        )
    }

    private func targetPlan(
        for selectedGroup: SameBaseNameSelectedGroup,
        configuration: ResolvedXMPExportConfiguration,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)?
    ) -> XMPChangePlan {
        let selectedSidecars = Set(selectedGroup.selectedMembers.map { $0.input.sidecarPath.standardizedFileURL.path })
        let sourceMembers = selectedGroup.group.members.map { member in
            sourceMemberPlan(
                for: member,
                selected: selectedSidecars.contains(member.input.sidecarPath.standardizedFileURL.path),
                pairScope: configuration.pairScope,
                includesQualityProvenance: configuration.qualityGrading.enabled
            )
        }
        var flatKeywords = plannedKeywords(from: selectedGroup.selectedMembers, keyPath: \.flatKeywords)
        var hierarchicalKeywords = plannedKeywords(from: selectedGroup.selectedMembers, keyPath: \.hierarchicalKeywords)
        let selectedResults = selectedGroup.selectedMembers.map(\.extractionResult)
        let sourceVerificationWarnings = selectedGroup.group.members.flatMap(\.input.warnings)

        var plan = XMPChangePlan(
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

        guard configuration.qualityGrading.enabled else {
            return plan
        }

        let quality = qualityAssessments(from: selectedGroup.selectedMembers)
        let policy = configuration.qualityGrading.policy
        let whole = quality.recordsByRole[.wholeImage]
        let subject = quality.recordsByRole[.subjectIsolated]
        let ungradedReason = QualityTierDeriver.ungradedReason(
            whole: whole,
            subject: subject,
            policy: policy
        )
        guard let grade = QualityTierDeriver.grade(whole: whole, subject: subject, policy: policy) else {
            plan.qualityExplanation = qualityExplanation(
                grade: nil,
                ungradedReason: ungradedReason ?? .noRecords,
                records: quality.recordsByRole,
                issues: quality.issues
            )
            return plan
        }

        plan.qualityTier = grade.tier
        plan.qualityExplanation = qualityExplanation(
            grade: grade,
            ungradedReason: nil,
            records: quality.recordsByRole,
            issues: quality.issues
        )
        if policy.writeKeywords {
            if configuration.writeFlatKeywords {
                flatKeywords = mergingQualityKeywords(flatKeywords, terms: flatQualityKeywords(from: grade.keywords))
            }
            if configuration.writeHierarchicalKeywords {
                hierarchicalKeywords = mergingQualityKeywords(
                    hierarchicalKeywords,
                    terms: hierarchicalQualityKeywords(from: grade.keywords)
                )
            }
            plan.flatKeywordsToAdd = flatKeywords
            plan.hierarchicalKeywordsToAdd = hierarchicalKeywords
        }

        guard grade.rating != nil || grade.label != nil || grade.urgency != nil || grade.flag != nil else {
            return plan
        }
        guard let snapshotReader else {
            plan.status = .failed
            plan.failures.append(
                qualityPlanningError(
                    "Quality grading requires a prepared XMP snapshot reader for \(plan.targetXMPPath)."
                ))
            return plan
        }

        do {
            let snapshot = try snapshotReader(plan.targetXMPPath)
            let stamped: TrustedStampedScalars
            if configuration.qualityGrading.conflictPolicy == .refresh {
                stamped = trustedStampedScalars(
                    from: quality.contributors,
                    targetXMPPath: plan.targetXMPPath,
                    explanation: &plan.qualityExplanation
                )
            } else {
                stamped = TrustedStampedScalars()
            }
            plan.ratingWrite = scalarWrite(
                field: XMPManagedScalar.rating.qualifiedPropertyName,
                desiredValue: grade.rating.map(String.init),
                existingValue: snapshot.rating,
                stampedValue: stamped.rating,
                policy: configuration.qualityGrading.conflictPolicy
            )
            plan.labelWrite = scalarWrite(
                field: XMPManagedScalar.label.qualifiedPropertyName,
                desiredValue: grade.label,
                existingValue: snapshot.label,
                stampedValue: stamped.label,
                policy: configuration.qualityGrading.conflictPolicy
            )

            if let desiredUrgency = grade.urgency.map(String.init), let desiredLabel = grade.label {
                let resultingLabel = projectedValue(existingValue: snapshot.label, write: plan.labelWrite)
                if resultingLabel == desiredLabel {
                    plan.urgencyWrite = scalarWrite(
                        field: XMPManagedScalar.urgency.qualifiedPropertyName,
                        desiredValue: desiredUrgency,
                        existingValue: snapshot.urgency,
                        stampedValue: stamped.urgency,
                        policy: configuration.qualityGrading.conflictPolicy
                    )
                } else {
                    plan.urgencyWrite = PlannedScalarWrite(
                        field: XMPManagedScalar.urgency.qualifiedPropertyName,
                        plannedValue: desiredUrgency,
                        existingValue: snapshot.urgency,
                        action: .skipExisting
                    )
                    plan.qualityExplanation?.append(
                        "urgency suppressed: resulting label does not match the planned label \(desiredLabel)"
                    )
                }
            }

            if let desiredFlag = grade.flag {
                plan.pickWrite = scalarWrite(
                    field: XMPManagedScalar.pick.qualifiedPropertyName,
                    desiredValue: desiredFlag.pickValue,
                    existingValue: snapshot.pick,
                    stampedValue: stamped.pick,
                    policy: configuration.qualityGrading.conflictPolicy
                )
                // xmpDM:good mirrors xmpDM:pick's action so Lightroom's flag
                // pair can never be split by per-scalar conflict resolution.
                plan.goodWrite = plan.pickWrite.map { pickWrite in
                    PlannedScalarWrite(
                        field: XMPManagedScalar.good.qualifiedPropertyName,
                        plannedValue: desiredFlag.goodValue,
                        existingValue: snapshot.good,
                        action: pickWrite.action
                    )
                }
            }
        } catch {
            plan.status = .failed
            plan.failures.append(
                qualityPlanningError(
                    "Unable to read XMP scalars for quality grading at \(plan.targetXMPPath): "
                        + error.localizedDescription
                ))
        }
        return plan
    }

    private func sourceMemberPlan(
        for member: SameBaseNameGroupMember,
        selected: Bool,
        pairScope: XMPPairScope,
        includesQualityProvenance: Bool
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
            hierarchicalKeywordContributionCount: selected ? member.extractionResult.hierarchicalKeywords.count : 0,
            qualitySidecarPath: selected && includesQualityProvenance
                ? distinctQualitySidecarPath(for: member.input)
                : nil
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

    private func distinctQualitySidecarPath(for input: ResolvedRawSidecarInput) -> String? {
        guard let qualitySidecarPath = input.qualitySidecarPath?.standardizedFileURL.path,
            qualitySidecarPath != input.sidecarPath.standardizedFileURL.path
        else {
            return nil
        }
        return qualitySidecarPath
    }

    private func qualityAssessments(from members: [SameBaseNameGroupMember]) -> QualityAssessmentSelection {
        var contributorByPath: [String: QualityDocumentContributor] = [:]
        for member in members {
            let input = member.input
            let primaryPath = input.sidecarPath.standardizedFileURL.path
            contributorByPath[primaryPath] = QualityDocumentContributor(
                path: primaryPath,
                document: input.document
            )
            if let qualityPath = input.qualitySidecarPath?.standardizedFileURL.path,
                let qualityDocument = input.qualityDocument
            {
                contributorByPath[qualityPath] = QualityDocumentContributor(
                    path: qualityPath,
                    document: qualityDocument
                )
            }
        }

        let contributors = contributorByPath.values.sorted {
            if $0.document.sidecar.createdAt == $1.document.sidecar.createdAt {
                return comparePaths($0.path, $1.path)
            }
            return $0.document.sidecar.createdAt < $1.document.sidecar.createdAt
        }
        var recordsByRole: [ModelInputRole: QualityAssessmentRecord] = [:]
        var issues: [QualityExtractionIssue] = []
        for contributor in contributors {
            let extraction = QualityAssessmentExtractor.extract(
                from: ResolvedRawSidecarInput(
                    sidecarPath: URL(fileURLWithPath: contributor.path),
                    document: contributor.document,
                    sourcePath: URL(fileURLWithPath: contributor.document.sidecar.source.path),
                    sourceIdentityStatus: .matched,
                    relativePath: nil,
                    warnings: []
                ))
            issues.append(contentsOf: extraction.issues)
            for record in extraction.records {
                recordsByRole[record.role] = record
            }
        }
        return QualityAssessmentSelection(
            contributors: contributors,
            recordsByRole: recordsByRole,
            issues: issues
        )
    }

    private func qualityExplanation(
        grade: QualityGrade?,
        ungradedReason: QualityUngradedReason?,
        records: [ModelInputRole: QualityAssessmentRecord],
        issues: [QualityExtractionIssue]
    ) -> [String] {
        var explanation: [String]
        if let grade {
            explanation = ["tier=\(grade.tier.rawValue)"]
        } else {
            explanation = ["ungraded reason=\((ungradedReason ?? .noRecords).rawValue)"]
        }

        if let primary = records[.wholeImage] ?? records[.subjectIsolated] {
            let strongCount = primary.criteria.values.filter { $0 == .strong }.count
            let problemCount = primary.criteria.values.filter { $0 == .problem }.count
            explanation.append("counts strong=\(strongCount) problem=\(problemCount)")
            explanation.append("confidence=\(primary.confidence.rawValue)")
        }
        for role in ModelInputRole.allCases {
            guard let record = records[role] else {
                continue
            }
            explanation.append("source role=\(role.rawValue) prompt_version=\(record.promptVersion)")
        }
        for code in issues.map({ $0.code.rawValue }).sorted() {
            explanation.append("extraction_issue=\(code)")
        }
        if let grade {
            explanation.append(contentsOf: grade.explanation.map { "rule=\($0)" })
        }
        return explanation
    }

    private func hierarchicalQualityKeywords(from paths: [String]) -> [String] {
        let normalizedPaths = paths.compactMap { path -> String? in
            let components = path.split(separator: "|", omittingEmptySubsequences: false)
                .map { KeywordTextNormalizer.normalize(String($0)) }
            guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            return components.joined(separator: "|")
        }
        return normalizedSafeKeywords(normalizedPaths)
    }

    private func flatQualityKeywords(from paths: [String]) -> [String] {
        let flattened = paths.map { path in
            path.split(separator: "|", omittingEmptySubsequences: false)
                .map { KeywordTextNormalizer.normalize(String($0)) }
                .joined(separator: " ")
        }
        return normalizedSafeKeywords(flattened)
    }

    private func normalizedSafeKeywords(_ terms: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for term in terms {
            let normalized = KeywordTextNormalizer.normalize(term)
            guard !normalized.isEmpty, !KeywordSafetyPolicy.isUnsafeKeyword(normalized) else {
                continue
            }
            let key = KeywordTextNormalizer.deduplicationKey(for: normalized)
            if seen.insert(key).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    private func mergingQualityKeywords(_ existing: [PlannedKeyword], terms: [String]) -> [PlannedKeyword] {
        var merged = existing
        var seen = Set(existing.map(\.normalizedKey))
        for term in terms {
            let key = KeywordTextNormalizer.deduplicationKey(for: term)
            guard seen.insert(key).inserted else {
                continue
            }
            merged.append(PlannedKeyword(term: term, normalizedKey: key, candidates: []))
        }
        return merged
    }

    private func trustedStampedScalars(
        from contributors: [QualityDocumentContributor],
        targetXMPPath: String,
        explanation: inout [String]?
    ) -> TrustedStampedScalars {
        var stamps: [RawSidecarExportStamp.Contents] = []
        for contributor in contributors {
            let hasStamp = ((try? contributor.document.jsonValue())?.objectValue)?[RawSidecarExportStamp.key] != nil
            guard hasStamp else {
                continue
            }
            guard let contents = RawSidecarExportStamp.contents(from: contributor.document) else {
                explanation?.append("refresh provenance unavailable: malformed export stamp")
                return TrustedStampedScalars()
            }
            stamps.append(contents)
        }
        guard let newestDate = stamps.map(\.exportedAt).max() else {
            return TrustedStampedScalars()
        }
        let newest = stamps.filter { $0.exportedAt == newestDate }
        let standardizedTarget = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        guard
            newest.allSatisfy({
                URL(fileURLWithPath: $0.targetXMPPath).standardizedFileURL.path == standardizedTarget
            })
        else {
            explanation?.append("refresh provenance unavailable: newest export stamp targets another XMP sidecar")
            return TrustedStampedScalars()
        }

        let rating = trustedTiedValue(newest.map(\.rating), field: "rating", explanation: &explanation)
        let label = trustedTiedValue(newest.map(\.label), field: "label", explanation: &explanation)
        let urgency = trustedTiedValue(newest.map(\.urgency), field: "urgency", explanation: &explanation)
        let pick = trustedTiedValue(newest.map(\.pick), field: "pick", explanation: &explanation)
        return TrustedStampedScalars(rating: rating, label: label, urgency: urgency, pick: pick)
    }

    private func trustedTiedValue(
        _ values: [String?],
        field: String,
        explanation: inout [String]?
    ) -> String? {
        guard let first = values.first else {
            return nil
        }
        guard values.dropFirst().allSatisfy({ $0 == first }) else {
            explanation?.append("refresh provenance unavailable: newest export stamps disagree on \(field)")
            return nil
        }
        return first
    }

    private func scalarWrite(
        field: String,
        desiredValue: String?,
        existingValue: String?,
        stampedValue: String?,
        policy: ScalarConflictPolicy
    ) -> PlannedScalarWrite? {
        guard let desiredValue else {
            return nil
        }
        let action: PlannedScalarWrite.Action
        switch policy {
        case .preserve:
            action = existingValue == nil ? .write : .skipExisting
        case .refresh:
            if existingValue == nil {
                action = .write
            } else if existingValue == desiredValue {
                action = .skipExisting
            } else if existingValue == stampedValue {
                action = .overwrite
            } else {
                action = .skipExisting
            }
        case .overwrite:
            action = .overwrite
        }
        return PlannedScalarWrite(
            field: field,
            plannedValue: desiredValue,
            existingValue: existingValue,
            action: action
        )
    }

    private func projectedValue(existingValue: String?, write: PlannedScalarWrite?) -> String? {
        switch write?.action {
        case .write, .overwrite:
            return write?.plannedValue
        case .skipExisting, nil:
            return existingValue
        }
    }

    private func qualityPlanningError(_ message: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: message,
            recoverable: true
        )
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

private struct QualityDocumentContributor {
    var path: String
    var document: RawJSONSidecarDocument
}

private struct QualityAssessmentSelection {
    var contributors: [QualityDocumentContributor]
    var recordsByRole: [ModelInputRole: QualityAssessmentRecord]
    var issues: [QualityExtractionIssue]
}

private struct TrustedStampedScalars {
    var rating: String?
    var label: String?
    var urgency: String?
    var pick: String?

    init(rating: String? = nil, label: String? = nil, urgency: String? = nil, pick: String? = nil) {
        self.rating = rating
        self.label = label
        self.urgency = urgency
        self.pick = pick
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
