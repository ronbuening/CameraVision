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
        XCTAssertEqual(resolved.modelTimeoutSeconds, 180)
        XCTAssertEqual(resolved.modelRetryLimit, 2)
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 1)
        XCTAssertEqual(resolved.gpsContext, .coarse)
        XCTAssertEqual(resolved.taskProfile, .tagging)
        // 0 = "model default": the pipeline sends no num_ctx until a positive
        // value is configured.
        XCTAssertEqual(resolved.modelContextWindow, 0)
        XCTAssertEqual(resolved.modelMaxResponseTokens, 2_048)
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
        XCTAssertEqual(resolved.qualityGrading, .builtInDefaults)
        XCTAssertFalse(resolved.qualityGrading.enabled)
        XCTAssertEqual(resolved.qualityGrading.conflictPolicy, .preserve)
        XCTAssertEqual(resolved.qualityGrading.policy.urgencyMap, [.reject: 1, .excellent: 2])
        XCTAssertFalse(resolved.qualityGrading.policy.writeRating)
        XCTAssertTrue(resolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(resolved.qualityGrading.policy.flagMap, [.reject: .reject, .excellent: .pick])
    }

    func testNormalizationDefaultsIncludeDormantQualityGrading() throws {
        let resolved = try ConfigurationResolver.resolveNormalization(
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved, .builtInDefaults)
        XCTAssertEqual(resolved.qualityGrading, .builtInDefaults)
    }

    func testNormalizationQualityGradingUsesFileEnvironmentAndCLIPrecedence() throws {
        let configPath = try writeConfig(
            """
            {
              "xmp_quality_grading": false,
              "xmp_quality_write_flag": false,
              "xmp_quality_rating_map": { "good": 3 }
            }
            """
        )

        let fileResolved = try ConfigurationResolver.resolveNormalization(
            environment: [:],
            defaultConfigPath: configPath
        )
        XCTAssertFalse(fileResolved.qualityGrading.enabled)
        XCTAssertFalse(fileResolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(fileResolved.qualityGrading.policy.ratingMap, [.good: 3])

        let environmentResolved = try ConfigurationResolver.resolveNormalization(
            environment: [
                "AISIDECAR_XMP_QUALITY_GRADING": "true",
                "AISIDECAR_XMP_QUALITY_WRITE_FLAG": "true",
            ],
            defaultConfigPath: configPath
        )
        XCTAssertTrue(environmentResolved.qualityGrading.enabled)
        XCTAssertTrue(environmentResolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(environmentResolved.qualityGrading.policy.ratingMap, [.good: 3])

        let cliResolved = try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(
                qualityGrading: QualityGradingConfigurationOverrides(
                    enabled: false,
                    writeFlag: false,
                    ratingMap: [.good: 4]
                )
            ),
            environment: [
                "AISIDECAR_XMP_QUALITY_GRADING": "true",
                "AISIDECAR_XMP_QUALITY_WRITE_FLAG": "true",
            ],
            defaultConfigPath: configPath
        )
        XCTAssertFalse(cliResolved.qualityGrading.enabled)
        XCTAssertFalse(cliResolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(cliResolved.qualityGrading.policy.ratingMap, [.good: 4])
    }

    func testApplySessionQualityGradingUsesFileEnvironmentAndCLIPrecedence() throws {
        let configPath = try writeConfig(
            """
            {
              "xmp_quality_grading": false,
              "xmp_quality_write_label": false,
              "xmp_quality_rating_map": { "good": 3 }
            }
            """
        )

        let fileResolved = try ConfigurationResolver.resolveApplySession(
            environment: [:],
            defaultConfigPath: configPath
        )
        XCTAssertFalse(fileResolved.qualityGrading.enabled)
        XCTAssertFalse(fileResolved.qualityGrading.policy.writeLabel)
        XCTAssertEqual(fileResolved.qualityGrading.policy.ratingMap, [.good: 3])

        let environmentResolved = try ConfigurationResolver.resolveApplySession(
            environment: [
                "AISIDECAR_XMP_QUALITY_GRADING": "true",
                "AISIDECAR_XMP_QUALITY_WRITE_LABEL": "true",
            ],
            defaultConfigPath: configPath
        )
        XCTAssertTrue(environmentResolved.qualityGrading.enabled)
        XCTAssertTrue(environmentResolved.qualityGrading.policy.writeLabel)
        XCTAssertEqual(environmentResolved.qualityGrading.policy.ratingMap, [.good: 3])

        let cliResolved = try ConfigurationResolver.resolveApplySession(
            cli: ApplySessionConfigurationOverrides(
                qualityGrading: QualityGradingConfigurationOverrides(
                    enabled: false,
                    writeLabel: false,
                    ratingMap: [.good: 4]
                )
            ),
            environment: [
                "AISIDECAR_XMP_QUALITY_GRADING": "true",
                "AISIDECAR_XMP_QUALITY_WRITE_LABEL": "true",
            ],
            defaultConfigPath: configPath
        )
        XCTAssertFalse(cliResolved.qualityGrading.enabled)
        XCTAssertFalse(cliResolved.qualityGrading.policy.writeLabel)
        XCTAssertEqual(cliResolved.qualityGrading.policy.ratingMap, [.good: 4])
    }

    func testQualityAssessmentEnvironmentOverridesConfigFile() throws {
        let configPath = try writeConfig(
            """
            {
              "quality_assessment": true
            }
            """
        )

        let disabledByEnvironment = try ConfigurationResolver.resolve(
            environment: ["AISIDECAR_QUALITY_ASSESSMENT": "false"],
            defaultConfigPath: configPath
        )
        XCTAssertEqual(disabledByEnvironment.taskProfile, .tagging)

        let enabledByEnvironment = try ConfigurationResolver.resolve(
            environment: ["AISIDECAR_QUALITY_ASSESSMENT": "true"],
            defaultConfigPath: configPath
        )
        XCTAssertEqual(enabledByEnvironment.taskProfile, .taggingWithQuality)
    }

    func testQualityScanModeDefaultsToCombined() throws {
        let resolved = try ConfigurationResolver.resolve(
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )
        XCTAssertEqual(resolved.qualityScanMode, .combined)
    }

    func testQualityScanModePrecedenceChain() throws {
        let configPath = try writeConfig(
            """
            {
              "quality_scan_mode": "sequential"
            }
            """
        )

        let fileResolved = try ConfigurationResolver.resolve(
            environment: [:],
            defaultConfigPath: configPath
        )
        XCTAssertEqual(fileResolved.qualityScanMode, .sequential)

        let environmentResolved = try ConfigurationResolver.resolve(
            environment: ["AISIDECAR_QUALITY_SCAN_MODE": "combined"],
            defaultConfigPath: configPath
        )
        XCTAssertEqual(environmentResolved.qualityScanMode, .combined)

        let cliResolved = try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(qualityScanMode: .sequential),
            environment: ["AISIDECAR_QUALITY_SCAN_MODE": "combined"],
            defaultConfigPath: configPath
        )
        XCTAssertEqual(cliResolved.qualityScanMode, .sequential)
    }

    func testQualityScanModeRejectsUnknownValues() throws {
        XCTAssertThrowsError(
            try ConfigurationResolver.resolve(
                environment: ["AISIDECAR_QUALITY_SCAN_MODE": "twice"],
                defaultConfigPath: missingConfigPath()
            )
        )
        let configPath = try writeConfig(
            """
            {
              "quality_scan_mode": "twice"
            }
            """
        )
        XCTAssertThrowsError(
            try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: configPath)
        )
    }

    func testQualityScanModeUsesStableProvenanceJSONKey() throws {
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.qualityScanMode = .sequential

        let data = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["quality_scan_mode"] as? String, "sequential")
        XCTAssertNil(object["qualityScanMode"])
        XCTAssertEqual(try JSONDecoder().decode(ResolvedRunConfiguration.self, from: data), configuration)
    }

    func testResolvedConfigurationDecodesWhenQualityScanModeKeyIsMissing() throws {
        let data = try JSONEncoder().encode(ResolvedRunConfiguration.builtInDefaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "quality_scan_mode")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ResolvedRunConfiguration.self, from: stripped)
        XCTAssertEqual(decoded.qualityScanMode, .combined)
    }

    func testTaskProfileUsesStableProvenanceJSONKey() throws {
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.taskProfile = .taggingWithQuality

        let data = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["task_profile"] as? String, "tagging_with_quality")
        XCTAssertNil(object["taskProfile"])
        XCTAssertEqual(try JSONDecoder().decode(ResolvedRunConfiguration.self, from: data), configuration)
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
              "model_timeout_seconds": 420,
              "model_retry_limit": 4,
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
              "model_response_repair_attempts": 0,
              "gps_context": "exact",
              "model_context_window": 16384,
              "model_max_response_tokens": 1024
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
        XCTAssertEqual(resolved.modelTimeoutSeconds, 420)
        XCTAssertEqual(resolved.modelRetryLimit, 4)
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
        XCTAssertEqual(resolved.gpsContext, .exact)
        XCTAssertEqual(resolved.modelContextWindow, 16_384)
        XCTAssertEqual(resolved.modelMaxResponseTokens, 1_024)
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
              "write_ai_json": false,
              "xmp_quality_grading": true,
              "xmp_quality_conflicts": "refresh",
              "xmp_quality_min_confidence": "high",
              "xmp_quality_write_rating": false,
              "xmp_quality_write_label": false,
              "xmp_quality_write_urgency": false,
              "xmp_quality_write_flag": false,
              "xmp_quality_write_keywords": false,
              "xmp_quality_reject_as_minus_one": true,
              "xmp_quality_per_criterion_problem_keywords": true,
              "xmp_quality_keyword_root": "Review Quality",
              "xmp_quality_rating_map": { "reject": -1, "excellent": 4 },
              "xmp_quality_label_map": { "good": "Blue" },
              "xmp_quality_urgency_map": { "good": 3 },
              "xmp_quality_flag_map": { "good": "pick" }
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
        XCTAssertTrue(resolved.qualityGrading.enabled)
        XCTAssertEqual(resolved.qualityGrading.conflictPolicy, .refresh)
        XCTAssertEqual(resolved.qualityGrading.policy.minimumConfidence, .high)
        XCTAssertFalse(resolved.qualityGrading.policy.writeRating)
        XCTAssertFalse(resolved.qualityGrading.policy.writeLabel)
        XCTAssertFalse(resolved.qualityGrading.policy.writeUrgency)
        XCTAssertFalse(resolved.qualityGrading.policy.writeKeywords)
        XCTAssertTrue(resolved.qualityGrading.policy.rejectAsMinusOne)
        XCTAssertTrue(resolved.qualityGrading.policy.perCriterionProblemKeywords)
        XCTAssertEqual(resolved.qualityGrading.policy.keywordRoot, "Review Quality")
        XCTAssertEqual(resolved.qualityGrading.policy.ratingMap, [.reject: -1, .excellent: 4])
        XCTAssertEqual(resolved.qualityGrading.policy.labelMap, [.good: "Blue"])
        XCTAssertEqual(resolved.qualityGrading.policy.urgencyMap, [.good: 3])
        XCTAssertFalse(resolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(resolved.qualityGrading.policy.flagMap, [.good: .pick])
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
                "AISIDECAR_MODEL_TIMEOUT_SECONDS": "360",
                "AISIDECAR_MODEL_RETRY_LIMIT": "5",
                "AISIDECAR_LOG_LEVEL": "debug",
                "AISIDECAR_SOURCE_IDENTITY_POLICY": "sha256",
                "AISIDECAR_DERIVATIVE_CACHE_DIR": "/tmp/env-cache",
                "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "2097152",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START": "yes",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS": "1",
                "AISIDECAR_SUBJECT_CROP_MARGIN_FRACTION": "0.15",
                "AISIDECAR_SUBJECT_MERGE_DOMINANCE_THRESHOLD": "0.65",
                "AISIDECAR_STAGE_CONCURRENCY": "5",
                "AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS": "2",
                "AISIDECAR_GPS_CONTEXT": "off",
                "AISIDECAR_MODEL_CONTEXT_WINDOW": "4096",
            ],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.mode, .subject)
        XCTAssertEqual(resolved.existing, .overwrite)
        XCTAssertEqual(resolved.model, "env:model")
        XCTAssertEqual(resolved.modelKeepAlive, "0")
        XCTAssertEqual(resolved.modelTimeoutSeconds, 360)
        XCTAssertEqual(resolved.modelRetryLimit, 5)
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
        XCTAssertEqual(resolved.gpsContext, .off)
        XCTAssertEqual(resolved.modelContextWindow, 4_096)
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
              "write_ai_json": true,
              "xmp_quality_grading": false,
              "xmp_quality_conflicts": "preserve",
              "xmp_quality_min_confidence": "medium",
              "xmp_quality_write_rating": true,
              "xmp_quality_write_label": true,
              "xmp_quality_write_urgency": true,
              "xmp_quality_write_flag": true,
              "xmp_quality_write_keywords": true,
              "xmp_quality_reject_as_minus_one": false,
              "xmp_quality_per_criterion_problem_keywords": false,
              "xmp_quality_keyword_root": "File Quality",
              "xmp_quality_rating_map": { "neutral": 2 },
              "xmp_quality_label_map": { "neutral": "Yellow" },
              "xmp_quality_urgency_map": { "neutral": 7 },
              "xmp_quality_flag_map": { "neutral": "reject" }
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
                "AISIDECAR_WRITE_AI_JSON": "false",
                "AISIDECAR_XMP_QUALITY_GRADING": "yes",
                "AISIDECAR_XMP_QUALITY_CONFLICTS": "overwrite",
                "AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE": "low",
                "AISIDECAR_XMP_QUALITY_WRITE_RATING": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_LABEL": "0",
                "AISIDECAR_XMP_QUALITY_WRITE_URGENCY": "no",
                "AISIDECAR_XMP_QUALITY_WRITE_FLAG": "no",
                "AISIDECAR_XMP_QUALITY_WRITE_KEYWORDS": "false",
                "AISIDECAR_XMP_QUALITY_REJECT_AS_MINUS_ONE": "true",
                "AISIDECAR_XMP_QUALITY_PER_CRITERION_PROBLEM_KEYWORDS": "1",
                "AISIDECAR_XMP_QUALITY_KEYWORD_ROOT": "Environment Quality",
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
        XCTAssertTrue(resolved.qualityGrading.enabled)
        XCTAssertEqual(resolved.qualityGrading.conflictPolicy, .overwrite)
        XCTAssertEqual(resolved.qualityGrading.policy.minimumConfidence, .low)
        XCTAssertFalse(resolved.qualityGrading.policy.writeRating)
        XCTAssertFalse(resolved.qualityGrading.policy.writeLabel)
        XCTAssertFalse(resolved.qualityGrading.policy.writeUrgency)
        XCTAssertFalse(resolved.qualityGrading.policy.writeKeywords)
        XCTAssertTrue(resolved.qualityGrading.policy.rejectAsMinusOne)
        XCTAssertTrue(resolved.qualityGrading.policy.perCriterionProblemKeywords)
        XCTAssertEqual(resolved.qualityGrading.policy.keywordRoot, "Environment Quality")
        XCTAssertEqual(resolved.qualityGrading.policy.ratingMap, [.neutral: 2])
        XCTAssertEqual(resolved.qualityGrading.policy.labelMap, [.neutral: "Yellow"])
        XCTAssertEqual(resolved.qualityGrading.policy.urgencyMap, [.neutral: 7])
        XCTAssertFalse(resolved.qualityGrading.policy.writeFlag)
        XCTAssertEqual(resolved.qualityGrading.policy.flagMap, [.neutral: .reject])
    }

    func testSourceIdentityPolicyUsesStableJSONKey() throws {
        let config = AppConfig(
            qualityAssessment: true,
            modelKeepAlive: "5m",
            modelTimeoutSeconds: 240,
            modelRetryLimit: 6,
            sourceIdentityPolicy: .fast,
            clearDerivativeCacheOnStart: true,
            clearDerivativeCacheAfterSuccess: true,
            subjectCropMarginFraction: 0.12,
            subjectMergeDominanceThreshold: 0.75,
            stageConcurrency: 3,
            modelResponseRepairAttempts: 0,
            gpsContext: .exact,
            sourceRoot: "/tmp/source-root",
            sourceVerification: .warn,
            writeFlatKeywords: false,
            writeHierarchicalKeywords: true,
            backupSidecars: false,
            xmpConflictPolicy: .merge,
            minConfidence: .high,
            allowSpecificTags: true,
            pairScope: .rawOnly,
            writeAIJSON: false,
            xmpQualityGrading: true,
            xmpQualityConflicts: .refresh,
            xmpQualityMinConfidence: .high,
            xmpQualityWriteRating: false,
            xmpQualityWriteLabel: false,
            xmpQualityWriteUrgency: false,
            xmpQualityWriteKeywords: false,
            xmpQualityRejectAsMinusOne: true,
            xmpQualityPerCriterionProblemKeywords: true,
            xmpQualityKeywordRoot: "Review Quality",
            xmpQualityRatingMap: [.belowAverage: 2],
            xmpQualityLabelMap: [.excellent: "Green"],
            xmpQualityUrgencyMap: [.excellent: 2]
        )
        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["source_identity_policy"] as? String, "fast")
        XCTAssertNil(object["sourceIdentityPolicy"])
        XCTAssertEqual(object["model_keep_alive"] as? String, "5m")
        XCTAssertEqual(object["model_timeout_seconds"] as? Double, 240)
        XCTAssertEqual(object["model_retry_limit"] as? Int, 6)
        XCTAssertEqual(object["clear_derivative_cache_on_start"] as? Bool, true)
        XCTAssertEqual(object["clear_derivative_cache_after_success"] as? Bool, true)
        XCTAssertEqual(object["subject_crop_margin_fraction"] as? Double, 0.12)
        XCTAssertEqual(object["subject_merge_dominance_threshold"] as? Double, 0.75)
        XCTAssertEqual(object["stage_concurrency"] as? Int, 3)
        XCTAssertEqual(object["model_response_repair_attempts"] as? Int, 0)
        XCTAssertEqual(object["gps_context"] as? String, "exact")
        XCTAssertEqual(object["quality_assessment"] as? Bool, true)
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
        XCTAssertEqual(object["xmp_quality_grading"] as? Bool, true)
        XCTAssertEqual(object["xmp_quality_conflicts"] as? String, "refresh")
        XCTAssertEqual(object["xmp_quality_min_confidence"] as? String, "high")
        XCTAssertEqual(object["xmp_quality_write_rating"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_label"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_urgency"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_write_keywords"] as? Bool, false)
        XCTAssertEqual(object["xmp_quality_reject_as_minus_one"] as? Bool, true)
        XCTAssertEqual(object["xmp_quality_per_criterion_problem_keywords"] as? Bool, true)
        XCTAssertEqual(object["xmp_quality_keyword_root"] as? String, "Review Quality")
        XCTAssertEqual((object["xmp_quality_rating_map"] as? [String: Int])?["below_average"], 2)
        XCTAssertEqual((object["xmp_quality_label_map"] as? [String: String])?["excellent"], "Green")
        XCTAssertEqual((object["xmp_quality_urgency_map"] as? [String: Int])?["excellent"], 2)
    }

    func testCLIOverridesEnvironment() throws {
        let resolved = try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(
                mode: .both,
                existing: .skip,
                model: "cli:model",
                modelEndpoint: "http://localhost:9999",
                modelKeepAlive: "15m",
                modelTimeoutSeconds: 300,
                modelRetryLimit: 7,
                logFormat: .json,
                clearDerivativeCacheOnStart: true,
                clearDerivativeCacheAfterSuccess: true,
                stageConcurrency: 7,
                modelResponseRepairAttempts: 3,
                gpsContext: .exact,
                modelContextWindow: 32_768
            ),
            environment: [
                "AISIDECAR_MODE": "subject",
                "AISIDECAR_EXISTING": "overwrite",
                "AISIDECAR_MODEL": "env:model",
                "AISIDECAR_MODEL_ENDPOINT": "http://localhost:1111",
                "AISIDECAR_MODEL_KEEP_ALIVE": "0",
                "AISIDECAR_MODEL_TIMEOUT_SECONDS": "240",
                "AISIDECAR_MODEL_RETRY_LIMIT": "6",
                "AISIDECAR_LOG_FORMAT": "text",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_ON_START": "false",
                "AISIDECAR_CLEAR_DERIVATIVE_CACHE_AFTER_SUCCESS": "false",
                "AISIDECAR_STAGE_CONCURRENCY": "5",
                "AISIDECAR_MODEL_RESPONSE_REPAIR_ATTEMPTS": "2",
                "AISIDECAR_GPS_CONTEXT": "off",
                "AISIDECAR_MODEL_CONTEXT_WINDOW": "4096",
            ],
            defaultConfigPath: missingConfigPath()
        )

        XCTAssertEqual(resolved.mode, .both)
        XCTAssertEqual(resolved.existing, .skip)
        XCTAssertEqual(resolved.model, "cli:model")
        XCTAssertEqual(resolved.modelEndpoint.absoluteString, "http://localhost:9999")
        XCTAssertEqual(resolved.modelKeepAlive, "15m")
        XCTAssertEqual(resolved.modelTimeoutSeconds, 300)
        XCTAssertEqual(resolved.modelRetryLimit, 7)
        XCTAssertEqual(resolved.logFormat, .json)
        XCTAssertTrue(resolved.clearDerivativeCacheOnStart)
        XCTAssertTrue(resolved.clearDerivativeCacheAfterSuccess)
        XCTAssertEqual(resolved.stageConcurrency, 7)
        XCTAssertEqual(resolved.modelResponseRepairAttempts, 3)
        XCTAssertEqual(resolved.gpsContext, .exact)
        XCTAssertEqual(resolved.modelContextWindow, 32_768)
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
                writeAIJSON: true,
                qualityGrading: QualityGradingConfigurationOverrides(
                    enabled: true,
                    conflictPolicy: .refresh,
                    minimumConfidence: .high,
                    writeRating: true,
                    writeLabel: true,
                    writeUrgency: true,
                    writeFlag: true,
                    writeKeywords: true
                )
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
                "AISIDECAR_WRITE_AI_JSON": "false",
                "AISIDECAR_XMP_QUALITY_GRADING": "false",
                "AISIDECAR_XMP_QUALITY_CONFLICTS": "overwrite",
                "AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE": "low",
                "AISIDECAR_XMP_QUALITY_WRITE_RATING": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_LABEL": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_URGENCY": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_FLAG": "false",
                "AISIDECAR_XMP_QUALITY_WRITE_KEYWORDS": "false",
                "AISIDECAR_XMP_QUALITY_REJECT_AS_MINUS_ONE": "true",
                "AISIDECAR_XMP_QUALITY_PER_CRITERION_PROBLEM_KEYWORDS": "true",
                "AISIDECAR_XMP_QUALITY_KEYWORD_ROOT": "Environment Quality",
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
        XCTAssertTrue(resolved.qualityGrading.enabled)
        XCTAssertEqual(resolved.qualityGrading.conflictPolicy, .refresh)
        XCTAssertEqual(resolved.qualityGrading.policy.minimumConfidence, .high)
        XCTAssertTrue(resolved.qualityGrading.policy.writeRating)
        XCTAssertTrue(resolved.qualityGrading.policy.writeLabel)
        XCTAssertTrue(resolved.qualityGrading.policy.writeUrgency)
        XCTAssertTrue(resolved.qualityGrading.policy.writeFlag)
        XCTAssertTrue(resolved.qualityGrading.policy.writeKeywords)
        XCTAssertTrue(resolved.qualityGrading.policy.rejectAsMinusOne)
        XCTAssertTrue(resolved.qualityGrading.policy.perCriterionProblemKeywords)
        XCTAssertEqual(resolved.qualityGrading.policy.keywordRoot, "Environment Quality")
        XCTAssertEqual(resolved.qualityGrading.policy.ratingMap, QualityGradingPolicy.builtInDefaults.ratingMap)
    }

    func testResolvedXMPExportConfigurationRoundTripsAndDefaultsLegacyQualityBlock() throws {
        var current = ResolvedXMPExportConfiguration.builtInDefaults
        current.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .refresh,
            policy: QualityGradingPolicy(keywordRoot: "Review Quality")
        )

        let data = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let qualityObject = try XCTUnwrap(object["quality_grading"] as? [String: Any])
        XCTAssertEqual(qualityObject["conflict_policy"] as? String, "refresh")
        XCTAssertEqual(try JSONDecoder().decode(ResolvedXMPExportConfiguration.self, from: data), current)

        object.removeValue(forKey: "quality_grading")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let legacy = try JSONDecoder().decode(ResolvedXMPExportConfiguration.self, from: legacyData)
        XCTAssertEqual(legacy.qualityGrading, .builtInDefaults)
    }

    func testResolvedNormalizationConfigurationRoundTripsAndDefaultsLegacyQualityBlock() throws {
        var current = ResolvedNormalizationConfiguration.builtInDefaults
        current.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .refresh,
            policy: QualityGradingPolicy(keywordRoot: "Review Quality")
        )

        let data = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let qualityObject = try XCTUnwrap(object["quality_grading"] as? [String: Any])
        XCTAssertEqual(qualityObject["conflict_policy"] as? String, "refresh")
        XCTAssertEqual(try JSONDecoder().decode(ResolvedNormalizationConfiguration.self, from: data), current)

        object.removeValue(forKey: "quality_grading")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let legacy = try JSONDecoder().decode(ResolvedNormalizationConfiguration.self, from: legacyData)
        XCTAssertEqual(legacy.qualityGrading, .builtInDefaults)

        let defaultData = try JSONEncoder().encode(ResolvedNormalizationConfiguration.builtInDefaults)
        let defaultObject = try XCTUnwrap(JSONSerialization.jsonObject(with: defaultData) as? [String: Any])
        XCTAssertNil(defaultObject["quality_grading"])
    }

    func testResolvedApplySessionConfigurationRoundTripsAndDefaultsLegacyQualityBlock() throws {
        var current = ResolvedApplySessionConfiguration.builtInDefaults
        current.qualityGrading = ResolvedQualityGradingConfiguration(
            enabled: true,
            conflictPolicy: .refresh,
            policy: QualityGradingPolicy(keywordRoot: "Review Quality")
        )

        let data = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let qualityObject = try XCTUnwrap(object["quality_grading"] as? [String: Any])
        XCTAssertEqual(qualityObject["conflict_policy"] as? String, "refresh")
        XCTAssertEqual(try JSONDecoder().decode(ResolvedApplySessionConfiguration.self, from: data), current)

        object.removeValue(forKey: "quality_grading")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let legacy = try JSONDecoder().decode(ResolvedApplySessionConfiguration.self, from: legacyData)
        XCTAssertEqual(legacy.qualityGrading, .builtInDefaults)

        let defaultData = try JSONEncoder().encode(ResolvedApplySessionConfiguration.builtInDefaults)
        let defaultObject = try XCTUnwrap(JSONSerialization.jsonObject(with: defaultData) as? [String: Any])
        XCTAssertNil(defaultObject["quality_grading"])
    }

    func testXMPQualityGradingResolutionRejectsInvalidPoliciesWhileDisabled() throws {
        let invalidConfigurations = [
            #"{ "xmp_quality_rating_map": { "good": 6 } }"#,
            #"{ "xmp_quality_urgency_map": { "excellent": 0 } }"#,
            #"{ "xmp_quality_label_map": { "excellent": " " } }"#,
            #"{ "xmp_quality_keyword_root": "AI|Quality" }"#,
            #"{ "xmp_quality_rating_map": { "future": 3 } }"#,
        ]

        for contents in invalidConfigurations {
            let configPath = try writeConfig(contents)
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolveXMPExport(
                    environment: [:],
                    defaultConfigPath: configPath
                )
            }
        }
    }

    func testNormalizationQualityGradingRejectsInvalidPoliciesWhileDisabled() throws {
        let configPath = try writeConfig(#"{ "xmp_quality_rating_map": { "good": 6 } }"#)

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveNormalization(
                environment: [:],
                defaultConfigPath: configPath
            )
        }
    }

    func testApplySessionQualityGradingRejectsInvalidPoliciesWhileDisabled() throws {
        let configPath = try writeConfig(#"{ "xmp_quality_rating_map": { "good": 6 } }"#)

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveApplySession(
                environment: [:],
                defaultConfigPath: configPath
            )
        }
    }

    func testXMPQualityGradingResolutionRejectsInvalidEnvironmentValues() throws {
        let invalidEnvironments = [
            ["AISIDECAR_XMP_QUALITY_GRADING": "sometimes"],
            ["AISIDECAR_XMP_QUALITY_CONFLICTS": "replace"],
            ["AISIDECAR_XMP_QUALITY_MIN_CONFIDENCE": "very-high"],
            ["AISIDECAR_XMP_QUALITY_WRITE_RATING": "perhaps"],
        ]

        for environment in invalidEnvironments {
            try assertConfigInvalid {
                _ = try ConfigurationResolver.resolveXMPExport(
                    environment: environment,
                    defaultConfigPath: missingConfigPath()
                )
            }
        }
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
              "model_timeout_seconds": "slow",
              "model_retry_limit": "many",
              "profile": "unknown-profile",
              "gps_context": "precise",
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
                "AISIDECAR_DERIVATIVE_CACHE_SIZE_BYTES": "2097152",
                "AISIDECAR_GPS_CONTEXT": "precise",
                "AISIDECAR_MODEL_TIMEOUT_SECONDS": "not-a-number",
                "AISIDECAR_MODEL_RETRY_LIMIT": "not-a-number",
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
