import AISidecarCore
import Foundation
import Observation

/// User-adjustable run options (Wizard Step 3). Values map one-to-one onto
/// Core enums (FR4-044); resolved against the shared config.json via
/// `ConfigurationResolver` so GUI and CLI defaults can never diverge.
@MainActor
@Observable
final class AnalysisOptions {
    private let environment: [String: String]
    private let defaultConfigPath: String?

    var mode: AnalysisMode = .both
    var gps: GPSContextMode = .coarse
    var existing: ExistingPolicy = .skip
    var concurrency = 1
    var advancedOpen = false
    var modelOverride: String?
    var xmpConflictPolicy: XMPConflictPolicy = ResolvedApplySessionConfiguration.builtInDefaults.xmpConflictPolicy
    /// Rendering profile name controlling the image size sent to the model.
    var profile: String = ModelInputProfile.defaultProfile.name
    /// Ollama num_ctx token window requested per model call.
    var contextWindow: Int = ResolvedRunConfiguration.builtInDefaults.modelContextWindow

    /// Resolved display values (model tag, endpoint) from the config chain.
    private(set) var resolvedModel = ""
    private(set) var resolvedEndpoint = ""
    private(set) var defaultsLoaded = false

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultConfigPath: String? = nil
    ) {
        self.environment = environment
        self.defaultConfigPath = defaultConfigPath
    }

    var effectiveModel: String {
        modelOverride ?? resolvedModel
    }

    func loadResolvedDefaults() {
        guard
            let resolved = try? ConfigurationResolver.resolve(
                environment: environment,
                defaultConfigPath: defaultConfigPath
            )
        else { return }
        resolvedModel = resolved.model
        resolvedEndpoint = resolved.modelEndpoint.absoluteString
        guard !defaultsLoaded else { return }
        defaultsLoaded = true
        mode = resolved.mode
        gps = resolved.gpsContext
        existing = resolved.existing
        concurrency = min(8, max(1, resolved.stageConcurrency))
        profile = resolved.profile
        contextWindow = resolved.modelContextWindow
        if let exportDefaults = try? ConfigurationResolver.resolveApplySession(
            environment: environment,
            defaultConfigPath: defaultConfigPath
        ) {
            xmpConflictPolicy = exportDefaults.xmpConflictPolicy
        }
    }

    func resetToResolvedDefaults() {
        defaultsLoaded = false
        loadResolvedDefaults()
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
                model: modelOverride,
                profile: profile,
                stageConcurrency: concurrency,
                gpsContext: gps,
                modelContextWindow: contextWindow
            ),
            environment: environment,
            defaultConfigPath: defaultConfigPath
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
    /// Timestamp of the most recent completed image. The average rate is
    /// measured up to this instant so the currently-processing image (whose
    /// time is still accumulating) never skews the figure.
    private(set) var lastCompletedAt: Date?
    private(set) var writtenCount = 0

    /// Per-record observer so the import queue can advance asset states live.
    var onRecord: ((ProgressRecord) -> Void)?

    private var monitor: InterruptionMonitor?
    private var preflightGeneration = 0

    var progressFraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    var isRunning: Bool { phase == .running || phase == .cancelling }

    /// Smoothed seconds per image over the run so far. Measured from the run
    /// start to the last completed image, so the image currently in flight is
    /// excluded — its still-accumulating time would otherwise inflate the
    /// average, badly so early in a run.
    var secondsPerImage: Double {
        guard let startedAt, let lastCompletedAt else { return 0 }
        let elapsed = lastCompletedAt.timeIntervalSince(startedAt)
        return Self.secondsPerImage(elapsed: elapsed, done: done)
    }

    nonisolated static func secondsPerImage(elapsed: Double, done: Int) -> Double {
        guard done > 0, elapsed > 0.5 else { return 0 }
        return elapsed / Double(done)
    }

    func checkPreflight(options: AnalysisOptions, recursive: Bool, outputDir: String?) {
        preflightGeneration += 1
        let generation = preflightGeneration
        preflight = .checking
        Task {
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                let runtime = try await OllamaVisionRunner().prepare(configuration: configuration)
                guard generation == preflightGeneration else { return }
                preflight = .ready(
                    model: runtime.model,
                    digest: runtime.modelDigest,
                    runtimeVersion: runtime.runtimeVersion
                )
            } catch {
                guard generation == preflightGeneration else { return }
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
        lastCompletedAt = nil
        let monitor = InterruptionMonitor()
        self.monitor = monitor

        let (stream, continuation) = AsyncStream.makeStream(of: ProgressRecord.self)

        Task {
            for await record in stream {
                done += 1
                lastCompletedAt = Date()
                reconcileProgressTotal()
                if record.status == .written { writtenCount += 1 }
                if let relativePath = record.relativePath { currentFile = relativePath }
                onRecord?(record)
            }
        }

        Task {
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                let pipeline = AnalyzePipeline(logger: GUILog.shared.makeLogger(), runner: OllamaVisionRunner())
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
        lastCompletedAt = nil
    }

    func applyProgressForTesting(done: Int, total: Int) {
        self.done = done
        self.total = total
        reconcileProgressTotal()
    }

    /// Seed the timing state so `secondsPerImage` can be exercised without a
    /// live pipeline run. `lastCompletedAt == nil` models an image in flight
    /// with nothing completed yet.
    func applyTimingForTesting(done: Int, startedAt: Date, lastCompletedAt: Date?) {
        self.done = done
        self.startedAt = startedAt
        self.lastCompletedAt = lastCompletedAt
    }

    private func reconcileProgressTotal() {
        if done > total {
            total = done
        }
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
        outcome.errorSummaries =
            errorCounts
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
            return
                "Ollama isn't reachable. If it's installed, open the Ollama app (or run `ollama serve`); if not, download it from \(RuntimeGuidanceModel.downloadURL). Then retry."
        case .modelTagNotFound:
            return sidecarError.message + " Pull it with `ollama pull <tag>` or pick an installed vision model."
        default:
            return sidecarError.message
        }
    }
}
