import Foundation

/// Deterministic quality bucket used by all grading output channels.
public enum QualityTier: String, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case reject
    case belowAverage = "below_average"
    case neutral
    case good
    case excellent

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    fileprivate var demoted: Self {
        switch self {
        case .excellent: .good
        case .good: .neutral
        case .neutral: .belowAverage
        case .belowAverage: .reject
        case .reject: .reject
        }
    }

    private var rank: Int {
        switch self {
        case .reject: 0
        case .belowAverage: 1
        case .neutral: 2
        case .good: 3
        case .excellent: 4
        }
    }
}

/// User-adjustable mapping from a derived quality tier to metadata-facing channels.
public struct QualityGradingPolicy: Sendable, Equatable {
    public var minimumConfidence: QualityAssessmentRecord.Confidence
    public var writeRating: Bool
    public var writeLabel: Bool
    public var writeUrgency: Bool
    public var writeKeywords: Bool
    public var rejectAsMinusOne: Bool
    public var perCriterionProblemKeywords: Bool
    public var keywordRoot: String
    public var ratingMap: [QualityTier: Int]
    public var labelMap: [QualityTier: String]
    public var urgencyMap: [QualityTier: Int]

    public init(
        minimumConfidence: QualityAssessmentRecord.Confidence = .medium,
        writeRating: Bool = true,
        writeLabel: Bool = true,
        writeUrgency: Bool = true,
        writeKeywords: Bool = true,
        rejectAsMinusOne: Bool = false,
        perCriterionProblemKeywords: Bool = false,
        keywordRoot: String = "AI Quality",
        ratingMap: [QualityTier: Int] = [
            .reject: 1,
            .belowAverage: 2,
            .neutral: 3,
            .good: 4,
            .excellent: 5,
        ],
        labelMap: [QualityTier: String] = [
            .reject: "Red",
            .excellent: "Green",
        ],
        urgencyMap: [QualityTier: Int] = [:]
    ) {
        self.minimumConfidence = minimumConfidence
        self.writeRating = writeRating
        self.writeLabel = writeLabel
        self.writeUrgency = writeUrgency
        self.writeKeywords = writeKeywords
        self.rejectAsMinusOne = rejectAsMinusOne
        self.perCriterionProblemKeywords = perCriterionProblemKeywords
        self.keywordRoot = keywordRoot
        self.ratingMap = ratingMap
        self.labelMap = labelMap
        self.urgencyMap = urgencyMap
    }

    public static let builtInDefaults = QualityGradingPolicy()
}

/// Output-channel values and audit explanation derived from stored assessments.
public struct QualityGrade: Sendable, Equatable {
    public let tier: QualityTier
    public let rating: Int?
    public let label: String?
    public let urgency: Int?
    public let keywords: [String]
    public let explanation: [String]

    public init(
        tier: QualityTier,
        rating: Int?,
        label: String?,
        urgency: Int?,
        keywords: [String],
        explanation: [String]
    ) {
        self.tier = tier
        self.rating = rating
        self.label = label
        self.urgency = urgency
        self.keywords = keywords
        self.explanation = explanation
    }
}

/// Stable reason an asset could not pass the policy's grading gates.
public enum QualityUngradedReason: String, Codable, Sendable, Equatable {
    case noRecords = "no_records"
    case belowMinimumConfidence = "below_minimum_confidence"
    case overallUnrated = "overall_unrated"
}

/// Deterministically derives a tier and output-channel values from at most one record per role.
public enum QualityTierDeriver {
    public static func grade(
        whole: QualityAssessmentRecord?,
        subject: QualityAssessmentRecord?,
        policy: QualityGradingPolicy
    ) -> QualityGrade? {
        guard ungradedReason(whole: whole, subject: subject, policy: policy) == nil,
            let primary = whole ?? subject
        else {
            return nil
        }

        var explanation: [String] = []
        var tier = baseTier(for: primary, explanation: &explanation)
        if whole != nil,
            let subject,
            subject.criteria[.focus] == .problem,
            tier > .belowAverage
        {
            tier = tier.demoted
            explanation.append("subject focus veto: demoted to \(tier.rawValue)")
        }

        let rating =
            policy.writeRating
            ? (tier == .reject && policy.rejectAsMinusOne ? -1 : policy.ratingMap[tier])
            : nil
        let label = policy.writeLabel ? policy.labelMap[tier] : nil
        let urgency = policy.writeUrgency && label != nil ? policy.urgencyMap[tier] : nil
        var keywords: [String] = []
        if policy.writeKeywords {
            keywords.append("\(policy.keywordRoot)|\(tier.rawValue)")
            if policy.perCriterionProblemKeywords {
                for (criterion, level) in primary.criteria.sorted(by: { $0.key.rawValue < $1.key.rawValue })
                where level == .problem {
                    keywords.append("\(policy.keywordRoot)|problems|\(criterion.rawValue)")
                }
            }
        }

        return QualityGrade(
            tier: tier,
            rating: rating,
            label: label,
            urgency: urgency,
            keywords: keywords,
            explanation: explanation
        )
    }

    public static func ungradedReason(
        whole: QualityAssessmentRecord?,
        subject: QualityAssessmentRecord?,
        policy: QualityGradingPolicy
    ) -> QualityUngradedReason? {
        guard let primary = whole ?? subject else {
            return .noRecords
        }
        guard primary.confidence >= policy.minimumConfidence else {
            return .belowMinimumConfidence
        }
        guard primary.overall != .unrated else {
            return .overallUnrated
        }
        return nil
    }

    private static func baseTier(
        for primary: QualityAssessmentRecord,
        explanation: inout [String]
    ) -> QualityTier {
        let strongCount = primary.criteria.values.filter { $0 == .strong }.count
        let problemCount = primary.criteria.values.filter { $0 == .problem }.count

        switch primary.overall {
        case .problem where primary.criteria[.focus] == .problem || problemCount >= 3:
            explanation.append("overall problem corroborated by focus or at least three problem criteria")
            return .reject
        case .problem:
            explanation.append("overall problem without reject-level corroboration")
            return .belowAverage
        case .acceptable where problemCount == 0 && strongCount >= 2:
            explanation.append("acceptable overall with at least two strengths and no problems")
            return .good
        case .acceptable:
            explanation.append("acceptable overall")
            return .neutral
        case .strong where problemCount == 0 && strongCount >= 3 && primary.confidence == .high:
            explanation.append("strong overall with at least three strengths, no problems, and high confidence")
            return .excellent
        case .strong:
            explanation.append("strong overall")
            return .good
        case .unrated:
            // `ungradedReason` handles this gate before tier derivation.
            return .neutral
        }
    }
}
