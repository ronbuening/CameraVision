import Foundation

/// One stored perceptual-quality assessment, tagged with its model-input role and prompt contract.
public struct QualityAssessmentRecord: Sendable, Equatable {
    public enum Criterion: String, CaseIterable, Hashable, Sendable {
        case focus
        case composition
        case exposureAndTone = "exposure_and_tone"
        case lightingAndColor = "lighting_and_color"
        case detailAndTexture = "detail_and_texture"
        case subjectBackgroundRelationship = "subject_background_relationship"
        case momentOrExpression = "moment_or_expression"
        case poseExpressionOrMoment = "pose_expression_or_moment"
        case technicalCleanliness = "technical_cleanliness"
    }

    public enum Level: String, Sendable {
        case problem
        case acceptable
        case strong
        case unrated
    }

    public enum Confidence: String, Comparable, Sendable {
        case low
        case medium
        case high

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }
    }

    public let role: ModelInputRole
    public let promptVersion: String
    public let criteria: [Criterion: Level]
    public let overall: Level
    public let strengths: [String]
    public let concerns: [String]
    public let confidence: Confidence

    public init(
        role: ModelInputRole,
        promptVersion: String,
        criteria: [Criterion: Level],
        overall: Level,
        strengths: [String],
        concerns: [String],
        confidence: Confidence
    ) {
        self.role = role
        self.promptVersion = promptVersion
        self.criteria = criteria
        self.overall = overall
        self.strengths = strengths
        self.concerns = concerns
        self.confidence = confidence
    }
}

/// Stable diagnostic category for tolerant quality-assessment extraction.
public enum QualityExtractionIssueCode: String, Sendable {
    case malformedBlock = "malformed_block"
    case unknownCriterion = "unknown_criterion"
    case missingOverall = "missing_overall"
    case invalidLevel = "invalid_level"
}

/// Non-fatal problem found while decoding a stored quality assessment.
public enum QualityExtractionIssue: Sendable, Equatable {
    case malformedBlock
    case unknownCriterion(String)
    case missingOverall
    case invalidLevel(field: String, value: String)

    public var code: QualityExtractionIssueCode {
        switch self {
        case .malformedBlock: .malformedBlock
        case .unknownCriterion: .unknownCriterion
        case .missingOverall: .missingOverall
        case .invalidLevel: .invalidLevel
        }
    }
}

/// Quality assessments and tolerant-decode diagnostics for one resolved source image.
public struct QualityExtractionResult: Sendable, Equatable {
    public let sourceImagePath: String
    public let records: [QualityAssessmentRecord]
    public let issues: [QualityExtractionIssue]

    public init(
        sourceImagePath: String,
        records: [QualityAssessmentRecord],
        issues: [QualityExtractionIssue]
    ) {
        self.sourceImagePath = sourceImagePath
        self.records = records
        self.issues = issues
    }
}

/// Tolerantly decodes stored `quality_assessment` blocks without performing model or filesystem work.
public enum QualityAssessmentExtractor {
    public static func extract(from inputs: [ResolvedRawSidecarInput]) -> [QualityExtractionResult] {
        inputs.map { extract(from: $0) }
    }

    public static func extract(from input: ResolvedRawSidecarInput) -> QualityExtractionResult {
        let sourceImagePath = input.sourcePath?.standardizedFileURL.path ?? input.document.sidecar.source.path
        var documents = [(path: input.sidecarPath, document: input.document)]
        if let qualityPath = input.qualitySidecarPath,
            let qualityDocument = input.qualityDocument,
            qualityPath.standardizedFileURL != input.sidecarPath.standardizedFileURL
        {
            documents.append((qualityPath, qualityDocument))
        }
        documents.sort {
            if $0.document.sidecar.createdAt == $1.document.sidecar.createdAt {
                return $0.path.standardizedFileURL.path < $1.path.standardizedFileURL.path
            }
            return $0.document.sidecar.createdAt < $1.document.sidecar.createdAt
        }

        var newestByRole: [ModelInputRole: QualityAssessmentRecord] = [:]
        var issues: [QualityExtractionIssue] = []
        for (_, document) in documents {
            let requiresAssessment = document.sidecar.runConfiguration.taskProfile != .tagging
            for run in document.sidecar.modelRuns {
                guard let response = run.parsedResponseJSON?.objectValue else {
                    if requiresAssessment {
                        issues.append(.malformedBlock)
                    }
                    continue
                }
                guard let assessmentValue = response["quality_assessment"] else {
                    if requiresAssessment {
                        issues.append(.malformedBlock)
                    }
                    continue
                }
                guard let assessment = assessmentValue.objectValue else {
                    issues.append(.malformedBlock)
                    continue
                }
                let decoded = decode(assessment, role: run.inputRole, promptVersion: run.promptVersion)
                issues.append(contentsOf: decoded.issues)
                if let record = decoded.record {
                    newestByRole[run.inputRole] = record
                }
            }
        }

        return QualityExtractionResult(
            sourceImagePath: sourceImagePath,
            records: ModelInputRole.allCases.compactMap { newestByRole[$0] },
            issues: issues
        )
    }

    private static let nonCriterionFields: Set<String> = [
        "overall_effectiveness",
        "overall_subject_quality",
        "strengths",
        "concerns",
        "confidence",
    ]

    private static func decode(
        _ assessment: [String: JSONValue],
        role: ModelInputRole,
        promptVersion: String
    ) -> (record: QualityAssessmentRecord?, issues: [QualityExtractionIssue]) {
        var issues: [QualityExtractionIssue] = []
        var criteria: [QualityAssessmentRecord.Criterion: QualityAssessmentRecord.Level] = [:]
        for key in assessment.keys.sorted() where !nonCriterionFields.contains(key) {
            guard let criterion = QualityAssessmentRecord.Criterion(rawValue: key) else {
                issues.append(.unknownCriterion(key))
                continue
            }
            guard let value = assessment[key]?.stringValue,
                let level = QualityAssessmentRecord.Level(rawValue: value)
            else {
                issues.append(.invalidLevel(field: key, value: displayValue(assessment[key])))
                continue
            }
            criteria[criterion] = level
        }

        let overallField = role == .wholeImage ? "overall_effectiveness" : "overall_subject_quality"
        guard let overallValue = assessment[overallField] else {
            issues.append(.missingOverall)
            return (nil, issues)
        }
        guard let overallText = overallValue.stringValue,
            let overall = QualityAssessmentRecord.Level(rawValue: overallText)
        else {
            issues.append(.invalidLevel(field: overallField, value: displayValue(overallValue)))
            return (nil, issues)
        }

        guard let confidenceValue = assessment["confidence"],
            let confidenceText = confidenceValue.stringValue,
            let confidence = QualityAssessmentRecord.Confidence(rawValue: confidenceText)
        else {
            issues.append(.invalidLevel(field: "confidence", value: displayValue(assessment["confidence"])))
            return (nil, issues)
        }

        let strengths = notes(in: assessment, field: "strengths", issues: &issues)
        let concerns = notes(in: assessment, field: "concerns", issues: &issues)
        return (
            QualityAssessmentRecord(
                role: role,
                promptVersion: promptVersion,
                criteria: criteria,
                overall: overall,
                strengths: strengths,
                concerns: concerns,
                confidence: confidence
            ),
            issues
        )
    }

    private static func notes(
        in assessment: [String: JSONValue],
        field: String,
        issues: inout [QualityExtractionIssue]
    ) -> [String] {
        guard let values = assessment[field]?.arrayValue else {
            issues.append(.malformedBlock)
            return []
        }
        let notes = values.compactMap(\.stringValue)
        if notes.count != values.count {
            issues.append(.malformedBlock)
        }
        return notes
    }

    private static func displayValue(_ value: JSONValue?) -> String {
        guard let value else {
            return "<missing>"
        }
        switch value {
        case .string(let string): return string
        case .number(let number): return String(number)
        case .bool(let bool): return String(bool)
        case .null: return "null"
        case .object: return "<object>"
        case .array: return "<array>"
        }
    }
}
