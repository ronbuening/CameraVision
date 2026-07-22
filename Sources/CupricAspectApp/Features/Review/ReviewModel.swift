import AISidecarCore
import Foundation
import Observation

/// Shell-agnostic candidate-review state (M4).
///
/// The durable form of a review is a Phase 3 session document: the model
/// builds a base session over the folder's `.ai.json` files (observed-tags
/// vocabulary, single-image mode — direct observations, no propagation),
/// holds verdicts in memory, and persists by writing the reviewed session
/// (`SessionReview.applying`). `apply-session` then writes exactly the
/// approved set (AC4-013). Autosave per FR4-046a.
@MainActor
@Observable
final class ReviewModel {
    struct AssetQuality: Equatable {
        var records: [QualityAssessmentRecord]
        var issueDiagnostics: [String]
        var tier: QualityTier?
        var explanations: [String]
        var ungradedReason: String?
    }

    struct QualitySummary: Equatable {
        var assessedAssetCount: Int
        var tierCounts: [QualityTier: Int]
        var ungradedAssetCount: Int
        var issueCount: Int

        var isEmpty: Bool {
            assessedAssetCount == 0 && tierCounts.isEmpty && ungradedAssetCount == 0 && issueCount == 0
        }
    }

    struct Chip: Identifiable, Equatable {
        var decisionID: String
        var keyword: String
        var originalKeyword: String?
        var confidence: XMPMinimumConfidence?
        var evidence: String?
        var verdict: ReviewVerdict
        /// AC4-004 detail line: provenance + vocabulary-match state.
        var detail: String
        var id: String { decisionID }
    }

    struct AssetRow: Identifiable, Equatable {
        var assetID: String
        var sourcePath: String?
        var fileName: String
        var fileExtension: String
        var chips: [Chip]
        var quality: AssetQuality? = nil
        var id: String { assetID }
    }

    private(set) var session: NormalizationSessionDocument?
    private(set) var verdicts: [String: ReviewVerdict] = [:]
    private(set) var edits: [String: String] = [:]
    private(set) var building = false
    private(set) var buildError: String?
    private(set) var recoveryAvailable = false
    private(set) var restoredFromRecovery = false
    private(set) var restoredRecoveryDirty = false
    private(set) var editError: String?
    private(set) var qualityByAssetID: [String: AssetQuality] = [:]
    private(set) var qualityDiagnostics: [String] = []
    private(set) var assetRows: [AssetRow] = []

    /// Autosave policy (FR4-046a defaults): every 25 decisions or 5 minutes.
    private let autosaveDecisionLimit: Int
    private let autosaveInterval: TimeInterval
    private let stateDirectory: URL
    private let environment: [String: String]
    private let defaultConfigPath: String?
    private let now: () -> Date
    private let onAssetRowBuilt: (String) -> Void
    private var changesSinceAutosave = 0
    private var lastAutosaveAt: Date
    private var qualityLoadToken = UUID()
    private var assetRowsSessionID: String?
    private var rowIndexByAssetID: [String: Int] = [:]
    private var chipLocationByDecisionID: [String: ChipLocation] = [:]
    private var decisionByID: [String: PerAssetNormalizationDecision] = [:]
    private var decisionOrderByID: [String: Int] = [:]

    init(
        stateDirectory: URL = ReviewModel.defaultStateDirectory,
        autosaveDecisionLimit: Int = 25,
        autosaveInterval: TimeInterval = 300,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil,
        now: @escaping () -> Date = Date.init,
        onAssetRowBuilt: @escaping (String) -> Void = { _ in }
    ) {
        self.stateDirectory = stateDirectory
        self.autosaveDecisionLimit = autosaveDecisionLimit
        self.autosaveInterval = autosaveInterval
        self.environment = environment
        self.defaultConfigPath = defaultConfigPath
        self.now = now
        self.onAssetRowBuilt = onAssetRowBuilt
        self.lastAutosaveAt = now()
        recoveryAvailable = FileManager.default.fileExists(atPath: recoveryURL.path)
    }

    static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CupricAspect", isDirectory: true)
    }

    var recoveryURL: URL {
        stateDirectory.appendingPathComponent("recovery", isDirectory: true)
            .appendingPathComponent("review-recovery.json")
    }

    // MARK: - Derived rows

    private struct ChipLocation {
        var rowIndex: Int
        var chipIndex: Int
    }

    private func rebuildAssetRows(for session: NormalizationSessionDocument) {
        var assetsByID: [String: NormalizationSourceAsset] = [:]
        // Disk imports reject duplicate IDs; first-wins here keeps an invalid in-memory document from trapping UI redraw.
        for asset in session.sourceAssets where assetsByID[asset.assetID] == nil {
            assetsByID[asset.assetID] = asset
        }
        decisionByID = [:]
        decisionOrderByID = [:]
        for (index, decision) in session.perAssetDecisions.enumerated() where decisionByID[decision.decisionID] == nil {
            decisionByID[decision.decisionID] = decision
            decisionOrderByID[decision.decisionID] = index
        }

        var rows: [String: AssetRow] = [:]
        for decision in session.perAssetDecisions where isVisibleReviewDecision(decision) {
            let asset = assetsByID[decision.assetID]
            if rows[decision.assetID] == nil {
                rows[decision.assetID] = AssetRow(
                    assetID: decision.assetID,
                    sourcePath: asset?.sourcePath,
                    fileName: asset?.fileName ?? decision.assetID,
                    fileExtension: asset.map { $0.sourceType.rawValue.uppercased() } ?? "",
                    chips: []
                )
                onAssetRowBuilt(decision.assetID)
            }
            rows[decision.assetID]?.chips.append(chip(for: decision))
        }
        for asset in session.sourceAssets {
            guard let quality = qualityByAssetID[asset.assetID] else { continue }
            if rows[asset.assetID] == nil {
                rows[asset.assetID] = AssetRow(
                    assetID: asset.assetID,
                    sourcePath: asset.sourcePath,
                    fileName: asset.fileName,
                    fileExtension: asset.sourceType.rawValue.uppercased(),
                    chips: []
                )
                onAssetRowBuilt(asset.assetID)
            }
            rows[asset.assetID]?.quality = quality
        }
        assetRows = rows.values.sorted(by: Self.compareRows)
        assetRowsSessionID = session.session.sessionID
        reindexAssetRows()
    }

    private func chip(for decision: PerAssetNormalizationDecision) -> Chip {
        let observation = decision.observations.first
        var detailParts: [String] = [NormalizationDecisionExplainer.text(for: decision.candidateKind)]
        if let provenance = observation?.provenance {
            detailParts.append("from \(provenance.inputRole.rawValue) · \(provenance.sourceField.rawValue)")
            if let model = provenance.model { detailParts.append(model) }
        }
        if let evidence = observation?.evidence {
            detailParts.append("evidence: \(evidence)")
        }
        return Chip(
            decisionID: decision.decisionID,
            keyword: displayKeyword(for: decision),
            originalKeyword: edits[decision.decisionID] != nil ? baseDisplayKeyword(for: decision) : nil,
            confidence: observation?.confidence,
            evidence: observation?.evidence,
            verdict: verdicts[decision.decisionID] ?? .approved,
            detail: detailParts.joined(separator: "\n")
        )
    }

    private func refreshChip(_ decisionID: String) {
        guard let decision = decisionByID[decisionID], isVisibleReviewDecision(decision) else { return }
        let refreshed = chip(for: decision)
        if let location = chipLocationByDecisionID[decisionID] {
            assetRows[location.rowIndex].chips[location.chipIndex] = refreshed
            return
        }

        if let rowIndex = rowIndexByAssetID[decision.assetID] {
            assetRows[rowIndex].chips.append(refreshed)
            assetRows[rowIndex].chips.sort {
                decisionOrderByID[$0.decisionID, default: .max]
                    < decisionOrderByID[$1.decisionID, default: .max]
            }
        } else {
            let asset = session?.sourceAssets.first { $0.assetID == decision.assetID }
            assetRows.append(
                AssetRow(
                    assetID: decision.assetID,
                    sourcePath: asset?.sourcePath,
                    fileName: asset?.fileName ?? decision.assetID,
                    fileExtension: asset.map { $0.sourceType.rawValue.uppercased() } ?? "",
                    chips: [refreshed],
                    quality: qualityByAssetID[decision.assetID]
                )
            )
            onAssetRowBuilt(decision.assetID)
            assetRows.sort(by: Self.compareRows)
        }
        reindexAssetRows()
    }

    private func synchronizeQualityRows(for sessionDocument: NormalizationSessionDocument) {
        guard assetRowsSessionID == sessionDocument.session.sessionID else { return }
        for index in assetRows.indices {
            assetRows[index].quality = qualityByAssetID[assetRows[index].assetID]
        }
        var knownAssetIDs = Set(assetRows.map(\.assetID))
        for asset in sessionDocument.sourceAssets {
            guard qualityByAssetID[asset.assetID] != nil, knownAssetIDs.insert(asset.assetID).inserted else { continue }
            assetRows.append(
                AssetRow(
                    assetID: asset.assetID,
                    sourcePath: asset.sourcePath,
                    fileName: asset.fileName,
                    fileExtension: asset.sourceType.rawValue.uppercased(),
                    chips: [],
                    quality: qualityByAssetID[asset.assetID]
                )
            )
            onAssetRowBuilt(asset.assetID)
        }
        assetRows.removeAll { $0.chips.isEmpty && $0.quality == nil }
        assetRows.sort(by: Self.compareRows)
        reindexAssetRows()
    }

    private func reindexAssetRows() {
        rowIndexByAssetID = [:]
        chipLocationByDecisionID = [:]
        for (rowIndex, row) in assetRows.enumerated() {
            rowIndexByAssetID[row.assetID] = rowIndex
            for (chipIndex, chip) in row.chips.enumerated() {
                chipLocationByDecisionID[chip.decisionID] = ChipLocation(
                    rowIndex: rowIndex,
                    chipIndex: chipIndex
                )
            }
        }
    }

    private static func compareRows(_ lhs: AssetRow, _ rhs: AssetRow) -> Bool {
        lhs.fileName.lowercased() < rhs.fileName.lowercased()
    }

    private func isVisibleReviewDecision(_ decision: PerAssetNormalizationDecision) -> Bool {
        decision.status == .accepted || verdicts[decision.decisionID] != nil
    }

    private func displayKeyword(for decision: PerAssetNormalizationDecision) -> String {
        edits[decision.decisionID] ?? baseDisplayKeyword(for: decision)
    }

    private func baseDisplayKeyword(for decision: PerAssetNormalizationDecision) -> String {
        decision.flatKeyword ?? decision.canonicalPath ?? decision.sourceText ?? "?"
    }

    var approvedCount: Int { verdicts.values.count { $0 == .approved } }
    var rejectedCount: Int { verdicts.values.count { $0 == .rejected } }
    var deferredCount: Int { verdicts.values.count { $0 == .deferred } }
    var canSaveSession: Bool { session != nil }
    var qualitySummary: QualitySummary {
        Self.qualitySummary(for: qualityByAssetID)
    }

    nonisolated static func qualitySummary(for presentation: [String: AssetQuality]) -> QualitySummary {
        var summary = QualitySummary(
            assessedAssetCount: 0,
            tierCounts: [:],
            ungradedAssetCount: 0,
            issueCount: 0
        )
        for quality in presentation.values {
            if !quality.records.isEmpty {
                summary.assessedAssetCount += 1
            }
            if let tier = quality.tier {
                summary.tierCounts[tier, default: 0] += 1
            } else if quality.ungradedReason != nil {
                summary.ungradedAssetCount += 1
            }
            summary.issueCount += quality.issueDiagnostics.count
        }
        return summary
    }

    /// The exportable document: base session + review verdicts and edits.
    var reviewedSession: NormalizationSessionDocument? {
        session.map { SessionReview.applying(verdicts: verdicts, edits: edits, to: $0) }
    }

    // MARK: - Session lifecycle

    /// Build the review base session over the folder's `.ai.json` files.
    /// Model-free; artifacts land inside the app state directory.
    func buildSession(
        jsonRoot: String,
        sourceRoot: String,
        qualityGrading: QualityGradingConfigurationOverrides
    ) {
        guard !building else { return }
        building = true
        buildError = nil
        let artifactDir =
            stateDirectory
            .appendingPathComponent("review-artifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString).path

        Task {
            defer { building = false }
            do {
                let configuration = try buildConfiguration(
                    sourceRoot: sourceRoot,
                    outputDir: artifactDir,
                    qualityGrading: qualityGrading
                )
                let result = try await Task.detached(priority: .userInitiated) {
                    return try NormalizePipeline().runSessionOnly(
                        mode: .fromJSON(path: jsonRoot),
                        configuration: configuration
                    )
                }.value
                adopt(session: result.session)
            } catch {
                buildError = (error as? SidecarError)?.message ?? error.localizedDescription
            }
        }
    }

    func buildConfiguration(
        sourceRoot: String,
        outputDir: String,
        qualityGrading: QualityGradingConfigurationOverrides
    ) throws -> ResolvedNormalizationConfiguration {
        try ConfigurationResolver.resolveNormalization(
            cli: NormalizationConfigurationOverrides(
                recursive: true,
                outputDir: outputDir,
                sourceRoot: sourceRoot,
                vocabularyMode: .observedTags,
                normalizationMode: .singleImage,
                qualityGrading: qualityGrading
            ),
            environment: environment,
            defaultConfigPath: defaultConfigPath
        )
    }

    /// Adopt a session document (fresh build, import, or recovery) and
    /// reconstruct verdicts/edits from it.
    func adopt(session sessionDocument: NormalizationSessionDocument) {
        session = sessionDocument
        verdicts = SessionReview.verdicts(in: sessionDocument)
        edits = SessionReview.edits(in: sessionDocument)
        changesSinceAutosave = 0
        lastAutosaveAt = now()
        restoredFromRecovery = false
        restoredRecoveryDirty = false
        editError = nil
        qualityDiagnostics = []
        qualityByAssetID = Self.qualityPresentation(
            sourceAssets: sessionDocument.sourceAssets,
            xmpWritePlans: sessionDocument.xmpWritePlans,
            extractionByAssetID: [:]
        )
        rebuildAssetRows(for: sessionDocument)
        loadQualityAssessments(for: sessionDocument)
    }

    nonisolated static func qualityPresentation(
        sourceAssets: [NormalizationSourceAsset],
        xmpWritePlans: [NormalizedXMPWritePlan],
        extractionByAssetID: [String: QualityExtractionResult]
    ) -> [String: AssetQuality] {
        struct PlannedQuality {
            var tier: QualityTier?
            var explanations: [String]
            var ungradedReason: String?
        }

        var planBySource: [String: PlannedQuality] = [:]
        for writePlan in xmpWritePlans {
            let plan = writePlan.xmpChangePlan
            let explanations = plan.qualityExplanation ?? []
            let ungradedReason = plan.ungradedReasonExplanation
            guard plan.qualityTier != nil || ungradedReason != nil || !explanations.isEmpty else { continue }
            let planned = PlannedQuality(
                tier: plan.qualityTier,
                explanations: explanations,
                ungradedReason: ungradedReason
            )
            for member in plan.sourceMembers {
                planBySource[
                    qualitySourceKey(path: member.sourcePath, relativePath: member.sourceRelativePath)
                ] = planned
            }
        }

        var presentation: [String: AssetQuality] = [:]
        for asset in sourceAssets {
            let key = qualitySourceKey(path: asset.sourcePath, relativePath: asset.sourceRelativePath)
            let extraction = extractionByAssetID[asset.assetID]
            let planned = planBySource[key]
            let records = extraction?.records ?? []
            let issues = extraction?.issues.map(qualityIssueDiagnostic) ?? []
            guard !records.isEmpty || !issues.isEmpty || planned != nil else { continue }
            presentation[asset.assetID] = AssetQuality(
                records: records,
                issueDiagnostics: issues,
                tier: planned?.tier,
                explanations: planned?.explanations ?? [],
                ungradedReason: planned?.ungradedReason
            )
        }
        return presentation
    }

    private nonisolated static func qualitySourceKey(path: String?, relativePath: String) -> String {
        guard let path, !path.isEmpty else { return "relative:\(relativePath)" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private nonisolated static func qualityIssueDiagnostic(_ issue: QualityExtractionIssue) -> String {
        switch issue {
        case .malformedBlock:
            QualityExtractionIssueCode.malformedBlock.rawValue
        case .unknownCriterion(let criterion):
            "\(QualityExtractionIssueCode.unknownCriterion.rawValue): \(criterion)"
        case .missingOverall:
            QualityExtractionIssueCode.missingOverall.rawValue
        case .invalidLevel(let field, let value):
            "\(QualityExtractionIssueCode.invalidLevel.rawValue): \(field)=\(value)"
        }
    }

    /// Re-resolve current contributor documents and extract assessments away from the UI actor.
    private func loadQualityAssessments(for sessionDocument: NormalizationSessionDocument) {
        let token = UUID()
        qualityLoadToken = token
        Task {
            let loaded = await Task.detached(priority: .utility) {
                Self.loadQualityExtraction(for: sessionDocument)
            }.value
            guard qualityLoadToken == token, session?.session.sessionID == sessionDocument.session.sessionID else {
                return
            }
            qualityByAssetID = Self.qualityPresentation(
                sourceAssets: sessionDocument.sourceAssets,
                xmpWritePlans: sessionDocument.xmpWritePlans,
                extractionByAssetID: loaded.resultsByAssetID
            )
            qualityDiagnostics = loaded.diagnostics
            synchronizeQualityRows(for: sessionDocument)
        }
    }

    /// Re-read the session's stored sidecar references through the same
    /// current-pair resolver apply-session grading uses (QN6), so the panel
    /// shows exactly the contributor documents an apply-time grade would
    /// consume — no source re-hashing and no second identity gate.
    nonisolated static func loadQualityExtraction(
        for sessionDocument: NormalizationSessionDocument
    ) -> (resultsByAssetID: [String: QualityExtractionResult], diagnostics: [String]) {
        let resolver = RawJSONSidecarInputResolver()
        var resultsByAssetID: [String: QualityExtractionResult] = [:]
        var diagnostics: [String] = []
        var consumedSidecarPaths: Set<String> = []
        for record in sessionDocument.sourceAISidecars {
            let referencePath = URL(fileURLWithPath: record.sidecarPath).standardizedFileURL.path
            guard !consumedSidecarPaths.contains(referencePath) else { continue }
            let batch = resolver.resolveCurrentSidecarPair(at: record.sidecarPath)
            diagnostics.append(contentsOf: batch.failures.map { "\($0.error.code.rawValue): \($0.error.message)" })
            for input in batch.inputs {
                consumedSidecarPaths.insert(input.sidecarPath.standardizedFileURL.path)
                if let qualityPath = input.qualitySidecarPath {
                    consumedSidecarPaths.insert(qualityPath.standardizedFileURL.path)
                }
                if resultsByAssetID[record.sourceAssetID] == nil {
                    resultsByAssetID[record.sourceAssetID] = QualityAssessmentExtractor.extract(from: input)
                }
            }
        }
        return (resultsByAssetID, diagnostics)
    }

    /// FR4-059: user-initiated file operations surface failures instead of
    /// silently dropping them. Set by the views' save/import/restore actions,
    /// shown beside `buildError`, and echoed to the diagnostic log.
    private(set) var fileError: String?

    func reportFileError(_ action: String, _ error: Error) {
        let message = "\(action) failed: \((error as? SidecarError)?.message ?? error.localizedDescription)"
        fileError = message
        try? GUILog.shared.makeLogger().log(
            LogRecord(
                level: .error,
                event: "review.file_operation_failed",
                message: message,
                errors: (error as? SidecarError).map { [$0] } ?? []
            ))
    }

    func clearFileError() {
        fileError = nil
    }

    func importSession(from url: URL) throws {
        adopt(session: try NormalizationSessionReader().read(from: url.path))
    }

    /// "Save session only" — the reviewed session in the Phase 3 format.
    func saveSession(to url: URL) throws {
        guard let reviewedSession else {
            throw SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "No review session is loaded; nothing to save.",
                recoverable: true
            )
        }
        try NormalizationSessionWriter().write(reviewedSession, to: url.path)
        restoredRecoveryDirty = false
    }

    /// Clean completion: review state is exported or intentionally dropped.
    func completeCleanly() {
        try? FileManager.default.removeItem(at: recoveryURL)
        recoveryAvailable = false
        session = nil
        verdicts = [:]
        edits = [:]
        restoredFromRecovery = false
        restoredRecoveryDirty = false
        editError = nil
        qualityLoadToken = UUID()
        qualityByAssetID = [:]
        qualityDiagnostics = []
        assetRows = []
        assetRowsSessionID = nil
        rowIndexByAssetID = [:]
        chipLocationByDecisionID = [:]
        decisionByID = [:]
        decisionOrderByID = [:]
    }

    // MARK: - Verdicts

    func setVerdict(_ verdict: ReviewVerdict, for decisionID: String) {
        guard verdicts[decisionID] != verdict else { return }
        verdicts[decisionID] = verdict
        refreshChip(decisionID)
        recordChange()
    }

    func toggle(_ decisionID: String) {
        setVerdict((verdicts[decisionID] ?? .approved) == .approved ? .rejected : .approved, for: decisionID)
    }

    func acceptAll(assetID: String) {
        guard session != nil else { return }
        if let rowIndex = rowIndexByAssetID[assetID] {
            for chipIndex in assetRows[rowIndex].chips.indices {
                let decisionID = assetRows[rowIndex].chips[chipIndex].decisionID
                verdicts[decisionID] = .approved
                assetRows[rowIndex].chips[chipIndex].verdict = .approved
            }
        }
        recordChange()
    }

    /// Batch approve/reject every currently visible chip (FR4-018).
    func setAllVisible(_ verdict: ReviewVerdict) {
        for rowIndex in assetRows.indices {
            for chipIndex in assetRows[rowIndex].chips.indices {
                let decisionID = assetRows[rowIndex].chips[chipIndex].decisionID
                verdicts[decisionID] = verdict
                assetRows[rowIndex].chips[chipIndex].verdict = verdict
            }
        }
        recordChange()
    }

    @discardableResult
    func editKeyword(_ decisionID: String, to text: String) -> Bool {
        guard let replacement = SessionReview.sanitizedEdit(text) else {
            editError =
                "Keyword edits must be non-empty and cannot contain '|', GPS/location metadata, or coordinate syntax."
            return false
        }
        editError = nil
        edits[decisionID] = replacement
        verdicts[decisionID] = .approved
        refreshChip(decisionID)
        recordChange()
        return true
    }

    /// FR4-019 scoped batch correction: apply an edit to every asset in the
    /// current folder carrying the same keyword. Callers confirm explicitly.
    func editEverywhere(keyword: String, to text: String) -> Int {
        guard let session else { return 0 }
        let folded = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !folded.isEmpty, let replacement = SessionReview.sanitizedEdit(text) else {
            editError =
                "Keyword edits must be non-empty and cannot contain '|', GPS/location metadata, or coordinate syntax."
            return 0
        }
        editError = nil
        var applied = 0
        for decision in session.perAssetDecisions
        where isVisibleReviewDecision(decision) && displayKeyword(for: decision).lowercased() == folded {
            edits[decision.decisionID] = replacement
            verdicts[decision.decisionID] = .approved
            refreshChip(decision.decisionID)
            applied += 1
        }
        if applied > 0 { recordChange() }
        return applied
    }

    // MARK: - Autosave (FR4-046a)

    private func recordChange() {
        changesSinceAutosave += 1
        if restoredFromRecovery {
            restoredRecoveryDirty = true
        }
        let elapsed = now().timeIntervalSince(lastAutosaveAt)
        if changesSinceAutosave >= autosaveDecisionLimit || elapsed >= autosaveInterval {
            autosaveNow()
        }
    }

    func autosaveNow() {
        guard let reviewedSession else { return }
        do {
            try FileManager.default.createDirectory(
                at: recoveryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try NormalizationSessionWriter().write(reviewedSession, to: recoveryURL.path)
            changesSinceAutosave = 0
            lastAutosaveAt = now()
            recoveryAvailable = true
        } catch {
            // Autosave must never interrupt review; the next change retries.
        }
    }

    func restoreFromRecovery() throws {
        adopt(session: try NormalizationSessionReader().read(from: recoveryURL.path))
        recoveryAvailable = true
        restoredFromRecovery = true
        restoredRecoveryDirty = true
    }

    func discardRecovery() {
        try? FileManager.default.removeItem(at: recoveryURL)
        recoveryAvailable = false
        restoredFromRecovery = false
        restoredRecoveryDirty = false
    }
}
