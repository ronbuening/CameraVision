import Foundation

struct QualityGradingPlanApplier {
    func apply(
        to plan: inout XMPChangePlan,
        inputs: [ResolvedRawSidecarInput],
        grading: ResolvedQualityGradingConfiguration,
        writeFlatKeywords: Bool,
        writeHierarchicalKeywords: Bool,
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)?
    ) {
        guard grading.enabled else {
            return
        }

        let quality = qualityAssessments(from: inputs)
        let policy = grading.policy
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
            return
        }

        plan.qualityTier = grade.tier
        plan.qualityExplanation = qualityExplanation(
            grade: grade,
            ungradedReason: nil,
            records: quality.recordsByRole,
            issues: quality.issues
        )
        if policy.writeKeywords {
            if writeFlatKeywords {
                plan.flatKeywordsToAdd = mergingQualityKeywords(
                    plan.flatKeywordsToAdd,
                    terms: flatQualityKeywords(from: grade.keywords)
                )
            }
            if writeHierarchicalKeywords {
                plan.hierarchicalKeywordsToAdd = mergingQualityKeywords(
                    plan.hierarchicalKeywordsToAdd,
                    terms: hierarchicalQualityKeywords(from: grade.keywords)
                )
            }
        }

        guard grade.rating != nil || grade.label != nil || grade.urgency != nil || grade.flag != nil else {
            return
        }
        guard let snapshotReader else {
            plan.status = .failed
            plan.failures.append(
                qualityPlanningError(
                    "Quality grading requires a prepared XMP snapshot reader for \(plan.targetXMPPath)."
                ))
            return
        }

        do {
            let snapshot = try snapshotReader(plan.targetXMPPath)
            let stamped: TrustedStampedScalars
            if grading.conflictPolicy == .refresh {
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
                policy: grading.conflictPolicy
            )
            plan.labelWrite = scalarWrite(
                field: XMPManagedScalar.label.qualifiedPropertyName,
                desiredValue: grade.label,
                existingValue: snapshot.label,
                stampedValue: stamped.label,
                policy: grading.conflictPolicy
            )

            if let desiredUrgency = grade.urgency.map(String.init), let desiredLabel = grade.label {
                let resultingLabel = projectedValue(existingValue: snapshot.label, write: plan.labelWrite)
                if resultingLabel == desiredLabel {
                    plan.urgencyWrite = scalarWrite(
                        field: XMPManagedScalar.urgency.qualifiedPropertyName,
                        desiredValue: desiredUrgency,
                        existingValue: snapshot.urgency,
                        stampedValue: stamped.urgency,
                        policy: grading.conflictPolicy
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
                    policy: grading.conflictPolicy
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
    }

    private func qualityAssessments(from inputs: [ResolvedRawSidecarInput]) -> QualityAssessmentSelection {
        var contributorByPath: [String: QualityDocumentContributor] = [:]
        for input in inputs {
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
