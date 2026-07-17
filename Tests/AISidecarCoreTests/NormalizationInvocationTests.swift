import XCTest

@testable import AISidecarCore

final class NormalizationInvocationTests: XCTestCase {
    func testNormalizeRequiresExactlyOneInputMode() throws {
        try assertConfigInvalid {
            _ = try NormalizationInvocationValidator.validate(NormalizationInvocationRequest())
        }

        try assertConfigInvalid {
            _ = try NormalizationInvocationValidator.validate(
                NormalizationInvocationRequest(inputPath: "Images", fromJSONPath: "sidecars")
            )
        }

        let fileList = try NormalizationInvocationValidator.validate(
            NormalizationInvocationRequest(fileListPath: "images.txt", mode: .both)
        )
        XCTAssertEqual(fileList, .fileList(path: "images.txt"))
    }

    func testNormalizeRejectsFromJSONWithAnalyzeOnlyOptions() throws {
        let invalidRequests = [
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", mode: .both),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", existing: .overwrite),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", model: "custom:model"),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", modelEndpoint: "http://localhost:11434"),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", modelTimeoutSeconds: 180),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", modelRetryLimit: 2),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", profile: "gemma4-26b-default"),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", debugDerivatives: true),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", clearDerivativeCacheOnStart: true),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", clearDerivativeCacheAfterSuccess: true),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", stageConcurrency: 1),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", modelResponseRepairAttempts: 1),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", gpsContext: .coarse),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", writeAIJSON: true),
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", noWriteAIJSON: true),
        ]

        for request in invalidRequests {
            try assertConfigInvalid {
                _ = try NormalizationInvocationValidator.validate(request)
            }
        }
    }

    func testNormalizeRejectsSourceRootOutsideFromJSON() throws {
        try assertConfigInvalid {
            _ = try NormalizationInvocationValidator.validate(
                NormalizationInvocationRequest(inputPath: "Images", sourceRoot: "/tmp/source")
            )
        }

        try assertConfigInvalid {
            _ = try NormalizationInvocationValidator.validate(
                NormalizationInvocationRequest(fileListPath: "images.txt", sourceVerification: .warn)
            )
        }
    }

    func testNormalizeAssessQualityIsValidOnlyForPositionalAnalyzeMode() throws {
        let analyze = try NormalizationInvocationValidator.validate(
            NormalizationInvocationRequest(inputPath: "Images", assessQuality: true)
        )
        XCTAssertEqual(analyze, .analyze(inputPath: "Images"))

        for request in [
            NormalizationInvocationRequest(fromJSONPath: "A.ai.json", assessQuality: true),
            NormalizationInvocationRequest(fileListPath: "images.txt", assessQuality: true),
        ] {
            try assertConfigInvalid {
                _ = try NormalizationInvocationValidator.validate(request)
            }
        }
    }

    func testNormalizeRejectsConflictingBooleanPairs() throws {
        let invalidRequests = [
            NormalizationInvocationRequest(inputPath: "Images", writeFlatKeywords: true, noWriteFlatKeywords: true),
            NormalizationInvocationRequest(
                inputPath: "Images",
                writeHierarchicalKeywords: true,
                noWriteHierarchicalKeywords: true
            ),
            NormalizationInvocationRequest(inputPath: "Images", backupSidecars: true, noBackupSidecars: true),
            NormalizationInvocationRequest(inputPath: "Images", writeRating: true, noWriteRating: true),
            NormalizationInvocationRequest(inputPath: "Images", writeLabel: true, noWriteLabel: true),
            NormalizationInvocationRequest(inputPath: "Images", writeUrgency: true, noWriteUrgency: true),
            NormalizationInvocationRequest(inputPath: "Images", writeFlag: true, noWriteFlag: true),
            NormalizationInvocationRequest(
                inputPath: "Images",
                writeQualityKeywords: true,
                noWriteQualityKeywords: true
            ),
            NormalizationInvocationRequest(inputPath: "Images", writeAIJSON: true, noWriteAIJSON: true),
        ]

        for request in invalidRequests {
            try assertConfigInvalid {
                _ = try NormalizationInvocationValidator.validate(request)
            }
        }
    }

    func testNormalizeAcceptsQualityGradingOptionsForExistingAndAnalyzeInputs() throws {
        let fromJSON = try NormalizationInvocationValidator.validate(
            NormalizationInvocationRequest(
                fromJSONPath: "A.ai.json",
                qualityGrading: true,
                qualityConflicts: .overwrite,
                qualityMinConfidence: .low,
                noWriteRating: true,
                writeLabel: true,
                noWriteUrgency: true,
                writeFlag: true,
                writeQualityKeywords: true
            )
        )
        XCTAssertEqual(fromJSON, .fromJSON(path: "A.ai.json"))

        let analyze = try NormalizationInvocationValidator.validate(
            NormalizationInvocationRequest(
                inputPath: "Images",
                qualityGrading: true,
                qualityConflicts: .refresh,
                qualityMinConfidence: .high,
                writeRating: true,
                noWriteLabel: true,
                writeUrgency: true,
                noWriteFlag: true,
                noWriteQualityKeywords: true
            )
        )
        XCTAssertEqual(analyze, .analyze(inputPath: "Images"))
    }

    func testApplySessionRejectsDecisionFlagsAndRequiresSessionPath() throws {
        try assertConfigInvalid {
            _ = try ApplySessionInvocationValidator.validate(ApplySessionInvocationRequest())
        }

        try assertConfigInvalid {
            _ = try ApplySessionInvocationValidator.validate(
                ApplySessionInvocationRequest(
                    sessionPath: "normalization-session.json",
                    invalidNormalizationFlags: ["--normalization-mode", "--min-confidence"]
                )
            )
        }

        try assertConfigInvalid {
            _ = try ApplySessionInvocationValidator.validate(
                ApplySessionInvocationRequest(
                    sessionPath: "normalization-session.json",
                    backupSidecars: true,
                    noBackupSidecars: true
                )
            )
        }

        let session = try ApplySessionInvocationValidator.validate(
            ApplySessionInvocationRequest(sessionPath: "normalization-session.json")
        )
        XCTAssertEqual(session, "normalization-session.json")
    }

    func testNormalizationSchemaIdentifierConstantsAreStable() {
        XCTAssertEqual(NormalizationSchemaIdentifiers.vocabulary, "ai-sidecar-vocabulary/1.0")
        XCTAssertEqual(NormalizationSchemaIdentifiers.session, "ai-sidecar-normalization/1.0")
        XCTAssertEqual(NormalizationSchemaIdentifiers.report, "ai-sidecar-normalization-report/1.0")
        XCTAssertEqual(SidecarErrorCode.vocabularyInvalid.rawValue, "E_VOCABULARY_INVALID")
        XCTAssertEqual(SidecarErrorCode.sessionStale.rawValue, "E_SESSION_STALE")
    }

    func testNormalizationDefaultsAndPrecedence() throws {
        let configPath = try writeConfig(
            """
            {
              "normalization_mode": "off",
              "consensus_threshold": 0.4,
              "affinity_profile": "aggressive",
              "session_subject": "Birds",
              "allow_session_subject_propagation": false
            }
            """
        )

        let resolved = try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(
                normalizationMode: .singleImage,
                consensusThreshold: 0.7,
                allowSessionSubjectPropagation: true
            ),
            environment: [
                "AISIDECAR_NORMALIZATION_MODE": "batch-conservative",
                "AISIDECAR_CONSENSUS_THRESHOLD": "0.6",
                "AISIDECAR_AFFINITY_PROFILE": "balanced",
                "AISIDECAR_SESSION_HABITAT": "Wetland",
            ],
            defaultConfigPath: configPath
        )

        XCTAssertEqual(resolved.normalizationMode, .singleImage)
        XCTAssertEqual(resolved.consensusThreshold, 0.7)
        XCTAssertEqual(resolved.affinityProfile, .balanced)
        XCTAssertEqual(resolved.sessionSubject, "Birds")
        XCTAssertEqual(resolved.sessionHabitat, "Wetland")
        XCTAssertTrue(resolved.allowSessionSubjectPropagation)
        XCTAssertEqual(resolved.vocabularyMode, .observedTags)
        XCTAssertEqual(ResolvedNormalizationConfiguration.builtInDefaults.vocabularyMode, .observedTags)
        XCTAssertEqual(ResolvedNormalizationConfiguration.builtInDefaults.minAffinityForConsensus, 0.35)
        XCTAssertEqual(ResolvedNormalizationConfiguration.builtInDefaults.unknownSessionContextPolicy, .reject)
    }

    func testNormalizationVocabularyModeResolution() throws {
        let defaultResolved = try ConfigurationResolver.resolveNormalization(
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )
        XCTAssertEqual(defaultResolved.vocabularyMode, .observedTags)
        XCTAssertNil(defaultResolved.vocabularyPath)

        let inferredFromCLIPath = try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(vocabularyPath: "/tmp/custom-vocabulary.json"),
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )
        XCTAssertEqual(inferredFromCLIPath.vocabularyMode, .controlledVocabulary)
        XCTAssertEqual(inferredFromCLIPath.vocabularyPath, "/tmp/custom-vocabulary.json")

        let inferredFromConfigPath = try ConfigurationResolver.resolveNormalization(
            environment: [:],
            defaultConfigPath: try writeConfig(#"{ "vocabulary_path": "/tmp/config-vocabulary.json" }"#)
        )
        XCTAssertEqual(inferredFromConfigPath.vocabularyMode, .controlledVocabulary)
        XCTAssertEqual(inferredFromConfigPath.vocabularyPath, "/tmp/config-vocabulary.json")

        let explicitControlled = try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(vocabularyMode: .controlledVocabulary),
            environment: [:],
            defaultConfigPath: missingConfigPath()
        )
        XCTAssertEqual(explicitControlled.vocabularyMode, .controlledVocabulary)
        XCTAssertNil(explicitControlled.vocabularyPath)

        let environmentControlled = try ConfigurationResolver.resolveNormalization(
            environment: [
                "AISIDECAR_VOCABULARY_MODE": "controlled-vocabulary"
            ],
            defaultConfigPath: missingConfigPath()
        )
        XCTAssertEqual(environmentControlled.vocabularyMode, .controlledVocabulary)

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveNormalization(
                cli: NormalizationConfigurationOverrides(
                    vocabularyPath: "/tmp/custom-vocabulary.json",
                    vocabularyMode: .observedTags
                ),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testApplySessionConfigRejectsPersistentAllowStaleKey() throws {
        let configPath = try writeConfig(#"{ "allow_stale": true }"#)

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveApplySession(
                environment: [:],
                defaultConfigPath: configPath
            )
        }
    }

    func testNormalizationThresholdValidation() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveNormalization(
                cli: NormalizationConfigurationOverrides(consensusThreshold: 1.2),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }

        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolveNormalization(
                cli: NormalizationConfigurationOverrides(minAffinityForConsensus: -0.1),
                environment: [:],
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
