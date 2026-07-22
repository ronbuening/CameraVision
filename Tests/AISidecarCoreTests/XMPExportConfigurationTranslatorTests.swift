import XCTest

@testable import AISidecarCore

final class XMPExportConfigurationTranslatorTests: XCTestCase {
    func testTranslatorSentinelsCoverEveryResolvedExportField() {
        let fieldCount = Mirror(reflecting: ResolvedXMPExportConfiguration.builtInDefaults).children.count

        XCTAssertEqual(
            fieldCount, 16,
            """
            ResolvedXMPExportConfiguration gained or lost a stored field. A field added \
            with a memberwise default compiles through every translator while staying \
            unmapped: map it in all three translator inits, extend the sentinel tests \
            in this file, then update this count.
            """
        )
    }

    func testNormalizationTranslatorMapsEveryExportField() {
        let grading = qualityGrading(keywordRoot: "Normalization grading", conflictPolicy: .overwrite)
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.outputDir = "/normalization-output"
        configuration.logLevel = .debug
        configuration.logFormat = .json
        configuration.dryRun = true
        configuration.sourceRoot = "/normalization-source"
        configuration.sourceVerification = .warn
        configuration.writeFlatKeywords = false
        configuration.writeHierarchicalKeywords = false
        configuration.backupSidecars = false
        configuration.xmpConflictPolicy = .fail
        configuration.minConfidence = .high
        configuration.allowSpecificTags = true
        configuration.pairScope = .jpegOnly
        configuration.writeAIJSON = false
        configuration.qualityGrading = grading

        let translated = ResolvedXMPExportConfiguration(from: configuration)

        XCTAssertTrue(translated.recursive)
        XCTAssertEqual(translated.outputDir, "/normalization-output")
        XCTAssertEqual(translated.logLevel, .debug)
        XCTAssertEqual(translated.logFormat, .json)
        XCTAssertTrue(translated.dryRun)
        XCTAssertEqual(translated.sourceRoot, "/normalization-source")
        XCTAssertEqual(translated.sourceVerification, .warn)
        XCTAssertFalse(translated.writeFlatKeywords)
        XCTAssertFalse(translated.writeHierarchicalKeywords)
        XCTAssertFalse(translated.backupSidecars)
        XCTAssertEqual(translated.xmpConflictPolicy, .fail)
        XCTAssertEqual(translated.minConfidence, .high)
        XCTAssertTrue(translated.allowSpecificTags)
        XCTAssertEqual(translated.pairScope, .jpegOnly)
        XCTAssertFalse(translated.writeAIJSON)
        XCTAssertEqual(translated.qualityGrading, grading)
    }

    func testRawSidecarInputTranslatorPreservesDormantGradingDefault() {
        let grading = qualityGrading(keywordRoot: "Normalization grading", conflictPolicy: .overwrite)
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.outputDir = "/normalization-output"
        configuration.qualityGrading = grading

        let normalTranslation = ResolvedXMPExportConfiguration(from: configuration)
        let resolverTranslation = ResolvedXMPExportConfiguration(
            resolvingRawSidecarInputFrom: configuration
        )

        XCTAssertEqual(normalTranslation.qualityGrading, grading)
        XCTAssertEqual(resolverTranslation.qualityGrading, .builtInDefaults)
        var expectedResolverTranslation = normalTranslation
        expectedResolverTranslation.qualityGrading = .builtInDefaults
        XCTAssertEqual(resolverTranslation, expectedResolverTranslation)
    }

    func testApplySessionTranslatorUsesLiveApplyAndFrozenSessionOwnership() {
        let sessionGrading = qualityGrading(keywordRoot: "Frozen grading", conflictPolicy: .refresh)
        var sessionConfiguration = ResolvedNormalizationConfiguration.builtInDefaults
        sessionConfiguration.recursive = true
        sessionConfiguration.outputDir = "/frozen-output"
        sessionConfiguration.logLevel = .debug
        sessionConfiguration.logFormat = .text
        sessionConfiguration.dryRun = false
        sessionConfiguration.sourceRoot = "/frozen-source"
        sessionConfiguration.sourceVerification = .fail
        sessionConfiguration.writeFlatKeywords = false
        sessionConfiguration.writeHierarchicalKeywords = false
        sessionConfiguration.backupSidecars = true
        sessionConfiguration.xmpConflictPolicy = .fail
        sessionConfiguration.minConfidence = .high
        sessionConfiguration.allowSpecificTags = true
        sessionConfiguration.pairScope = .rawOnly
        sessionConfiguration.writeAIJSON = true
        sessionConfiguration.qualityGrading = sessionGrading

        let applyGrading = qualityGrading(keywordRoot: "Apply grading", conflictPolicy: .overwrite)
        let applyConfiguration = ResolvedApplySessionConfiguration(
            outputDir: "/apply-output",
            logLevel: .error,
            logFormat: .json,
            dryRun: true,
            sourceRoot: "/apply-source",
            sourceVerification: .skip,
            backupSidecars: false,
            xmpConflictPolicy: .merge,
            allowStale: true,
            qualityGrading: applyGrading
        )

        let translated = ResolvedXMPExportConfiguration(
            from: applyConfiguration,
            sessionConfiguration: sessionConfiguration
        )

        XCTAssertFalse(translated.recursive)
        XCTAssertEqual(translated.outputDir, "/apply-output")
        XCTAssertEqual(translated.logLevel, .error)
        XCTAssertEqual(translated.logFormat, .json)
        XCTAssertTrue(translated.dryRun)
        XCTAssertEqual(translated.sourceRoot, "/apply-source")
        XCTAssertEqual(translated.sourceVerification, .skip)
        XCTAssertFalse(translated.writeFlatKeywords)
        XCTAssertFalse(translated.writeHierarchicalKeywords)
        XCTAssertFalse(translated.backupSidecars)
        XCTAssertEqual(translated.xmpConflictPolicy, .merge)
        XCTAssertEqual(translated.minConfidence, .high)
        XCTAssertTrue(translated.allowSpecificTags)
        XCTAssertEqual(translated.pairScope, .rawOnly)
        XCTAssertFalse(translated.writeAIJSON)
        XCTAssertEqual(translated.qualityGrading, applyGrading)

        var applyWithoutSourceRoot = applyConfiguration
        applyWithoutSourceRoot.sourceRoot = nil
        XCTAssertNil(
            ResolvedXMPExportConfiguration(
                from: applyWithoutSourceRoot,
                sessionConfiguration: sessionConfiguration
            ).sourceRoot
        )
    }

    private func qualityGrading(
        keywordRoot: String,
        conflictPolicy: ScalarConflictPolicy
    ) -> ResolvedQualityGradingConfiguration {
        var policy = QualityGradingPolicy.builtInDefaults
        policy.keywordRoot = keywordRoot
        policy.writeRating = true
        return ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: conflictPolicy,
            policy: policy
        )
    }
}
