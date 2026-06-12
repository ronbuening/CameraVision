import XCTest
@testable import AISidecarCore

final class ConfigValidationTests: XCTestCase {
    func testInvalidEnumFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "mode": "invalid" }"#)
            )
        }
    }

    func testInvalidURLFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "model_endpoint": "not-a-url" }"#)
            )
        }
    }

    func testMalformedJSONFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "mode": "whole" "#)
            )
        }
    }

    func testMissingExplicitConfigFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                cli: RunConfigurationOverrides(configPath: missingConfigPath()),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testYAMLConfigPathFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                cli: RunConfigurationOverrides(configPath: "\(NSTemporaryDirectory())config.yaml"),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testUnknownConfigKeyFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "surprise": true }"#)
            )
        }
    }

    func testInvalidSourceIdentityPolicyFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "source_identity_policy": "quick" }"#)
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_SOURCE_IDENTITY_POLICY": "quick"],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testUnknownModelInputProfileFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "profile": "custom-profile" }"#)
            )
        }
    }

    func testInvalidDerivativeCacheSizeFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "derivative_cache_size_bytes": 0 }"#)
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "large"],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testInvalidSubjectIsolationConfigFailsAsConfigInvalid() throws {
        for json in [
            #"{ "subject_crop_margin_fraction": 0 }"#,
            #"{ "subject_crop_margin_fraction": 1.1 }"#,
            #"{ "subject_merge_dominance_threshold": 0 }"#,
            #"{ "subject_merge_dominance_threshold": 1.1 }"#
        ] {
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolve(
                    environment: [:],
                    defaultConfigPath: writeConfig(json)
                )
            }
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_SUBJECT_CROP_MARGIN_FRACTION": "wide"],
                defaultConfigPath: missingConfigPath()
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_SUBJECT_MERGE_DOMINANCE_THRESHOLD": "wide"],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testInvalidStageConcurrencyFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "stage_concurrency": 0 }"#)
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_STAGE_CONCURRENCY": "wide"],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testInvalidModelResponseRepairAttemptsFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "model_response_repair_attempts": -1 }"#)
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS": "many"],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testInvalidXMPExportEnumFailsAsConfigInvalid() throws {
        for json in [
            #"{ "source_verification": "maybe" }"#,
            #"{ "xmp_conflict_policy": "replace" }"#,
            #"{ "min_confidence": "certain" }"#,
            #"{ "pair_scope": "tiff-only" }"#
        ] {
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolveXMPExport(
                    environment: [:],
                    defaultConfigPath: writeConfig(json)
                )
            }
        }

        for environment in [
            ["AISIDECAR_SOURCE_VERIFICATION": "maybe"],
            ["AISIDECAR_XMP_CONFLICT_POLICY": "replace"],
            ["AISIDECAR_MIN_CONFIDENCE": "certain"],
            ["AISIDECAR_PAIR_SCOPE": "tiff-only"]
        ] {
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolveXMPExport(
                    environment: environment,
                    defaultConfigPath: missingConfigPath()
                )
            }
        }
    }

    func testInvalidXMPExportBooleanFailsAsConfigInvalid() throws {
        for environment in [
            ["AISIDECAR_WRITE_FLAT_KEYWORDS": "maybe"],
            ["AISIDECAR_WRITE_HIERARCHICAL_KEYWORDS": "maybe"],
            ["AISIDECAR_BACKUP_SIDECARS": "maybe"],
            ["AISIDECAR_ALLOW_SPECIFIC_TAGS": "maybe"],
            ["AISIDECAR_WRITE_AI_JSON": "maybe"]
        ] {
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolveXMPExport(
                    environment: environment,
                    defaultConfigPath: missingConfigPath()
                )
            }
        }
    }

    func testXMPBackupAndMergeRequiresBackups() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveXMPExport(
                environment: [:],
                defaultConfigPath: writeConfig(
                    #"{ "xmp_conflict_policy": "backup-and-merge", "backup_sidecars": false }"#
                )
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveXMPExport(
                cli: XMPExportConfigurationOverrides(
                    backupSidecars: false,
                    xmpConflictPolicy: .backupAndMerge
                ),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testInvalidModelKeepAliveFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "model_keep_alive": "" }"#)
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_MODEL_KEEP_ALIVE": "   "],
                defaultConfigPath: missingConfigPath()
            )
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
