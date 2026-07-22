import Foundation

/// Read-only quality details prepared for one asset in a review session.
///
/// Stored assessment records and tolerant-decode diagnostics retain Core's
/// extraction order. Grading fields come from the session's persisted XMP plan
/// and remain available before current raw-sidecar contributors are re-read.
public struct ReviewAssetQualityPresentation: Sendable, Equatable {
    public let records: [QualityAssessmentRecord]
    public let issueDiagnostics: [String]
    public let tier: QualityTier?
    public let explanations: [String]
    public let ungradedReason: String?

    public init(
        records: [QualityAssessmentRecord],
        issueDiagnostics: [String],
        tier: QualityTier?,
        explanations: [String],
        ungradedReason: String?
    ) {
        self.records = records
        self.issueDiagnostics = issueDiagnostics
        self.tier = tier
        self.explanations = explanations
        self.ungradedReason = ungradedReason
    }
}

/// Current quality presentation and recoverable read diagnostics for a review session.
public struct ReviewQualityLoadResult: Sendable, Equatable {
    public let presentationByAssetID: [String: ReviewAssetQualityPresentation]
    public let diagnostics: [String]

    public init(
        presentationByAssetID: [String: ReviewAssetQualityPresentation],
        diagnostics: [String]
    ) {
        self.presentationByAssetID = presentationByAssetID
        self.diagnostics = diagnostics
    }
}

/// Resolves the current raw-sidecar contributors used by apply-time quality grading.
///
/// Loading deliberately uses `resolveCurrentSidecarPair` so it neither hashes
/// source images nor imposes a second identity gate. The stateless value can be
/// moved to a detached task while a GUI first presents the session's frozen plan.
public struct ReviewQualityLoader: Sendable, Equatable {
    public init() {}

    /// Project only persisted grading-plan fields without reading raw sidecars.
    public func plannedPresentation(
        for sessionDocument: NormalizationSessionDocument
    ) -> [String: ReviewAssetQualityPresentation] {
        presentation(
            sourceAssets: sessionDocument.sourceAssets,
            xmpWritePlans: sessionDocument.xmpWritePlans,
            extractionByAssetID: [:]
        )
    }

    /// Re-read current contributor pairs and merge their assessments with the persisted grading plan.
    ///
    /// Contributor records are visited in stored session order. Once a standardized
    /// pair path has been consumed, later references cannot replace its extraction;
    /// this preserves the same first-result ownership used by review before this seam
    /// moved into Core.
    public func load(for sessionDocument: NormalizationSessionDocument) -> ReviewQualityLoadResult {
        let resolver = RawJSONSidecarInputResolver()
        var extractionByAssetID: [String: QualityExtractionResult] = [:]
        var diagnostics: [String] = []
        var consumedSidecarPaths: Set<String> = []

        for record in sessionDocument.sourceAISidecars {
            let referencePath = URL(fileURLWithPath: record.sidecarPath).standardizedFileURL.path
            guard !consumedSidecarPaths.contains(referencePath) else { continue }

            let batch = resolver.resolveCurrentSidecarPair(at: record.sidecarPath)
            diagnostics.append(
                contentsOf: batch.failures.map {
                    "\($0.error.code.rawValue): \($0.error.message)"
                }
            )
            for input in batch.inputs {
                consumedSidecarPaths.insert(input.sidecarPath.standardizedFileURL.path)
                if let qualityPath = input.qualitySidecarPath {
                    consumedSidecarPaths.insert(qualityPath.standardizedFileURL.path)
                }
                if extractionByAssetID[record.sourceAssetID] == nil {
                    extractionByAssetID[record.sourceAssetID] = QualityAssessmentExtractor.extract(from: input)
                }
            }
        }

        return ReviewQualityLoadResult(
            presentationByAssetID: presentation(
                sourceAssets: sessionDocument.sourceAssets,
                xmpWritePlans: sessionDocument.xmpWritePlans,
                extractionByAssetID: extractionByAssetID
            ),
            diagnostics: diagnostics
        )
    }

    private func presentation(
        sourceAssets: [NormalizationSourceAsset],
        xmpWritePlans: [NormalizedXMPWritePlan],
        extractionByAssetID: [String: QualityExtractionResult]
    ) -> [String: ReviewAssetQualityPresentation] {
        struct PlannedQuality {
            var tier: QualityTier?
            var explanations: [String]
            var ungradedReason: String?
        }

        var planBySource: [String: PlannedQuality] = [:]
        for writePlan in xmpWritePlans {
            let plan = writePlan.xmpChangePlan
            let explanations = plan.qualityExplanation ?? []
            let ungradedReason = plan.ungradedReasonExplanation
            guard plan.qualityTier != nil || ungradedReason != nil || !explanations.isEmpty else { continue }

            let planned = PlannedQuality(
                tier: plan.qualityTier,
                explanations: explanations,
                ungradedReason: ungradedReason
            )
            for member in plan.sourceMembers {
                planBySource[sourceKey(path: member.sourcePath, relativePath: member.sourceRelativePath)] = planned
            }
        }

        var result: [String: ReviewAssetQualityPresentation] = [:]
        for asset in sourceAssets {
            let key = sourceKey(path: asset.sourcePath, relativePath: asset.sourceRelativePath)
            let extraction = extractionByAssetID[asset.assetID]
            let planned = planBySource[key]
            let records = extraction?.records ?? []
            let issues = extraction?.issues.map(issueDiagnostic) ?? []
            guard !records.isEmpty || !issues.isEmpty || planned != nil else { continue }

            result[asset.assetID] = ReviewAssetQualityPresentation(
                records: records,
                issueDiagnostics: issues,
                tier: planned?.tier,
                explanations: planned?.explanations ?? [],
                ungradedReason: planned?.ungradedReason
            )
        }
        return result
    }

    private func sourceKey(path: String?, relativePath: String) -> String {
        guard let path, !path.isEmpty else { return "relative:\(relativePath)" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func issueDiagnostic(_ issue: QualityExtractionIssue) -> String {
        switch issue {
        case .malformedBlock:
            QualityExtractionIssueCode.malformedBlock.rawValue
        case .unknownCriterion(let criterion):
            "\(QualityExtractionIssueCode.unknownCriterion.rawValue): \(criterion)"
        case .missingOverall:
            QualityExtractionIssueCode.missingOverall.rawValue
        case .invalidLevel(let field, let value):
            "\(QualityExtractionIssueCode.invalidLevel.rawValue): \(field)=\(value)"
        }
    }
}
