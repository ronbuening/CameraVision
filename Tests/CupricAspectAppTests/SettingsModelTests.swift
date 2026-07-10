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

        model.setProfile("gemma4-26b-benchmark-1024")
        model.setModelContextWindow(16_384)

        XCTAssertEqual(model.profile, "gemma4-26b-benchmark-1024")
        XCTAssertEqual(model.modelContextWindow, 16_384)

        let resolved = try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        XCTAssertEqual(resolved.profile, "gemma4-26b-benchmark-1024")
        XCTAssertEqual(resolved.modelContextWindow, 16_384)
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
        XCTAssertEqual(try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath).stageConcurrency, 1)

        model.setConcurrency(99)
        XCTAssertEqual(model.stageConcurrency, 8)
        XCTAssertEqual(try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath).stageConcurrency, 8)
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
    func testInvalidEndpointIsRejectedWithoutWriting() {
        let model = makeModel()
        model.endpointDraft = "not a url"
        model.applyEndpoint()
        XCTAssertNotNil(model.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath), "nothing written")
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
