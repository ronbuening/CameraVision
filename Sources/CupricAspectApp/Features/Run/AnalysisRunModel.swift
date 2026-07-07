import AISidecarCore
import Foundation
import Observation

/// User-adjustable run options (Wizard Step 3). Values map one-to-one onto
/// Core enums (FR4-044); resolved against the shared config.json via
/// `ConfigurationResolver` so GUI and CLI defaults can never diverge.
@MainActor
@Observable
final class AnalysisOptions {
    var mode: AnalysisMode = .both
    var gps: GPSContextMode = .coarse
    var existing: ExistingPolicy = .skip
    var concurrency = 1
    var advancedOpen = false

    /// Resolved display values (model tag, endpoint) from the config chain.
    private(set) var resolvedModel = ""
    private(set) var resolvedEndpoint = ""

    func loadResolvedDefaults() {
        guard let resolved = try? ConfigurationResolver.resolve() else { return }
        resolvedModel = resolved.model
        resolvedEndpoint = resolved.modelEndpoint.absoluteString
        mode = resolved.mode
        gps = resolved.gpsContext
        existing = resolved.existing
        concurrency = min(8, max(1, resolved.stageConcurrency))
    }

    /// Build the run configuration: UI choices as CLI-equivalent overrides on
    /// top of config.json/environment/defaults.
    func buildConfiguration(recursive: Bool, outputDir: String?) throws -> ResolvedRunConfiguration {
        try ConfigurationResolver.resolve(
            cli: RunConfigurationOverrides(
                mode: mode,
                existing: existing,
                recursive: recursive,
                outputDir: outputDir,
                stageConcurrency: concurrency,
                gpsContext: gps
            )
        )
    }
}

/// Ollama connectivity per FR4-051: checked on demand (launch, entering
/// options, pre-run, manual refresh) — never polled.
enum PreflightState: Equatable {
    case unknown
    case checking
    case ready(model: String, digest: String, runtimeVersion: String)
    case failed(message: String)
}

/// Outcome summary of a completed analysis run (Wizard Step 5 until M4's
/// review arrives).
struct RunOutcome: Equatable, Sendable {
    var written = 0
    var skipped = 0
    var failed = 0
    var interrupted = false
    var errorSummaries: [String] = []
}

/// The M2 job engine: preflight + one serialized analysis run at a time,
/// cancel via `InterruptionMonitor`, per-asset progress via the CORE-1 hook.
/// GUI mode suppresses batch report artifacts (CORE-2); `.ai.json` sidecars
/// are written exactly as the CLI writes them.
@MainActor
@Observable
final class AnalysisRunModel {
    enum Phase: Equatable {
        case idle
        case running
        case cancelling
        case finished(RunOutcome)
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var preflight: PreflightState = .unknown

    private(set) var done = 0
    private(set) var total = 0
    private(set) var currentFile = ""
    private(set) var startedAt: Date?
    private(set) var writtenCount = 0

    /// Per-record observer so the import queue can advance asset states live.
    var onRecord: ((ProgressRecord) -> Void)?

    private var monitor: InterruptionMonitor?

    var progressFraction: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    var isRunning: Bool { phase == .running || phase == .cancelling }

    /// Smoothed images/second over the run so far.
    var rate: Double {
        guard let startedAt, writtenCount > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed > 0.5 ? Double(writtenCount) / elapsed : 0
    }

    func checkPreflight(options: AnalysisOptions, recursive: Bool, outputDir: String?) {
        guard preflight != .checking else { return }
        preflight = .checking
        Task {
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                let runtime = try await OllamaVisionRunner().prepare(configuration: configuration)
                preflight = .ready(
                    model: runtime.model,
                    digest: runtime.modelDigest,
                    runtimeVersion: runtime.runtimeVersion
                )
            } catch {
                preflight = .failed(message: Self.guidance(for: error))
            }
        }
    }

    func start(options: AnalysisOptions, inputPath: String, recursive: Bool, outputDir: String?, expectedTotal: Int) {
        guard !isRunning else { return }
        phase = .running
        done = 0
        writtenCount = 0
        total = expectedTotal
        currentFile = ""
        startedAt = Date()
        let monitor = InterruptionMonitor()
        self.monitor = monitor

        let (stream, continuation) = AsyncStream.makeStream(of: ProgressRecord.self)

        Task {
            for await record in stream {
                done += 1
                if record.status == .written { writtenCount += 1 }
                if let relativePath = record.relativePath { currentFile = relativePath }
                onRecord?(record)
            }
        }

        Task {
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                let pipeline = AnalyzePipeline(logger: Logger(sink: { _ in }), runner: OllamaVisionRunner())
                let result = try await Task.detached(priority: .userInitiated) {
                    try await pipeline.run(
                        inputPath: inputPath,
                        configuration: configuration,
                        interruptionMonitor: monitor,
                        writesBatchArtifacts: false,
                        progressHandler: { continuation.yield($0) }
                    )
                }.value
                continuation.finish()

                phase = .finished(Self.outcome(from: result.records, interrupted: result.interrupted))
            } catch {
                continuation.finish()
                phase = .failed(message: Self.guidance(for: error))
            }
        }
    }

    func cancel() {
        guard phase == .running else { return }
        phase = .cancelling
        monitor?.requestInterruption()
    }

    func reset() {
        phase = .idle
        done = 0
        total = 0
        writtenCount = 0
        currentFile = ""
        startedAt = nil
    }

    /// Reduce a run's progress records to the Step 5 summary. Pure so tests
    /// can exercise it without a pipeline run.
    nonisolated static func outcome(from records: [ProgressRecord], interrupted: Bool) -> RunOutcome {
        var outcome = RunOutcome(interrupted: interrupted)
        var errorCounts: [String: Int] = [:]
        for record in records {
            switch record.status {
            case .written: outcome.written += 1
            case .skippedExisting: outcome.skipped += 1
            case .failed:
                outcome.failed += 1
                for error in record.errors {
                    errorCounts[error.code.rawValue, default: 0] += 1
                }
            case .dryRun: break
            }
        }
        outcome.errorSummaries = errorCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) × \($0.value)" }
        return outcome
    }

    /// User-facing message for preflight/run failures; mirrors the README's
    /// Ollama troubleshooting guidance for the common cases.
    private static func guidance(for error: Error) -> String {
        guard let sidecarError = error as? SidecarError else {
            return error.localizedDescription
        }
        switch sidecarError.code {
        case .modelEndpointUnreachable:
            return "Ollama isn't reachable. Start it with `ollama serve` (or open the Ollama app), then retry."
        case .modelTagNotFound:
            return sidecarError.message + " Pull it with `ollama pull <tag>` or pick an installed vision model."
        default:
            return sidecarError.message
        }
    }
}
