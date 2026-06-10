import XCTest
@testable import AISidecarCore

final class ConfigResolutionTests: XCTestCase {
    func testDefaultsLoadWhenDefaultConfigIsMissing() throws {
        let resolved = try ConfigurationResolver.resolve(
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved, .builtInDefaults)
        XCTAssertEqual(resolved.sourceIdentityPolicy, .sha256)
    }

    func testConfigFileOverridesDefaults() throws {
        let configPath = try writeConfig(
            """
            {
              "mode": "whole",
              "existing": "overwrite",
              "recursive": true,
              "output_dir": "/tmp/sidecars",
              "model": "custom:model",
              "model_endpoint": "http://127.0.0.1:11434",
              "profile": "gemma4-26b-default",
              "log_level": "debug",
              "log_format": "json",
              "dry_run": true,
              "debug_derivatives": true,
              "source_identity_policy": "fast",
              "derivative_cache_dir": "/tmp/aisidecar-cache",
              "derivative_cache_size_bytes": 1048576
            }
            """
        )

        let resolved = try ConfigurationResolver.resolve(
            environment: [:],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.mode, .whole)
        XCTAssertEqual(resolved.existing, .overwrite)
        XCTAssertTrue(resolved.recursive)
        XCTAssertEqual(resolved.outputDir, "/tmp/sidecars")
        XCTAssertEqual(resolved.model, "custom:model")
        XCTAssertEqual(resolved.modelEndpoint.absoluteString, "http://127.0.0.1:11434")
        XCTAssertEqual(resolved.profile, "gemma4-26b-default")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.dryRun)
        XCTAssertTrue(resolved.debugDerivatives)
        XCTAssertEqual(resolved.sourceIdentityPolicy, .fast)
        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/aisidecar-cache")
        XCTAssertEqual(resolved.derivativeCacheSizeBytes, 1_048_576)
    }

    func testEnvironmentOverridesConfigFile() throws {
        let configPath = try writeConfig(
            """
            {
              "mode": "whole",
              "existing": "fail",
              "model": "file:model",
              "log_level": "error",
              "source_identity_policy": "fast"
            }
            """
        )

        let resolved = try ConfigurationResolver.resolve(
            environment: [
                "AISIDECAR_MODE": "subject",
                "AISIDECAR_EXISTING": "overwrite",
                "AISIDECAR_MODEL": "env:model",
                "AISIDECAR_LOG_LEVEL": "debug",
                "AISIDECAR_SOURCE_IDENTITY_POLICY": "sha256",
                "AISIDECAR_DERIVATIVE_CACHE_DIR": "/tmp/env-cache",
                "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "2097152"
            ],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.mode, .subject)
        XCTAssertEqual(resolved.existing, .overwrite)
        XCTAssertEqual(resolved.model, "env:model")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.sourceIdentityPolicy, .sha256)
        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/env-cache")
        XCTAssertEqual(resolved.derivativeCacheSizeBytes, 2_097_152)
    }

    func testSourceIdentityPolicyUsesStableJSONKey() throws {
        let config = AppConfig(sourceIdentityPolicy: .fast)
        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        XCTAssertEqual(object["source_identity_policy"], "fast")
        XCTAssertNil(object["sourceIdentityPolicy"])
    }

    func testCLIOverridesEnvironment() throws {
        let resolved = try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(
                mode: .both,
                existing: .skip,
                model: "cli:model",
                modelEndpoint: "http://localhost:9999",
                logFormat: .json
            ),
            environment: [
                "AISIDECAR_MODE": "subject",
                "AISIDECAR_EXISTING": "overwrite",
                "AISIDECAR_MODEL": "env:model",
                "AISIDECAR_MODEL_ENDPOINT": "http://localhost:1111",
                "AISIDECAR_LOG_FORMAT": "text"
            ],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved.mode, .both)
        XCTAssertEqual(resolved.existing, .skip)
        XCTAssertEqual(resolved.model, "cli:model")
        XCTAssertEqual(resolved.modelEndpoint.absoluteString, "http://localhost:9999")
        XCTAssertEqual(resolved.logFormat, .json)
    }

    func testCLIConfigPathChoosesAlternateJSON() throws {
        let defaultPath = try writeConfig(#"{ "mode": "whole" }"#)
        let alternatePath = try writeConfig(#"{ "mode": "subject" }"#)

        let resolved = try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(configPath: alternatePath),
            environment: [:],
            defaultConfigPath: defaultPath
        )

        XCTAssertEqual(resolved.mode, .subject)
    }

    private func missingConfigPath() -> String {
        "\(NSTemporaryDirectory())aisidecar-tests/\(UUID().uuidString)/missing-config.json"
    }

    private func writeConfig(_ contents: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        try contents.data(using: .utf8)!.write(to: file)
        return file.path
    }
}
