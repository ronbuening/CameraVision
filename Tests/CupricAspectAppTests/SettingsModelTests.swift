import AISidecarCore
import XCTest

@testable import CupricAspectApp

/// Settings write-through (FR4-056, AC4-032): changes land in config.json,
/// unknown keys survive, and the resolver chain reflects them.
final class SettingsModelTests: XCTestCase {
    private var root: URL!
    private var configPath: String!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configPath = root.appendingPathComponent("config.json").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    private func makeModel() -> SettingsModel {
        SettingsModel(configPath: configPath, environment: [:])
    }

    @MainActor
    func testDefaultsResolveAndChangesWriteThrough() throws {
        let model = makeModel()
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.mode, .both, "built-in default")

        model.setMode(.subject)
        model.setExisting(.fail)
        model.setGPS(.off)
        model.setModel("qwen2.5vl:7b")

        XCTAssertEqual(model.mode, .subject)
        XCTAssertEqual(model.existing, .fail)
        XCTAssertEqual(model.gps, .off)
        XCTAssertEqual(model.model, "qwen2.5vl:7b")

        // AC4-032: a fresh resolve over the same file (a CLI run) sees them.
        let resolved = try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(resolved.mode, .subject)
        XCTAssertEqual(resolved.existing, .fail)
        XCTAssertEqual(resolved.gpsContext, .off)
        XCTAssertEqual(resolved.model, "qwen2.5vl:7b")
    }

    @MainActor
    func testModelTuningWriteThroughReachesResolverChain() throws {
        let model = makeModel()
        XCTAssertEqual(model.profile, ModelInputProfile.defaultProfile.name, "built-in default")
        XCTAssertEqual(model.modelContextWindow, ResolvedRunConfiguration.builtInDefaults.modelContextWindow)
        XCTAssertEqual(model.modelTimeoutSeconds, ModelRunOptions.default.timeoutSeconds)
        XCTAssertEqual(model.modelRetryLimit, ModelRunOptions.default.retryLimit)

        model.setProfile("gemma4-26b-benchmark-1024")
        model.setModelContextWindow(16_384)
        model.setModelTimeoutSeconds(300)
        model.setModelRetryLimit(4)

        XCTAssertEqual(model.profile, "gemma4-26b-benchmark-1024")
        XCTAssertEqual(model.modelContextWindow, 16_384)
        XCTAssertEqual(model.modelTimeoutSeconds, 300)
        XCTAssertEqual(model.modelRetryLimit, 4)

        let resolved = try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(resolved.profile, "gemma4-26b-benchmark-1024")
        XCTAssertEqual(resolved.modelContextWindow, 16_384)
        XCTAssertEqual(resolved.modelTimeoutSeconds, 300)
        XCTAssertEqual(resolved.modelRetryLimit, 4)

        let object = try readConfigObject()
        XCTAssertEqual(object["model_timeout_seconds"] as? Double, 300)
        XCTAssertEqual(object["model_retry_limit"] as? Int, 4)
    }

    @MainActor
    func testHandEditedKeysSurviveSettingsChanges() throws {
        try Data(#"{"stage_concurrency": 3, "custom_note": "mine"}"#.utf8)
            .write(to: URL(fileURLWithPath: configPath))
        let model = makeModel()

        model.setMode(.whole)

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: configPath))
            ) as? [String: Any]
        )
        XCTAssertEqual(object["custom_note"] as? String, "mine")
        XCTAssertEqual(object["stage_concurrency"] as? Int, 3)
        XCTAssertEqual(object["mode"] as? String, "whole")
    }

    @MainActor
    func testConcurrencyWriteThroughPreservesUnknownKeys() throws {
        try Data(#"{"custom_note": "mine"}"#.utf8)
            .write(to: URL(fileURLWithPath: configPath))
        let model = makeModel()

        model.setConcurrency(4)

        let object = try readConfigObject()
        XCTAssertEqual(object["custom_note"] as? String, "mine")
        XCTAssertEqual(object["stage_concurrency"] as? Int, 4)
    }

    @MainActor
    func testConcurrencyWritesThroughAndResolves() throws {
        let model = makeModel()

        model.setConcurrency(4)

        let resolved = try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(model.stageConcurrency, 4)
        XCTAssertEqual(resolved.stageConcurrency, 4)
    }

    @MainActor
    func testConcurrencyWriteThroughClampsToSettingsRange() throws {
        let model = makeModel()

        model.setConcurrency(0)
        XCTAssertEqual(model.stageConcurrency, 1)
        XCTAssertEqual(
            try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath).stageConcurrency, 1)

        model.setConcurrency(99)
        XCTAssertEqual(model.stageConcurrency, 8)
        XCTAssertEqual(
            try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath).stageConcurrency, 8)
    }

    @MainActor
    func testXMPConflictPolicyWriteThroughPreservesUnknownKeys() throws {
        try Data(#"{"custom_note": "mine"}"#.utf8)
            .write(to: URL(fileURLWithPath: configPath))
        let model = makeModel()

        model.setXMPConflictPolicy(.merge)

        let object = try readConfigObject()
        XCTAssertEqual(object["custom_note"] as? String, "mine")
        XCTAssertEqual(object["xmp_conflict_policy"] as? String, "merge")
    }

    @MainActor
    func testXMPConflictPolicyWritesThroughAndResolvesForExport() throws {
        let model = makeModel()

        model.setXMPConflictPolicy(.merge)

        XCTAssertEqual(model.xmpConflictPolicy, .merge)
        let resolved = try ConfigurationResolver.resolveXMPExport(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(resolved.xmpConflictPolicy, .merge)
    }

    @MainActor
    func testQualityDefaultsWriteThroughAndResolveForExport() throws {
        let model = makeModel()

        model.setQualityMinimumConfidence(.high)
        model.setQualityWriteRating(true)
        model.setQualityWriteLabel(false)
        model.setQualityWriteUrgency(false)
        model.setQualityWriteFlag(false)
        model.setQualityWriteKeywords(false)

        let object = try readConfigObject()
        XCTAssertEqual(object["xmp_quality_min_confidence"] as? String, "high")
        XCTAssertEqual(object["xmp_quality_write_rating"] as? Bool, true)
        XCTAssertEqual(object["xmp_quality_write_label"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_urgency"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_flag"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_keywords"] as? Bool, false)

        let policy = try ConfigurationResolver.resolveApplySession(
            environment: [:],
            defaultConfigPath: configPath
        ).qualityGrading.policy
        XCTAssertEqual(policy.minimumConfidence, .high)
        XCTAssertTrue(policy.writeRating)
        XCTAssertFalse(policy.writeLabel)
        XCTAssertFalse(policy.writeUrgency)
        XCTAssertFalse(policy.writeFlag)
        XCTAssertFalse(policy.writeKeywords)
    }

    @MainActor
    func testQualityDefaultsSeedFromEffectiveEnvironmentPrecedence() {
        let model = SettingsModel(
            configPath: configPath,
            environment: [
                "AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE": "low",
                "AISIDECAR_XMP_QUALITY_WRITE_LABEL": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_URGENCY": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_FLAG": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_KEYWORDS": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_RATING": "true",
            ]
        )

        XCTAssertEqual(model.qualityMinimumConfidence, .low)
        XCTAssertFalse(model.qualityWriteLabel)
        XCTAssertFalse(model.qualityWriteUrgency)
        XCTAssertFalse(model.qualityWriteFlag)
        XCTAssertFalse(model.qualityWriteKeywords)
        XCTAssertTrue(model.qualityWriteRating)
    }

    @MainActor
    func testUntouchedQualityDefaultsDoNotCreateOrExpandConfig() throws {
        let model = makeModel()

        XCTAssertNil(model.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath))

        model.setQualityWriteRating(true)

        let object = try readConfigObject()
        XCTAssertEqual(object["xmp_quality_write_rating"] as? Bool, true)
        XCTAssertEqual(object.count, 1, "untouched quality defaults stay absent")
    }

    @MainActor
    func testInvalidEndpointIsRejectedWithoutWriting() {
        let model = makeModel()
        model.endpointDraft = "not a url"
        model.applyEndpoint()
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath), "nothing written")
    }

    @MainActor
    func testInvalidModelRequestLimitsAreRejectedWithoutWriting() {
        let model = makeModel()

        model.setModelTimeoutSeconds(0)
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath), "invalid timeout is not persisted")

        model.setModelRetryLimit(-1)
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath), "invalid retry limit is not persisted")
    }

    @MainActor
    func testEnvironmentOverridesAreDisclosed() {
        let model = SettingsModel(
            configPath: configPath,
            environment: ["AISIDECAR_MODEL": "x", "HOME": "/tmp", "AISIDECAR_MODE": "whole"]
        )
        XCTAssertEqual(model.environmentOverrides, ["AISIDECAR_MODE", "AISIDECAR_MODEL"])
        XCTAssertEqual(model.mode, .whole, "environment wins over file per precedence")
    }

    private func readConfigObject() throws -> [String: Any] {
        try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: configPath))
            ) as? [String: Any]
        )
    }
}
