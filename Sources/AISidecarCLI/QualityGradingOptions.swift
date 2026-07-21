import AISidecarCore
import ArgumentParser

struct QualityGradingOptions: ParsableArguments {
    @Flag(help: "Grade stored quality assessments into configured XMP fields.")
    var qualityGrading = false

    @Flag(name: .customLong("write-rating"), help: "Write derived quality ratings to xmp:Rating.")
    var writeRating = false

    @Flag(name: .customLong("no-write-rating"), help: "Disable quality rating export.")
    var noWriteRating = false

    @Flag(name: .customLong("write-label"), help: "Write derived quality labels to xmp:Label.")
    var writeLabel = false

    @Flag(name: .customLong("no-write-label"), help: "Disable quality label export.")
    var noWriteLabel = false

    @Flag(
        name: .customLong("write-urgency"),
        help: "Write Capture One color companions to photoshop:Urgency."
    )
    var writeUrgency = false

    @Flag(name: .customLong("no-write-urgency"), help: "Disable Capture One urgency export.")
    var noWriteUrgency = false

    @Flag(
        name: .customLong("write-flag"),
        help: "Write derived pick/reject flags to the Lightroom xmpDM:pick/xmpDM:good pair."
    )
    var writeFlag = false

    @Flag(name: .customLong("no-write-flag"), help: "Disable Lightroom pick-flag export.")
    var noWriteFlag = false

    @Flag(name: .customLong("write-quality-keywords"), help: "Write deterministic quality-tier keywords.")
    var writeQualityKeywords = false

    @Flag(name: .customLong("no-write-quality-keywords"), help: "Disable quality-tier keyword export.")
    var noWriteQualityKeywords = false

    @Option(help: "Managed-scalar conflict policy: preserve, refresh, or overwrite.")
    var qualityConflicts: ScalarConflictPolicy?

    @Option(help: "Minimum confidence for quality grading: low, medium, or high.")
    var qualityMinConfidence: XMPMinimumConfidence?

    var overrides: QualityGradingConfigurationOverrides {
        QualityGradingConfigurationOverrides(
            enabled: qualityGrading ? true : nil,
            conflictPolicy: qualityConflicts,
            minimumConfidence: qualityConfidence(from: qualityMinConfidence),
            writeRating: CommandOutputHelpers.pairedFlag(positive: writeRating, negative: noWriteRating),
            writeLabel: CommandOutputHelpers.pairedFlag(positive: writeLabel, negative: noWriteLabel),
            writeUrgency: CommandOutputHelpers.pairedFlag(positive: writeUrgency, negative: noWriteUrgency),
            writeFlag: CommandOutputHelpers.pairedFlag(positive: writeFlag, negative: noWriteFlag),
            writeKeywords: CommandOutputHelpers.pairedFlag(
                positive: writeQualityKeywords,
                negative: noWriteQualityKeywords
            )
        )
    }

    private func qualityConfidence(
        from value: XMPMinimumConfidence?
    ) -> QualityAssessmentRecord.Confidence? {
        // Exhaustive so a new confidence tier cannot silently drop the flag.
        switch value {
        case nil:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}
