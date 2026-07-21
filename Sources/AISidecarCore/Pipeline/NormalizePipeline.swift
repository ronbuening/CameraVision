import Foundation

/// Result of building the initial Phase 3 normalization artifacts.
public struct NormalizePipelineResult: Sendable, Equatable {
    public var session: NormalizationSessionDocument
    public var report: NormalizationReport
    public var changePlan: XMPChangePlanDocument?

    public init(
        session: NormalizationSessionDocument,
        report: NormalizationReport,
        changePlan: XMPChangePlanDocument? = nil
    ) {
        self.session = session
        self.report = report
        self.changePlan = changePlan
    }
}

/// Builds complete Phase 3 normalization sessions and normalized XMP plans before any XMP write starts.
public struct NormalizePipeline {
    private let inputResolver: NormalizationInputResolver
    private let sessionWriter: NormalizationSessionWriter
    private let reportWriter: NormalizationReportWriter
    private let summaryWriter: NormalizationSummaryWriter
    private let snapshotReader: @Sendable (String) throws -> XMPMetadataSnapshot

    public init(
        inputResolver: NormalizationInputResolver = NormalizationInputResolver(),
        sessionWriter: NormalizationSessionWriter = NormalizationSessionWriter(),
        reportWriter: NormalizationReportWriter = NormalizationReportWriter(),
        summaryWriter: NormalizationSummaryWriter = NormalizationSummaryWriter(),
        snapshotReader: (@Sendable (String) throws -> XMPMetadataSnapshot)? = nil,
        fileManager: FileManager = .default
    ) {
        self.inputResolver = inputResolver
        self.sessionWriter = sessionWriter
        self.reportWriter = reportWriter
        self.summaryWriter = summaryWriter
        if let snapshotReader {
            self.snapshotReader = snapshotReader
        } else {
            let metadataEngine = OwnedXMPSidecarEngine(fileManager: fileManager)
            self.snapshotReader = { try metadataEngine.readSnapshot(at: $0) }
        }
    }

    /// Resolve inputs and write session/report/summary/progress artifacts without touching XMP sidecars.
    public func runSessionOnly(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date = Date(),
        sessionID: String = UUID().uuidString,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> NormalizePipelineResult {
        try run(
            mode: mode,
            configuration: configuration,
            timestamp: timestamp,
            sessionID: sessionID,
            includeXMPPlans: false,
            interruptionMonitor: interruptionMonitor
        )
    }

    /// Resolve inputs, normalize decisions, and write dry-run plans without touching XMP sidecars.
    public func runDryRun(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date = Date(),
        sessionID: String = UUID().uuidString,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> NormalizePipelineResult {
        try run(
            mode: mode,
            configuration: configuration,
            timestamp: timestamp,
            sessionID: sessionID,
            includeXMPPlans: true,
            interruptionMonitor: interruptionMonitor
        )
    }

    /// Resolve inputs, normalize decisions, and write executable XMP plans.
    public func runWritePlan(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date = Date(),
        sessionID: String = UUID().uuidString,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> NormalizePipelineResult {
        try run(
            mode: mode,
            configuration: configuration,
            timestamp: timestamp,
            sessionID: sessionID,
            includeXMPPlans: true,
            interruptionMonitor: interruptionMonitor
        )
    }

    /// Normalize raw sidecars already resolved by an upstream workflow.
    public func runResolvedInputs(
        _ input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date = Date(),
        sessionID: String = UUID().uuidString,
        includeXMPPlans: Bool = true,
        interruptionMonitor: InterruptionMonitor? = nil
    ) throws -> NormalizePipelineResult {
        return try runResolvedInput(
            input,
            configuration: configuration,
            timestamp: timestamp,
            sessionID: sessionID,
            includeXMPPlans: includeXMPPlans,
            interruptionMonitor: interruptionMonitor
        )
    }

    private func run(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date,
        sessionID: String,
        includeXMPPlans: Bool,
        interruptionMonitor: InterruptionMonitor?
    ) throws -> NormalizePipelineResult {
        let input = try inputResolver.resolve(mode: mode, configuration: configuration)
        return try runResolvedInput(
            input,
            configuration: configuration,
            timestamp: timestamp,
            sessionID: sessionID,
            includeXMPPlans: includeXMPPlans,
            interruptionMonitor: interruptionMonitor
        )
    }

    private func runResolvedInput(
        _ input: NormalizationResolvedInputBatch,
        configuration: ResolvedNormalizationConfiguration,
        timestamp: Date,
        sessionID: String,
        includeXMPPlans: Bool,
        interruptionMonitor: InterruptionMonitor?
    ) throws -> NormalizePipelineResult {
        let extractionResults = CandidateExtractor().extract(
            from: input.rawSidecarInputs,
            configuration: xmpExportConfiguration(from: configuration)
        )
        let vocabulary = try loadVocabulary(configuration, extractionResults: extractionResults)
        let canonicalizer = CandidateCanonicalizer(vocabulary: vocabulary)
        try canonicalizer.preflightSessionContext(configuration: configuration)
        let canonicalization = try canonicalizer.canonicalize(
            extractionResults: extractionResults,
            input: input,
            configuration: configuration
        )
        let consensus = BatchConsensusEngine(vocabulary: vocabulary).apply(
            canonicalization: canonicalization,
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
        let shouldBuildXMPPlans = includeXMPPlans || configuration.qualityGrading.enabled
        let planningConfiguration = qualityPlanningConfiguration(
            from: configuration,
            resolvesScalars: includeXMPPlans
        )
        let normalizedPlans =
            try shouldBuildXMPPlans
            ? NormalizedXMPChangePlanner().plan(
                input: input,
                decisions: consensus.perAssetDecisions,
                candidateSkips: consensus.skips,
                configuration: planningConfiguration,
                snapshotReader: includeXMPPlans ? snapshotReader : nil
            )
            : nil
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
            consensus: consensus,
            xmpWritePlans: normalizedPlans?.writePlans ?? []
        )
        let report = makeReport(
            timestamp: timestamp,
            input: input,
            configuration: configuration,
            vocabulary: vocabulary,
            writerIdentity: writerIdentity,
            artifactPlan: artifactPlan,
            consensus: consensus,
            xmpWritePlans: normalizedPlans?.writePlans ?? []
        )

        // Milestone 9 keeps session-only and dry-run interruption fail-closed: once
        // aggregation and planning finish, an already requested interruption stops
        // before any normalization artifacts or XMP side effects are created.
        if interruptionMonitor?.isInterrupted == true {
            throw interruptedError("Normalization interrupted before session artifact write.")
        }

        let progressLog = try NormalizationProgressLog(path: artifactPlan.progressPath)
        defer {
            try? progressLog.close()
        }
        try appendProgressRecords(
            to: progressLog,
            timestamp: timestamp,
            input: input,
            consensus: consensus,
            xmpWritePlans: normalizedPlans?.writePlans ?? []
        )
        try sessionWriter.write(session, to: sessionPath)
        try reportWriter.write(report, to: artifactPlan.reportPath)
        try summaryWriter.write(report, to: artifactPlan.summaryPath)
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .artifactWrite,
                status: .completed,
                message: "Normalization artifacts written.",
                sourceAssetCount: input.sourceAssets.count,
                perAssetDecisionCount: consensus.perAssetDecisions.count,
                xmpWritePlanCount: normalizedPlans?.writePlans.count ?? 0
            )
        )
        try progressLog.close()
        return NormalizePipelineResult(session: session, report: report, changePlan: normalizedPlans?.changePlan)
    }

    private func loadVocabulary(
        _ configuration: ResolvedNormalizationConfiguration,
        extractionResults: [CandidateExtractionResult]
    ) throws -> LoadedVocabulary {
        switch configuration.vocabularyMode {
        case .observedTags:
            return try ObservedTagVocabulary.load(
                extractionResults: extractionResults,
                configuration: configuration
            )
        case .controlledVocabulary:
            if let vocabularyPath = configuration.vocabularyPath {
                return try VocabularyLoader.load(at: vocabularyPath)
            }
            return try DefaultVocabulary.load()
        }
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
        consensus: BatchConsensusResult,
        xmpWritePlans: [NormalizedXMPWritePlan]
    ) -> NormalizationSessionDocument {
        let warnings = input.warnings
        let errors = input.failures.map(\.error)

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
            sessionContext: consensus.sessionContext,
            privacy: privacy,
            xmpWriter: writerIdentity,
            sourceAISidecars: input.sourceAISidecars,
            sourceAssets: input.sourceAssets,
            sameBaseNameGroups: input.sameBaseNameGroups,
            affinity: consensus.affinity,
            candidateObservations: consensus.observations,
            candidateSkips: consensus.skips,
            batchCandidates: consensus.batchCandidates,
            localConsensus: consensus.localConsensus,
            perAssetDecisions: consensus.perAssetDecisions,
            xmpWritePlans: xmpWritePlans,
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
        consensus: BatchConsensusResult,
        xmpWritePlans: [NormalizedXMPWritePlan]
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
                candidateObservationCount: consensus.observations.count,
                candidateSkipCount: consensus.skips.count,
                batchCandidateCount: consensus.batchCandidates.count,
                perAssetDecisionCount: consensus.perAssetDecisions.count,
                xmpWritePlanCount: xmpWritePlans.count,
                warningCount: input.warnings.count,
                failureCount: input.failures.count
            ),
            decisionSummary: NormalizationDecisionSummary(decisions: consensus.perAssetDecisions),
            sourceAssets: input.sourceAssets,
            sameBaseNameGroups: input.sameBaseNameGroups,
            affinity: consensus.affinity,
            candidateSkips: consensus.skips,
            batchCandidates: consensus.batchCandidates,
            localConsensus: consensus.localConsensus,
            perAssetDecisions: consensus.perAssetDecisions,
            xmpWritePlans: xmpWritePlans,
            warnings: input.warnings,
            errors: input.failures.map(\.error)
        )
    }

    private func appendProgressRecords(
        to progressLog: NormalizationProgressLog,
        timestamp: Date,
        input: NormalizationResolvedInputBatch,
        consensus: BatchConsensusResult,
        xmpWritePlans: [NormalizedXMPWritePlan]
    ) throws {
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .inputResolution,
                status: .completed,
                message: "Normalization inputs resolved.",
                sourceAssetCount: input.sourceAssets.count
            )
        )
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .normalization,
                status: .completed,
                message: "Normalization decisions completed.",
                sourceAssetCount: input.sourceAssets.count,
                perAssetDecisionCount: consensus.perAssetDecisions.count
            )
        )
        try progressLog.append(
            NormalizationProgressRecord(
                timestamp: timestamp,
                stage: .xmpPlanning,
                status: xmpWritePlans.isEmpty ? .skipped : .completed,
                message: xmpWritePlans.isEmpty
                    ? "XMP planning skipped for session-only invocation."
                    : "Normalized XMP plans completed.",
                xmpWritePlanCount: xmpWritePlans.count
            )
        )
        for writePlan in xmpWritePlans {
            let plan = writePlan.xmpChangePlan
            try progressLog.append(
                NormalizationProgressRecord(
                    timestamp: timestamp,
                    stage: .xmpTarget,
                    status: plan.status == .planned ? .planned : .failed,
                    message: "Normalized XMP target planned.",
                    xmpWritePlanCount: 1,
                    targetXMPPath: plan.targetXMPPath,
                    targetRelativePath: plan.targetRelativePath,
                    plannedFlatKeywords: plan.flatKeywordsToAdd.map(\.term),
                    plannedHierarchicalKeywords: plan.hierarchicalKeywordsToAdd.map(\.term),
                    ratingWrite: plan.ratingWrite,
                    labelWrite: plan.labelWrite,
                    urgencyWrite: plan.urgencyWrite,
                    pickWrite: plan.pickWrite,
                    goodWrite: plan.goodWrite,
                    qualityTier: plan.qualityTier,
                    qualityExplanation: plan.qualityExplanation,
                    errors: plan.failures
                )
            )
        }
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
            writeAIJSON: configuration.writeAIJSON,
            qualityGrading: configuration.qualityGrading
        )
    }

    private func qualityPlanningConfiguration(
        from configuration: ResolvedNormalizationConfiguration,
        resolvesScalars: Bool
    ) -> ResolvedNormalizationConfiguration {
        guard configuration.qualityGrading.enabled, !resolvesScalars else {
            return configuration
        }
        // Session-only plans are previews without a current-XMP snapshot. Keep
        // the derived tier, explanation, and quality keywords, but do not claim
        // scalar conflict decisions that only an authoritative write plan can make.
        var preview = configuration
        preview.qualityGrading.policy.writeRating = false
        preview.qualityGrading.policy.writeLabel = false
        preview.qualityGrading.policy.writeUrgency = false
        preview.qualityGrading.policy.writeFlag = false
        return preview
    }

    private func interruptedError(_ message: String) -> SidecarError {
        SidecarError(code: .interrupted, stage: .normalize, message: message, recoverable: true)
    }
}
