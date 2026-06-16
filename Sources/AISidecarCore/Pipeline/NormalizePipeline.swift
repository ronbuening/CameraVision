import Foundation

/// Result of building the initial Phase 3 normalization artifacts.
public struct NormalizePipelineResult: Sendable, Equatable {
    public var session: NormalizationSessionDocument
    public var report: NormalizationReport

    public init(session: NormalizationSessionDocument, report: NormalizationReport) {
        self.session = session
        self.report = report
    }
}

/// Builds Phase 3 normalization sessions before later milestones add decisions and XMP writes.
public struct NormalizePipeline {
    private let inputResolver: NormalizationInputResolver
    private let sessionWriter: NormalizationSessionWriter
    private let reportWriter: NormalizationReportWriter

    public init(
        inputResolver: NormalizationInputResolver = NormalizationInputResolver(),
        sessionWriter: NormalizationSessionWriter = NormalizationSessionWriter(),
        reportWriter: NormalizationReportWriter = NormalizationReportWriter()
    ) {
        self.inputResolver = inputResolver
        self.sessionWriter = sessionWriter
        self.reportWriter = reportWriter
    }

    /// Resolve inputs and write session/report artifacts without touching XMP sidecars.
    public func runSessionOnly(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date = Date(),
        sessionID: String = UUID().uuidString
    ) throws -> NormalizePipelineResult {
        let vocabulary = try loadVocabulary(configuration)
        try CandidateCanonicalizer.preflightSessionContext(
            configuration: configuration,
            vocabulary: vocabulary
        )
        let input = try inputResolver.resolve(mode: mode, configuration: configuration)
        let extractionResults = CandidateExtractor().extract(
            from: input.rawSidecarInputs,
            configuration: xmpExportConfiguration(from: configuration)
        )
        let canonicalization = try CandidateCanonicalizer(vocabulary: vocabulary).canonicalize(
            extractionResults: extractionResults,
            input: input,
            configuration: configuration
        )
        let artifactPlan = NormalizationArtifactPlanner.planNormalize(
            inputBasePath: input.inputBasePath,
            outputDir: configuration.outputDir,
            writeReportPath: configuration.writeReportPath,
            timestamp: timestamp
        )
        guard let sessionPath = artifactPlan.sessionPath else {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Normalization session path was not planned.",
                recoverable: false
            )
        }

        let writerIdentity = MetadataWriteEngineContext(
            engineName: OwnedXMPSidecarEngine.engineName,
            engineVersion: OwnedXMPSidecarEngine.engineVersion,
            writerRecipeVersion: OwnedXMPSidecarEngine.writerRecipeVersion
        )
        let privacy = NormalizationPrivacyRecord(privacyMode: configuration.affinityPrivacyMode)
        let session = makeSession(
            sessionID: sessionID,
            timestamp: timestamp,
            input: input,
            configuration: configuration,
            vocabulary: vocabulary,
            privacy: privacy,
            writerIdentity: writerIdentity,
            artifactPlan: artifactPlan,
            canonicalization: canonicalization
        )
        let report = makeReport(
            timestamp: timestamp,
            input: input,
            configuration: configuration,
            vocabulary: vocabulary,
            writerIdentity: writerIdentity,
            artifactPlan: artifactPlan,
            canonicalization: canonicalization
        )

        try sessionWriter.write(session, to: sessionPath)
        try reportWriter.write(report, to: artifactPlan.reportPath)
        return NormalizePipelineResult(session: session, report: report)
    }

    private func loadVocabulary(_ configuration: ResolvedNormalizationConfiguration) throws -> LoadedVocabulary {
        if let vocabularyPath = configuration.vocabularyPath {
            return try VocabularyLoader.load(at: vocabularyPath)
        }
        return try DefaultVocabulary.load()
    }

    private func makeSession(
        sessionID: String,
        timestamp: Date,
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        vocabulary: LoadedVocabulary,
        privacy: NormalizationPrivacyRecord,
        writerIdentity: MetadataWriteEngineContext,
        artifactPlan: NormalizationArtifactPlan,
        canonicalization: CandidateCanonicalizationResult
    ) -> NormalizationSessionDocument {
        let warnings = input.warnings
        let errors = input.failures.map(\.error)
        let nodes = input.sameBaseNameGroups.map {
            NormalizationAffinityNodeRecord(
                nodeID: $0.groupID,
                groupID: $0.groupID,
                memberAssetIDs: $0.memberAssetIDs
            )
        }

        return NormalizationSessionDocument(
            session: NormalizationSessionMetadata(
                sessionID: sessionID,
                createdAt: timestamp,
                workflow: input.workflow,
                inputPath: input.inputPath,
                normalizationMode: configuration.normalizationMode,
                scanRoot: input.scanRoot,
                sourceRoot: configuration.sourceRoot,
                outputDir: configuration.outputDir
            ),
            vocabulary: vocabulary.identity,
            resolvedConfiguration: configuration,
            sessionContext: canonicalization.sessionContext,
            privacy: privacy,
            xmpWriter: writerIdentity,
            sourceAISidecars: input.sourceAISidecars,
            sourceAssets: input.sourceAssets,
            sameBaseNameGroups: input.sameBaseNameGroups,
            affinity: NormalizationAffinityRecord(
                mode: configuration.affinityMode,
                profile: configuration.affinityProfile,
                minAffinityForConsensus: configuration.minAffinityForConsensus,
                nodes: nodes
            ),
            candidateObservations: canonicalization.observations,
            candidateSkips: canonicalization.skips,
            batchCandidates: canonicalization.batchCandidates,
            perAssetDecisions: canonicalization.perAssetDecisions,
            artifacts: artifactPlan,
            deterministicPolicy: NormalizationDeterministicPolicyRecord(
                exactAffinityInputsPersisted: privacy.exactAffinityInputsPersisted
            ),
            warnings: warnings,
            errors: errors
        )
    }

    private func makeReport(
        timestamp: Date,
        input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        vocabulary: LoadedVocabulary,
        writerIdentity: MetadataWriteEngineContext,
        artifactPlan: NormalizationArtifactPlan,
        canonicalization: CandidateCanonicalizationResult
    ) -> NormalizationReport {
        NormalizationReport(
            createdAt: timestamp,
            sessionPath: artifactPlan.sessionPath,
            workflow: input.workflow,
            inputPath: input.inputPath,
            configuration: configuration,
            vocabulary: vocabulary.identity,
            xmpWriter: writerIdentity,
            artifacts: artifactPlan,
            inputSummary: NormalizationInputSummary(
                sourceAssetCount: input.sourceAssets.count,
                sourceAISidecarCount: input.sourceAISidecars.count,
                sameBaseNameGroupCount: input.sameBaseNameGroups.count,
                candidateObservationCount: canonicalization.observations.count,
                candidateSkipCount: canonicalization.skips.count,
                batchCandidateCount: canonicalization.batchCandidates.count,
                perAssetDecisionCount: canonicalization.perAssetDecisions.count,
                warningCount: input.warnings.count,
                failureCount: input.failures.count
            ),
            decisionSummary: NormalizationDecisionSummary(decisions: canonicalization.perAssetDecisions),
            warnings: input.warnings,
            errors: input.failures.map(\.error)
        )
    }

    private func xmpExportConfiguration(
        from configuration: ResolvedNormalizationConfiguration
    ) -> ResolvedXMPExportConfiguration {
        ResolvedXMPExportConfiguration(
            recursive: configuration.recursive,
            outputDir: configuration.outputDir,
            logLevel: configuration.logLevel,
            logFormat: configuration.logFormat,
            dryRun: configuration.dryRun,
            sourceRoot: configuration.sourceRoot,
            sourceVerification: configuration.sourceVerification,
            writeFlatKeywords: configuration.writeFlatKeywords,
            writeHierarchicalKeywords: configuration.writeHierarchicalKeywords,
            backupSidecars: configuration.backupSidecars,
            xmpConflictPolicy: configuration.xmpConflictPolicy,
            minConfidence: configuration.minConfidence,
            allowSpecificTags: configuration.allowSpecificTags,
            pairScope: configuration.pairScope,
            writeAIJSON: configuration.writeAIJSON
        )
    }
}
