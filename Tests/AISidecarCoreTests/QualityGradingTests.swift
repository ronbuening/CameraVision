import XCTest

@testable import AISidecarCore

final class QualityGradingTests: XCTestCase {
    func testRuleTableCoversEveryTierRowAndThresholdBoundary() throws {
        struct Case {
            var name: String
            var overall: QualityAssessmentRecord.Level
            var confidence: QualityAssessmentRecord.Confidence
            var strongCount: Int
            var problemCount: Int
            var focus: QualityAssessmentRecord.Level
            var expected: QualityTier
        }
        let cases = [
            Case(
                name: "problem focus reject",
                overall: .problem,
                confidence: .high,
                strongCount: 0,
                problemCount: 1,
                focus: .problem,
                expected: .reject
            ),
            Case(
                name: "three problems reject",
                overall: .problem,
                confidence: .medium,
                strongCount: 0,
                problemCount: 3,
                focus: .acceptable,
                expected: .reject
            ),
            Case(
                name: "two problems below average",
                overall: .problem,
                confidence: .medium,
                strongCount: 0,
                problemCount: 2,
                focus: .acceptable,
                expected: .belowAverage
            ),
            Case(
                name: "acceptable two strengths good",
                overall: .acceptable,
                confidence: .medium,
                strongCount: 2,
                problemCount: 0,
                focus: .acceptable,
                expected: .good
            ),
            Case(
                name: "acceptable one strength neutral",
                overall: .acceptable,
                confidence: .medium,
                strongCount: 1,
                problemCount: 0,
                focus: .acceptable,
                expected: .neutral
            ),
            Case(
                name: "acceptable problem neutral",
                overall: .acceptable,
                confidence: .high,
                strongCount: 3,
                problemCount: 1,
                focus: .acceptable,
                expected: .neutral
            ),
            Case(
                name: "strong excellent thresholds",
                overall: .strong,
                confidence: .high,
                strongCount: 3,
                problemCount: 0,
                focus: .acceptable,
                expected: .excellent
            ),
            Case(
                name: "strong only two strengths good",
                overall: .strong,
                confidence: .high,
                strongCount: 2,
                problemCount: 0,
                focus: .acceptable,
                expected: .good
            ),
            Case(
                name: "strong medium confidence good",
                overall: .strong,
                confidence: .medium,
                strongCount: 3,
                problemCount: 0,
                focus: .acceptable,
                expected: .good
            ),
            Case(
                name: "strong one problem good",
                overall: .strong,
                confidence: .high,
                strongCount: 3,
                problemCount: 1,
                focus: .acceptable,
                expected: .good
            ),
        ]

        for testCase in cases {
            let grade = QualityTierDeriver.grade(
                whole: record(
                    role: .wholeImage,
                    overall: testCase.overall,
                    confidence: testCase.confidence,
                    strongCount: testCase.strongCount,
                    problemCount: testCase.problemCount,
                    focus: testCase.focus
                ),
                subject: nil,
                policy: .builtInDefaults
            )
            XCTAssertEqual(grade?.tier, testCase.expected, testCase.name)
        }
    }

    func testUngradedReasonsCoverNoRecordsConfidenceAndUnratedOverall() {
        XCTAssertEqual(
            QualityTierDeriver.ungradedReason(whole: nil, subject: nil, policy: .builtInDefaults),
            .noRecords
        )
        XCTAssertEqual(
            QualityTierDeriver.ungradedReason(
                whole: record(role: .wholeImage, overall: .strong, confidence: .low),
                subject: nil,
                policy: .builtInDefaults
            ),
            .belowMinimumConfidence
        )
        XCTAssertEqual(
            QualityTierDeriver.ungradedReason(
                whole: record(role: .wholeImage, overall: .unrated, confidence: .high),
                subject: nil,
                policy: .builtInDefaults
            ),
            .overallUnrated
        )
        XCTAssertNil(
            QualityTierDeriver.grade(
                whole: record(role: .wholeImage, overall: .unrated, confidence: .high),
                subject: nil,
                policy: .builtInDefaults
            )
        )
    }

    func testSubjectFocusVetoDemotesExactlyOneTierOnlyWhenWholeExists() throws {
        let whole = record(
            role: .wholeImage,
            overall: .strong,
            confidence: .high,
            strongCount: 3
        )
        let subject = record(
            role: .subjectIsolated,
            overall: .strong,
            confidence: .high,
            focus: .problem
        )

        let combined = try XCTUnwrap(
            QualityTierDeriver.grade(whole: whole, subject: subject, policy: .builtInDefaults)
        )
        let subjectOnly = try XCTUnwrap(
            QualityTierDeriver.grade(whole: nil, subject: subject, policy: .builtInDefaults)
        )

        XCTAssertEqual(combined.tier, .good)
        XCTAssertEqual(combined.explanation.last, "subject focus veto: demoted to good")
        XCTAssertEqual(subjectOnly.tier, .good)
        XCTAssertFalse(subjectOnly.explanation.contains { $0.contains("veto") })
    }

    func testWholeRecordIsPrimaryWhenBothRolesExist() {
        let whole = record(role: .wholeImage, overall: .acceptable, confidence: .high)
        let subject = record(role: .subjectIsolated, overall: .strong, confidence: .high, strongCount: 4)

        let grade = QualityTierDeriver.grade(whole: whole, subject: subject, policy: .builtInDefaults)

        XCTAssertEqual(grade?.tier, .neutral)
    }

    func testConfidenceGateIncludesConfiguredBoundary() {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.minimumConfidence = .high
        XCTAssertNil(
            QualityTierDeriver.grade(
                whole: record(role: .wholeImage, overall: .strong, confidence: .medium),
                subject: nil,
                policy: policy
            )
        )
        XCTAssertNotNil(
            QualityTierDeriver.grade(
                whole: record(role: .wholeImage, overall: .strong, confidence: .high),
                subject: nil,
                policy: policy
            )
        )
        policy.minimumConfidence = .low
        XCTAssertNotNil(
            QualityTierDeriver.grade(
                whole: record(role: .wholeImage, overall: .acceptable, confidence: .low),
                subject: nil,
                policy: policy
            )
        )
    }

    func testRejectMinusOneChangesOnlyRejectRating() {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.rejectAsMinusOne = true
        let reject = QualityTierDeriver.grade(
            whole: record(role: .wholeImage, overall: .problem, confidence: .high, focus: .problem),
            subject: nil,
            policy: policy
        )
        let good = QualityTierDeriver.grade(
            whole: record(role: .wholeImage, overall: .strong, confidence: .high),
            subject: nil,
            policy: policy
        )

        XCTAssertEqual(reject?.rating, -1)
        XCTAssertEqual(good?.rating, 4)
    }

    func testUrgencyRequiresAnEmittedLabelAndTierMapping() {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.urgencyMap = [.reject: 1, .good: 3]
        let reject = QualityTierDeriver.grade(
            whole: record(role: .wholeImage, overall: .problem, confidence: .high, focus: .problem),
            subject: nil,
            policy: policy
        )
        let good = QualityTierDeriver.grade(
            whole: record(role: .wholeImage, overall: .strong, confidence: .high),
            subject: nil,
            policy: policy
        )
        policy.writeLabel = false
        let labelDisabled = QualityTierDeriver.grade(
            whole: record(role: .wholeImage, overall: .problem, confidence: .high, focus: .problem),
            subject: nil,
            policy: policy
        )

        XCTAssertEqual(reject?.label, "Red")
        XCTAssertEqual(reject?.urgency, 1)
        XCTAssertNil(good?.label)
        XCTAssertNil(good?.urgency)
        XCTAssertNil(labelDisabled?.urgency)
    }

    func testQualityKeywordsAreDeterministicAndProblemCriteriaSorted() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.perCriterionProblemKeywords = true
        let whole = QualityAssessmentRecord(
            role: .wholeImage,
            promptVersion: "test",
            criteria: [
                .technicalCleanliness: .problem,
                .focus: .problem,
                .composition: .acceptable,
            ],
            overall: .problem,
            strengths: [],
            concerns: [],
            confidence: .high
        )

        let grade = try XCTUnwrap(
            QualityTierDeriver.grade(whole: whole, subject: nil, policy: policy)
        )

        XCTAssertEqual(
            grade.keywords,
            [
                "AI Quality|reject",
                "AI Quality|problems|focus",
                "AI Quality|problems|technical_cleanliness",
            ]
        )
    }

    func testDisabledChannelsProduceNoMappedValues() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.writeRating = false
        policy.writeLabel = false
        policy.writeUrgency = false
        policy.writeKeywords = false

        let grade = try XCTUnwrap(
            QualityTierDeriver.grade(
                whole: record(role: .wholeImage, overall: .strong, confidence: .high),
                subject: nil,
                policy: policy
            )
        )

        XCTAssertNil(grade.rating)
        XCTAssertNil(grade.label)
        XCTAssertNil(grade.urgency)
        XCTAssertTrue(grade.keywords.isEmpty)
    }

    func testGradingPolicyRoundTripsWithSnakeCaseKeysAndRawTierMapKeys() throws {
        let policy = QualityGradingPolicy(
            minimumConfidence: .high,
            writeRating: false,
            writeLabel: false,
            writeUrgency: false,
            writeKeywords: false,
            rejectAsMinusOne: true,
            perCriterionProblemKeywords: true,
            keywordRoot: "Review Quality",
            ratingMap: [.reject: -1, .belowAverage: 2, .excellent: 5],
            labelMap: [.good: "Blue"],
            urgencyMap: [.good: 4]
        )

        let data = try JSONCoding.documentEncoder(iso8601Dates: false).encode(policy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ratingMap = try XCTUnwrap(object["rating_map"] as? [String: Any])
        let decoded = try JSONCoding.decoder(iso8601Dates: false).decode(QualityGradingPolicy.self, from: data)

        XCTAssertEqual(
            Set(object.keys),
            Set([
                "minimum_confidence",
                "write_rating",
                "write_label",
                "write_urgency",
                "write_keywords",
                "reject_as_minus_one",
                "per_criterion_problem_keywords",
                "keyword_root",
                "rating_map",
                "label_map",
                "urgency_map",
            ])
        )
        XCTAssertNotNil(ratingMap["below_average"])
        XCTAssertEqual(decoded, policy)
    }

    func testGradingPolicyRejectsRatingOutsideSupportedRange() throws {
        for rating in [-2, 6] {
            var policy = QualityGradingPolicy.builtInDefaults
            policy.ratingMap[.neutral] = rating
            try assertConfigInvalid { try policy.validate() }
        }
    }

    func testGradingPolicyRejectsUrgencyOutsideSupportedRange() throws {
        for urgency in [0, 9] {
            var policy = QualityGradingPolicy.builtInDefaults
            policy.urgencyMap[.excellent] = urgency
            try assertConfigInvalid { try policy.validate() }
        }
    }

    func testGradingPolicyRejectsEmptyLabel() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.labelMap[.good] = " \n "
        try assertConfigInvalid { try policy.validate() }
    }

    func testGradingPolicyRejectsHierarchySeparatorInLabel() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.labelMap[.good] = "Blue|Pick"
        try assertConfigInvalid { try policy.validate() }
    }

    func testGradingPolicyRejectsEmptyKeywordRoot() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.keywordRoot = " \t "
        try assertConfigInvalid { try policy.validate() }
    }

    func testGradingPolicyRejectsHierarchySeparatorInKeywordRoot() throws {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.keywordRoot = "AI|Quality"
        try assertConfigInvalid { try policy.validate() }
    }

    func testGradingPolicyRejectsUnknownRatingTierKey() throws {
        try assertUnknownTierRejected(mapJSON: #""rating_map":{"future":3}"#)
    }

    func testGradingPolicyRejectsUnknownLabelTierKey() throws {
        try assertUnknownTierRejected(mapJSON: #""label_map":{"future":"Orange"}"#)
    }

    func testGradingPolicyRejectsUnknownUrgencyTierKey() throws {
        try assertUnknownTierRejected(mapJSON: #""urgency_map":{"future":4}"#)
    }

    private func record(
        role: ModelInputRole,
        overall: QualityAssessmentRecord.Level,
        confidence: QualityAssessmentRecord.Confidence,
        strongCount: Int = 0,
        problemCount: Int = 0,
        focus: QualityAssessmentRecord.Level = .acceptable
    ) -> QualityAssessmentRecord {
        let availableCriteria = QualityAssessmentRecord.Criterion.allCases.filter { $0 != .focus }
        var criteria: [QualityAssessmentRecord.Criterion: QualityAssessmentRecord.Level] = [.focus: focus]
        var remainingStrong = max(0, strongCount - (focus == .strong ? 1 : 0))
        var remainingProblems = max(0, problemCount - (focus == .problem ? 1 : 0))
        for criterion in availableCriteria {
            if remainingStrong > 0 {
                criteria[criterion] = .strong
                remainingStrong -= 1
            } else if remainingProblems > 0 {
                criteria[criterion] = .problem
                remainingProblems -= 1
            } else {
                criteria[criterion] = .acceptable
            }
        }
        return QualityAssessmentRecord(
            role: role,
            promptVersion: "test",
            criteria: criteria,
            overall: overall,
            strengths: [],
            concerns: [],
            confidence: confidence
        )
    }

    private func assertUnknownTierRejected(mapJSON: String) throws {
        let data = try XCTUnwrap("{\(mapJSON)}".data(using: .utf8))
        try assertConfigInvalid {
            _ = try JSONCoding.decoder(iso8601Dates: false).decode(QualityGradingPolicy.self, from: data)
        }
    }

    private func assertConfigInvalid(_ operation: () throws -> Void) throws {
        do {
            try operation()
            XCTFail("Expected E_CONFIG_INVALID")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .configInvalid)
            XCTAssertEqual(error.stage, .configuration)
            XCTAssertFalse(error.recoverable)
        }
    }
}
