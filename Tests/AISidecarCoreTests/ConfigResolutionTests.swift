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
        XCTAssertFalse(resolved.clearDerivativeCacheOnStart)
        XCTAssertFalse(resolved.clearDerivativeCacheAfterSuccess)
        XCTAssertEqual(resolved.modelKeepAlive, "30m")
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 1)
    }

    func testXMPExportDefaultsLoadWhenDefaultConfigIsMissing() throws {
        let resolved = try ConfigurationResolver.resolveXMPExport(
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved, .builtInDefaults)
        XCTAssertFalse(resolved.recursive)
        XCTAssertNil(resolved.outputDir)
        XCTAssertEqual(resolved.logLevel, .info)
        XCTAssertEqual(resolved.logFormat, .text)
        XCTAssertFalse(resolved.dryRun)
        XCTAssertNil(resolved.sourceRoot)
        XCTAssertEqual(resolved.sourceVerification, .fail)
        XCTAssertTrue(resolved.writeFlatKeywords)
        XCTAssertTrue(resolved.writeHierarchicalKeywords)
        XCTAssertTrue(resolved.backupSidecars)
        XCTAssertEqual(resolved.xmpConflictPolicy, .backupAndMerge)
        XCTAssertEqual(resolved.minConfidence, .medium)
        XCTAssertFalse(resolved.allowSpecificTags)
        XCTAssertEqual(resolved.pairScope, .union)
        XCTAssertTrue(resolved.writeAIJSON)
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
              "model_keep_alive": "5m",
              "profile": "gemma4-26b-default",
              "log_level": "debug",
              "log_format": "json",
              "dry_run": true,
              "debug_derivatives": true,
              "source_identity_policy": "fast",
              "derivative_cache_dir": "/tmp/aisidecar-cache",
              "derivative_cache_size_bytes": 1048576,
              "clear_derivative_cache_on_start": true,
              "clear_derivative_cache_after_success": true,
              "subject_crop_margin_fraction": 0.12,
              "subject_merge_dominance_threshold": 0.75,
              "stage_concurrency": 3,
              "model_response_repair_attempts": 0
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
        XCTAssertEqual(resolved.modelKeepAlive, "5m")
        XCTAssertEqual(resolved.profile, "gemma4-26b-default")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.dryRun)
        XCTAssertTrue(resolved.debugDerivatives)
        XCTAssertEqual(resolved.sourceIdentityPolicy, .fast)
        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/aisidecar-cache")
        XCTAssertEqual(resolved.derivativeCacheSizeBytes, 1_048_576)
        XCTAssertTrue(resolved.clearDerivativeCacheOnStart)
        XCTAssertTrue(resolved.clearDerivativeCacheAfterSuccess)
        XCTAssertEqual(resolved.subjectCropMarginFraction, 0.12)
        XCTAssertEqual(resolved.subjectMergeDominanceThreshold, 0.75)
        XCTAssertEqual(resolved.stageConcurrency, 3)
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 0)
    }

    func testXMPExportConfigFileOverridesDefaults() throws {
        let configPath = try writeConfig(
            """
            {
              "recursive": true,
              "output_dir": "/tmp/xmp-sidecars",
              "log_level": "debug",
              "log_format": "json",
              "dry_run": true,
              "source_root": "/tmp/source-images",
              "source_verification": "warn",
              "write_flat_keywords": false,
              "write_hierarchical_keywords": false,
              "backup_sidecars": false,
              "xmp_conflict_policy": "merge",
              "min_confidence": "high",
              "allow_specific_tags": true,
              "pair_scope": "raw-only",
              "write_ai_json": false
            }
            """
        )

        let resolved = try ConfigurationResolver.resolveXMPExport(
            environment: [:],
            defaultConfigPath: configPath
        )

        XCTAssertTrue(resolved.recursive)
        XCTAssertEqual(resolved.outputDir, "/tmp/xmp-sidecars")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.dryRun)
        XCTAssertEqual(resolved.sourceRoot, "/tmp/source-images")
        XCTAssertEqual(resolved.sourceVerification, .warn)
        XCTAssertFalse(resolved.writeFlatKeywords)
        XCTAssertFalse(resolved.writeHierarchicalKeywords)
        XCTAssertFalse(resolved.backupSidecars)
        XCTAssertEqual(resolved.xmpConflictPolicy, .merge)
        XCTAssertEqual(resolved.minConfidence, .high)
        XCTAssertTrue(resolved.allowSpecificTags)
        XCTAssertEqual(resolved.pairScope, .rawOnly)
        XCTAssertFalse(resolved.writeAIJSON)
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
                "AISIDECAR_MODEL_KEEP_ALIVE": "0",
                "AISIDECAR_LOG_LEVEL": "debug",
                "AISIDECAR_SOURCE_IDENTITY_POLICY": "sha256",
                "AISIDECAR_DERIVATIVE_CACHE_DIR": "/tmp/env-cache",
                "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "2097152",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START": "yes",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS": "1",
                "AISIDECAR_SUBJECT_CROP_MARGIN_FRACTION": "0.15",
                "AISIDECAR_SUBJECT_MERGE_DOMINANCE_THRESHOLD": "0.65",
                "AISIDECAR_STAGE_CONCURRENCY": "5",
                "AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS": "2"
            ],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.mode, .subject)
        XCTAssertEqual(resolved.existing, .overwrite)
        XCTAssertEqual(resolved.model, "env:model")
        XCTAssertEqual(resolved.modelKeepAlive, "0")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.sourceIdentityPolicy, .sha256)
        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/env-cache")
        XCTAssertEqual(resolved.derivativeCacheSizeBytes, 2_097_152)
        XCTAssertTrue(resolved.clearDerivativeCacheOnStart)
        XCTAssertTrue(resolved.clearDerivativeCacheAfterSuccess)
        XCTAssertEqual(resolved.subjectCropMarginFraction, 0.15)
        XCTAssertEqual(resolved.subjectMergeDominanceThreshold, 0.65)
        XCTAssertEqual(resolved.stageConcurrency, 5)
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 2)
    }

    func testXMPExportEnvironmentOverridesConfigFile() throws {
        let configPath = try writeConfig(
            """
            {
              "recursive": false,
              "output_dir": "/tmp/file-xmp",
              "log_level": "error",
              "source_verification": "fail",
              "write_flat_keywords": true,
              "backup_sidecars": true,
              "xmp_conflict_policy": "backup-and-merge",
              "min_confidence": "medium",
              "allow_specific_tags": false,
              "pair_scope": "union",
              "write_ai_json": true
            }
            """
        )

        let resolved = try ConfigurationResolver.resolveXMPExport(
            environment: [
                "AISIDECAR_RECURSIVE": "1",
                "AISIDECAR_OUTPUT_DIR": "/tmp/env-xmp",
                "AISIDECAR_LOG_LEVEL": "debug",
                "AISIDECAR_LOG_FORMAT": "json",
                "AISIDECAR_DRY_RUN": "yes",
                "AISIDECAR_SOURCE_ROOT": "/tmp/env-source",
                "AISIDECAR_SOURCE_VERIFICATION": "skip",
                "AISIDECAR_WRITE_FLAT_KEYWORDS": "false",
                "AISIDECAR_WRITE_HIERARCHICAL_KEYWORDS": "false",
                "AISIDECAR_BACKUP_SIDECARS": "false",
                "AISIDECAR_XMP_CONFLICT_POLICY": "merge",
                "AISIDECAR_MIN_CONFIDENCE": "low",
                "AISIDECAR_ALLOW_SPECIFIC_TAGS": "true",
                "AISIDECAR_PAIR_SCOPE": "jpeg-only",
                "AISIDECAR_WRITE_AI_JSON": "false"
            ],
            defaultConfigPath: configPath
        )

        XCTAssertTrue(resolved.recursive)
        XCTAssertEqual(resolved.outputDir, "/tmp/env-xmp")
        XCTAssertEqual(resolved.logLevel, .debug)
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.dryRun)
        XCTAssertEqual(resolved.sourceRoot, "/tmp/env-source")
        XCTAssertEqual(resolved.sourceVerification, .skip)
        XCTAssertFalse(resolved.writeFlatKeywords)
        XCTAssertFalse(resolved.writeHierarchicalKeywords)
        XCTAssertFalse(resolved.backupSidecars)
        XCTAssertEqual(resolved.xmpConflictPolicy, .merge)
        XCTAssertEqual(resolved.minConfidence, .low)
        XCTAssertTrue(resolved.allowSpecificTags)
        XCTAssertEqual(resolved.pairScope, .jpegOnly)
        XCTAssertFalse(resolved.writeAIJSON)
    }

    func testSourceIdentityPolicyUsesStableJSONKey() throws {
        let config = AppConfig(
            modelKeepAlive: "5m",
            sourceIdentityPolicy: .fast,
            clearDerivativeCacheOnStart: true,
            clearDerivativeCacheAfterSuccess: true,
            subjectCropMarginFraction: 0.12,
            subjectMergeDominanceThreshold: 0.75,
            stageConcurrency: 3,
            modelResponseRepairAttempts: 0,
            sourceRoot: "/tmp/source-root",
            sourceVerification: .warn,
            writeFlatKeywords: false,
            writeHierarchicalKeywords: true,
            backupSidecars: false,
            xmpConflictPolicy: .merge,
            minConfidence: .high,
            allowSpecificTags: true,
            pairScope: .rawOnly,
            writeAIJSON: false
        )
        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["source_identity_policy"] as? String, "fast")
        XCTAssertNil(object["sourceIdentityPolicy"])
        XCTAssertEqual(object["model_keep_alive"] as? String, "5m")
        XCTAssertEqual(object["clear_derivative_cache_on_start"] as? Bool, true)
        XCTAssertEqual(object["clear_derivative_cache_after_success"] as? Bool, true)
        XCTAssertEqual(object["subject_crop_margin_fraction"] as? Double, 0.12)
        XCTAssertEqual(object["subject_merge_dominance_threshold"] as? Double, 0.75)
        XCTAssertEqual(object["stage_concurrency"] as? Int, 3)
        XCTAssertEqual(object["model_response_repair_attempts"] as? Int, 0)
        XCTAssertEqual(object["source_root"] as? String, "/tmp/source-root")
        XCTAssertEqual(object["source_verification"] as? String, "warn")
        XCTAssertEqual(object["write_flat_keywords"] as? Bool, false)
        XCTAssertEqual(object["write_hierarchical_keywords"] as? Bool, true)
        XCTAssertEqual(object["backup_sidecars"] as? Bool, false)
        XCTAssertEqual(object["xmp_conflict_policy"] as? String, "merge")
        XCTAssertEqual(object["min_confidence"] as? String, "high")
        XCTAssertEqual(object["allow_specific_tags"] as? Bool, true)
        XCTAssertEqual(object["pair_scope"] as? String, "raw-only")
        XCTAssertEqual(object["write_ai_json"] as? Bool, false)
    }

    func testCLIOverridesEnvironment() throws {
        let resolved = try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(
                mode: .both,
                existing: .skip,
                model: "cli:model",
                modelEndpoint: "http://localhost:9999",
                modelKeepAlive: "15m",
                logFormat: .json,
                clearDerivativeCacheOnStart: true,
                clearDerivativeCacheAfterSuccess: true,
                stageConcurrency: 7,
                modelResponseRepairAttempts: 3
            ),
            environment: [
                "AISIDECAR_MODE": "subject",
                "AISIDECAR_EXISTING": "overwrite",
                "AISIDECAR_MODEL": "env:model",
                "AISIDECAR_MODEL_ENDPOINT": "http://localhost:1111",
                "AISIDECAR_MODEL_KEEP_ALIVE": "0",
                "AISIDECAR_LOG_FORMAT": "text",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START": "false",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS": "false",
                "AISIDECAR_STAGE_CONCURRENCY": "5",
                "AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS": "2"
            ],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved.mode, .both)
        XCTAssertEqual(resolved.existing, .skip)
        XCTAssertEqual(resolved.model, "cli:model")
        XCTAssertEqual(resolved.modelEndpoint.absoluteString, "http://localhost:9999")
        XCTAssertEqual(resolved.modelKeepAlive, "15m")
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.clearDerivativeCacheOnStart)
        XCTAssertTrue(resolved.clearDerivativeCacheAfterSuccess)
        XCTAssertEqual(resolved.stageConcurrency, 7)
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 3)
    }

    func testXMPExportCLIOverridesEnvironment() throws {
        let resolved = try ConfigurationResolver.resolveXMPExport(
            cli: XMPExportConfigurationOverrides(
                recursive: false,
                outputDir: "/tmp/cli-xmp",
                logFormat: .text,
                dryRun: false,
                sourceRoot: "/tmp/cli-source",
                sourceVerification: .warn,
                writeFlatKeywords: true,
                writeHierarchicalKeywords: true,
                backupSidecars: true,
                xmpConflictPolicy: .backupAndMerge,
                minConfidence: .high,
                allowSpecificTags: false,
                pairScope: .rawOnly,
                writeAIJSON: true
            ),
            environment: [
                "AISIDECAR_RECURSIVE": "1",
                "AISIDECAR_OUTPUT_DIR": "/tmp/env-xmp",
                "AISIDECAR_LOG_FORMAT": "json",
                "AISIDECAR_DRY_RUN": "yes",
                "AISIDECAR_SOURCE_ROOT": "/tmp/env-source",
                "AISIDECAR_SOURCE_VERIFICATION": "skip",
                "AISIDECAR_WRITE_FLAT_KEYWORDS": "false",
                "AISIDECAR_WRITE_HIERARCHICAL_KEYWORDS": "false",
                "AISIDECAR_BACKUP_SIDECARS": "false",
                "AISIDECAR_XMP_CONFLICT_POLICY": "merge",
                "AISIDECAR_MIN_CONFIDENCE": "low",
                "AISIDECAR_ALLOW_SPECIFIC_TAGS": "true",
                "AISIDECAR_PAIR_SCOPE": "jpeg-only",
                "AISIDECAR_WRITE_AI_JSON": "false"
            ],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertFalse(resolved.recursive)
        XCTAssertEqual(resolved.outputDir, "/tmp/cli-xmp")
        XCTAssertEqual(resolved.logFormat, .text)
        XCTAssertFalse(resolved.dryRun)
        XCTAssertEqual(resolved.sourceRoot, "/tmp/cli-source")
        XCTAssertEqual(resolved.sourceVerification, .warn)
        XCTAssertTrue(resolved.writeFlatKeywords)
        XCTAssertTrue(resolved.writeHierarchicalKeywords)
        XCTAssertTrue(resolved.backupSidecars)
        XCTAssertEqual(resolved.xmpConflictPolicy, .backupAndMerge)
        XCTAssertEqual(resolved.minConfidence, .high)
        XCTAssertFalse(resolved.allowSpecificTags)
        XCTAssertEqual(resolved.pairScope, .rawOnly)
        XCTAssertTrue(resolved.writeAIJSON)
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

    func testDerivativeCacheResolutionUsesCachePrecedenceOnly() throws {
        let configPath = try writeConfig(
            """
            {
              "model_endpoint": "not-a-url",
              "profile": "unknown-profile",
              "derivative_cache_dir": "/tmp/file-cache",
              "derivative_cache_size_bytes": 1048576
            }
            """
        )

        let resolved = try ConfigurationResolver.resolveDerivativeCache(
            cli: DerivativeCacheConfigurationOverrides(
                derivativeCacheDir: "/tmp/cli-cache",
                derivativeCacheSizeBytes: 3_145_728
            ),
            environment: [
                "AISIDECAR_DERIVATIVE_CACHE_DIR": "/tmp/env-cache",
                "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "2097152"
            ],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/cli-cache")
        XCTAssertEqual(resolved.derivativeCacheSizeBytes, 3_145_728)
    }

    func testDerivativeCacheResolutionHonorsExplicitConfigPath() throws {
        let defaultPath = try writeConfig(#"{ "derivative_cache_dir": "/tmp/default-cache" }"#)
        let alternatePath = try writeConfig(#"{ "derivative_cache_dir": "/tmp/alternate-cache" }"#)

        let resolved = try ConfigurationResolver.resolveDerivativeCache(
            cli: DerivativeCacheConfigurationOverrides(configPath: alternatePath),
            environment: [:],
            defaultConfigPath: defaultPath
        )

        XCTAssertEqual(resolved.derivativeCacheDir, "/tmp/alternate-cache")
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
