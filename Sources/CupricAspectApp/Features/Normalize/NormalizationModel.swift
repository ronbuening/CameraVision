import AISidecarCore
import CryptoKit
import Foundation
import Observation

/// Shell-agnostic normalization state (M6): session context inputs, the
/// model-free normalization run, and CORE-6 summaries for the Inspector
/// (FR4-052–055). XMP writes are routed through `ExportModel` so the
/// dry-run change-plan gate stays mandatory.
@MainActor
@Observable
final class NormalizationModel {
    enum OutcomeFilter: String, CaseIterable {
        case all
        case accepted
        case withheld
        case skipped
        case needsAttention

        var label: String {
            switch self {
            case .all: "All"
            case .accepted: "Accepted"
            case .withheld: "Withheld"
            case .skipped: "Skipped"
            case .needsAttention: "Needs attention"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case running
        case ready
        case failed(message: String)
    }

    // Session context panel state (FR4-052).
    var subject = ""
    var habitat = ""
    var event = ""
    var allowSubjectPropagation = false
    var allowHabitatPropagation = false
    var allowEventPropagation = false
    var unknownPolicy: UnknownSessionContextPolicy = .reject
    /// nil = bundled starter vocabulary.
    var vocabularyPath: String?

    private(set) var phase: Phase = .idle
    private(set) var session: NormalizationSessionDocument?
    private(set) var summaries: [KeywordDecisionSummary] = []
    var outcomeFilter: OutcomeFilter = .all
    var stageFilter: NormalizationDecisionStage?

    private let stateDirectory: URL

    init(stateDirectory: URL = ReviewModel.defaultStateDirectory) {
        self.stateDirectory = stateDirectory
    }

    // MARK: - Derived

    var filteredSummaries: [KeywordDecisionSummary] {
        summaries.filter { summary in
            let outcomeMatch: Bool = switch outcomeFilter {
            case .all: true
            case .accepted: summary.acceptedCount > 0
            case .withheld: summary.withheldCount > 0
            case .skipped: summary.skippedCount > 0
            case .needsAttention: summary.needsAttention
            }
            let stageMatch = stageFilter.map { summary.stages.contains($0) } ?? true
            return outcomeMatch && stageMatch
        }
    }

    var acceptedTotal: Int { summaries.reduce(0) { $0 + $1.acceptedCount } }
    var withheldTotal: Int { summaries.reduce(0) { $0 + $1.withheldCount } }
    var skippedTotal: Int { summaries.reduce(0) { $0 + $1.skippedCount } }
    var canSaveSession: Bool { session != nil }

    var contextRecords: [NormalizationSessionContextRecord] { session?.sessionContext ?? [] }

    /// FR4-054: the session predates the current vocabulary file.
    var vocabularyIsStale: Bool {
        guard let session, let vocabularyPath else { return false }
        guard let data = FileManager.default.contents(atPath: (vocabularyPath as NSString).expandingTildeInPath) else {
            return true
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return hash != session.vocabulary.sha256
    }

    // MARK: - Run (model-free; FR4-054)

    func run(jsonRoot: String, sourceRoot: String) {
        guard phase != .running else { return }
        phase = .running
        let artifactDir = stateDirectory
            .appendingPathComponent("normalize-artifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString).path
        let configuration = buildConfiguration(sourceRoot: sourceRoot, outputDir: artifactDir)

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try NormalizePipeline().runSessionOnly(
                        mode: .fromJSON(path: jsonRoot),
                        configuration: configuration
                    )
                }.value
                adopt(session: result.session)
            } catch {
                phase = .failed(message: (error as? SidecarError)?.message ?? error.localizedDescription)
            }
        }
    }

    func adopt(session sessionDocument: NormalizationSessionDocument) {
        session = sessionDocument
        summaries = NormalizationDecisionExplainer.summaries(for: sessionDocument)
        phase = .ready
    }

    func buildConfiguration(sourceRoot: String, outputDir: String) -> ResolvedNormalizationConfiguration {
        var configuration = ResolvedNormalizationConfiguration.builtInDefaults
        configuration.recursive = true
        configuration.sourceRoot = sourceRoot
        configuration.outputDir = outputDir
        if let vocabularyPath {
            configuration.vocabularyPath = vocabularyPath
        }
        configuration.sessionSubject = subject.isEmpty ? nil : subject
        configuration.sessionHabitat = habitat.isEmpty ? nil : habitat
        configuration.sessionEvent = event.isEmpty ? nil : event
        configuration.allowSessionSubjectPropagation = allowSubjectPropagation
        configuration.allowSessionHabitatPropagation = allowHabitatPropagation
        configuration.allowSessionEventPropagation = allowEventPropagation
        configuration.unknownSessionContextPolicy = unknownPolicy
        return configuration
    }

    func reset() {
        phase = .idle
        session = nil
        summaries = []
        outcomeFilter = .all
        stageFilter = nil
    }

    // MARK: - Session files (FR4-012b, AC4-016)

    /// FR4-059: save/import failures surface in the UI and the diagnostic
    /// log instead of vanishing behind `try?`.
    private(set) var fileError: String?

    func reportFileError(_ action: String, _ error: Error) {
        let message = "\(action) failed: \((error as? SidecarError)?.message ?? error.localizedDescription)"
        fileError = message
        try? GUILog.shared.makeLogger().log(LogRecord(
            level: .error,
            event: "normalize.file_operation_failed",
            message: message,
            errors: (error as? SidecarError).map { [$0] } ?? []
        ))
    }

    func clearFileError() {
        fileError = nil
    }

    func saveSession(to url: URL) throws {
        guard let session else {
            throw SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "No normalization session is loaded; nothing to save.",
                recoverable: true
            )
        }
        try NormalizationSessionWriter().write(session, to: url.path)
    }

    func importSession(from url: URL) throws {
        adopt(session: try NormalizationSessionReader().read(from: url.path))
    }

}
