import AISidecarCore
import Foundation
import Observation

/// The unified GUI export surface (M7): dry-run change plan first (FR4-029),
/// then the real write through the frozen-session writer — the same
/// `ApplySessionPipeline` + `XMPExportPipeline` chain the CLI uses, with
/// backups, source-hash checks, post-write validation, and restore-on-failure
/// (FR4-028/035). Used by the write, normalize, and apply flows alike.
@MainActor
@Observable
final class ExportModel {
    enum Phase: Equatable {
        case idle
        case planning
        case planReady
        case writing
        case written
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var changePlan: XMPChangePlanDocument?
    private(set) var exportReport: XMPExportReport?

    private var pendingSessionPath: String?
    private var pendingSourceRoot: String?
    private var pendingOutputDir: String?
    private let stateDirectory: URL

    init(stateDirectory: URL = ReviewModel.defaultStateDirectory) {
        self.stateDirectory = stateDirectory
    }

    var plannedTargets: [XMPChangePlan] { changePlan?.targetPlans ?? [] }
    var planFailures: [XMPChangePlanInputFailure] { changePlan?.inputFailures ?? [] }

    /// Targets whose plans failed (e.g. malformed existing XMP — FR4-035a):
    /// they are excluded from the write and shown with their error codes.
    var failedTargets: [XMPChangePlan] {
        plannedTargets.filter { !$0.failures.isEmpty }
    }

    var writableTargets: [XMPChangePlan] {
        plannedTargets.filter(\.failures.isEmpty)
    }

    /// Targets whose dry-run preview shows an existing XMP being merged into
    /// (the default backup-and-merge policy) rather than a new file created.
    var mergeTargets: [XMPChangePlan] {
        writableTargets.filter { $0.preview?.wouldCreate == false }
    }

    /// Existing keywords the merge preserves across all merge targets.
    var preservedKeywordCount: Int {
        mergeTargets.reduce(0) {
            $0 + ($1.preview.map { $0.existingFlatKeywords.count + $0.existingHierarchicalKeywords.count } ?? 0)
        }
    }

    /// FR4-029: dry-run the session and hold the change plan for review.
    func plan(session: NormalizationSessionDocument, sourceRoot: String, outputDir: String?) {
        guard phase != .planning, phase != .writing else { return }
        phase = .planning
        changePlan = nil
        exportReport = nil

        let sessionDir = stateDirectory.appendingPathComponent("export-sessions", isDirectory: true)
        Task {
            do {
                let (plan, sessionPath) = try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
                    let sessionPath = sessionDir.appendingPathComponent("export-\(UUID().uuidString).json").path
                    try NormalizationSessionWriter().write(session, to: sessionPath)
                    var configuration = ResolvedApplySessionConfiguration.builtInDefaults
                    configuration.sourceRoot = sourceRoot
                    configuration.outputDir = outputDir
                    configuration.dryRun = true
                    let result = try ApplySessionPipeline(
                        xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
                    ).run(sessionPath: sessionPath, configuration: configuration)
                    return (result.changePlan, sessionPath)
                }.value
                changePlan = plan
                pendingSessionPath = sessionPath
                pendingSourceRoot = sourceRoot
                pendingOutputDir = outputDir
                phase = .planReady
            } catch {
                phase = .failed(message: (error as? SidecarError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// Execute the reviewed plan (writes only the plannable targets; the
    /// engine re-reads current sidecars and semantically merges).
    func confirmWrite() {
        guard phase == .planReady,
              let sessionPath = pendingSessionPath,
              let sourceRoot = pendingSourceRoot else {
            return
        }
        phase = .writing
        let outputDir = pendingOutputDir
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var configuration = ResolvedApplySessionConfiguration.builtInDefaults
                    configuration.sourceRoot = sourceRoot
                    configuration.outputDir = outputDir
                    configuration.dryRun = false
                    return try ApplySessionPipeline(
                        xmpPipeline: XMPExportPipeline(logger: Logger(sink: { _ in }))
                    ).run(sessionPath: sessionPath, configuration: configuration)
                }.value
                exportReport = result.exportReport
                phase = .written
            } catch {
                phase = .failed(message: (error as? SidecarError)?.message ?? error.localizedDescription)
            }
        }
    }

    func cancelPlan() {
        guard phase == .planReady else { return }
        phase = .idle
        changePlan = nil
    }

    func reset() {
        phase = .idle
        changePlan = nil
        exportReport = nil
        pendingSessionPath = nil
    }
}
