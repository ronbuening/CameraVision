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
        var id: String { assetID }
    }

    private(set) var session: NormalizationSessionDocument?
    private(set) var verdicts: [String: ReviewVerdict] = [:]
    private(set) var edits: [String: String] = [:]
    private(set) var building = false
    private(set) var buildError: String?
    private(set) var recoveryAvailable = false

    /// Autosave policy (FR4-046a defaults): every 25 decisions or 5 minutes.
    private let autosaveDecisionLimit: Int
    private let autosaveInterval: TimeInterval
    private let stateDirectory: URL
    private let now: () -> Date
    private var changesSinceAutosave = 0
    private var lastAutosaveAt: Date

    init(
        stateDirectory: URL = ReviewModel.defaultStateDirectory,
        autosaveDecisionLimit: Int = 25,
        autosaveInterval: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.stateDirectory = stateDirectory
        self.autosaveDecisionLimit = autosaveDecisionLimit
        self.autosaveInterval = autosaveInterval
        self.now = now
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

    var assetRows: [AssetRow] {
        guard let session else { return [] }
        let assetsByID = Dictionary(uniqueKeysWithValues: session.sourceAssets.map { ($0.assetID, $0) })
        var rows: [String: AssetRow] = [:]
        for decision in session.perAssetDecisions where decision.status == .accepted || verdicts[decision.decisionID] != nil {
            let asset = assetsByID[decision.assetID]
            let keyword = edits[decision.decisionID] ?? decision.flatKeyword ?? decision.canonicalPath ?? decision.sourceText ?? "?"
            let observation = decision.observations.first
            var detailParts: [String] = [NormalizationDecisionExplainer.text(for: decision.candidateKind)]
            if let provenance = observation?.provenance {
                detailParts.append("from \(provenance.inputRole.rawValue) · \(provenance.sourceField.rawValue)")
                if let model = provenance.model { detailParts.append(model) }
            }
            if let evidence = observation?.evidence {
                detailParts.append("evidence: \(evidence)")
            }
            let chip = Chip(
                decisionID: decision.decisionID,
                keyword: keyword,
                originalKeyword: edits[decision.decisionID] != nil ? (decision.flatKeyword ?? decision.sourceText) : nil,
                confidence: observation?.confidence,
                evidence: observation?.evidence,
                verdict: verdicts[decision.decisionID] ?? .approved,
                detail: detailParts.joined(separator: "\n")
            )
            rows[decision.assetID, default: AssetRow(
                assetID: decision.assetID,
                sourcePath: asset?.sourcePath,
                fileName: asset?.fileName ?? decision.assetID,
                fileExtension: asset.map { $0.sourceType.rawValue.uppercased() } ?? "",
                chips: []
            )].chips.append(chip)
        }
        return rows.values.sorted { $0.fileName.lowercased() < $1.fileName.lowercased() }
    }

    var approvedCount: Int { verdicts.values.count { $0 == .approved } }
    var rejectedCount: Int { verdicts.values.count { $0 == .rejected } }
    var deferredCount: Int { verdicts.values.count { $0 == .deferred } }

    /// The exportable document: base session + review verdicts and edits.
    var reviewedSession: NormalizationSessionDocument? {
        session.map { SessionReview.applying(verdicts: verdicts, edits: edits, to: $0) }
    }

    // MARK: - Session lifecycle

    /// Build the review base session over the folder's `.ai.json` files.
    /// Model-free; artifacts land inside the app state directory.
    func buildSession(jsonRoot: String, sourceRoot: String) {
        guard !building else { return }
        building = true
        buildError = nil
        let artifactDir = stateDirectory
            .appendingPathComponent("review-artifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString).path

        Task {
            defer { building = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var configuration = ResolvedNormalizationConfiguration.builtInDefaults
                    configuration.vocabularyMode = .observedTags
                    configuration.normalizationMode = .singleImage
                    configuration.recursive = true
                    configuration.sourceRoot = sourceRoot
                    configuration.outputDir = artifactDir
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

    /// Adopt a session document (fresh build, import, or recovery) and
    /// reconstruct verdicts/edits from it.
    func adopt(session sessionDocument: NormalizationSessionDocument) {
        session = sessionDocument
        verdicts = SessionReview.verdicts(in: sessionDocument)
        edits = SessionReview.edits(in: sessionDocument)
        changesSinceAutosave = 0
        lastAutosaveAt = now()
    }

    /// FR4-059: user-initiated file operations surface failures instead of
    /// silently dropping them. Set by the views' save/import/restore actions,
    /// shown beside `buildError`, and echoed to the diagnostic log.
    private(set) var fileError: String?

    func reportFileError(_ action: String, _ error: Error) {
        let message = "\(action) failed: \((error as? SidecarError)?.message ?? error.localizedDescription)"
        fileError = message
        try? GUILog.shared.makeLogger().log(LogRecord(
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
        guard let reviewedSession else { return }
        try NormalizationSessionWriter().write(reviewedSession, to: url.path)
    }

    /// Clean completion: review state is exported or intentionally dropped.
    func completeCleanly() {
        try? FileManager.default.removeItem(at: recoveryURL)
        recoveryAvailable = false
        session = nil
        verdicts = [:]
        edits = [:]
    }

    // MARK: - Verdicts

    func setVerdict(_ verdict: ReviewVerdict, for decisionID: String) {
        guard verdicts[decisionID] != verdict else { return }
        verdicts[decisionID] = verdict
        recordChange()
    }

    func toggle(_ decisionID: String) {
        setVerdict((verdicts[decisionID] ?? .approved) == .approved ? .rejected : .approved, for: decisionID)
    }

    func acceptAll(assetID: String) {
        guard let session else { return }
        for decision in session.perAssetDecisions
        where decision.assetID == assetID && (decision.status == .accepted || verdicts[decision.decisionID] != nil) {
            verdicts[decision.decisionID] = .approved
        }
        recordChange()
    }

    /// Batch approve/reject every currently visible chip (FR4-018).
    func setAllVisible(_ verdict: ReviewVerdict) {
        for row in assetRows {
            for chip in row.chips {
                verdicts[chip.decisionID] = verdict
            }
        }
        recordChange()
    }

    func editKeyword(_ decisionID: String, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edits[decisionID] = trimmed
        verdicts[decisionID] = .approved
        recordChange()
    }

    /// FR4-019 scoped batch correction: apply an edit to every asset in the
    /// current folder carrying the same keyword. Callers confirm explicitly.
    func editEverywhere(keyword: String, to text: String) -> Int {
        guard let session else { return 0 }
        let folded = keyword.lowercased()
        var applied = 0
        for decision in session.perAssetDecisions
        where (edits[decision.decisionID] ?? decision.flatKeyword ?? "").lowercased() == folded {
            edits[decision.decisionID] = text
            verdicts[decision.decisionID] = .approved
            applied += 1
        }
        if applied > 0 { recordChange() }
        return applied
    }

    // MARK: - Autosave (FR4-046a)

    private func recordChange() {
        changesSinceAutosave += 1
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
    }

    func discardRecovery() {
        try? FileManager.default.removeItem(at: recoveryURL)
        recoveryAvailable = false
    }
}
