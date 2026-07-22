import AISidecarCore
import Foundation
import Observation

/// Backend connectivity per FR4-051: checked on demand (launch, entering
/// options, pre-run, manual refresh) — never polled.
enum PreflightState: Equatable {
    case unknown
    case checking
    case ready(
        backendID: ModelBackend,
        backendDisplayName: String,
        model: String,
        digest: String,
        runtimeVersion: String
    )
    case failed(backendID: ModelBackend, backendDisplayName: String, message: String)
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
    private let backendRegistry: VisionBackendRegistry
    private let runnerFactory: VisionModelRunnerFactory

    init(backendRegistry: VisionBackendRegistry = .live) {
        self.backendRegistry = backendRegistry
        self.runnerFactory = VisionModelRunnerFactory(registry: backendRegistry)
    }

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
            var requestedBackend = options.resolvedBackend
            var descriptor: (any VisionBackendDescriptor)?
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                requestedBackend = configuration.modelBackend
                let resolvedDescriptor = try await runnerFactory.resolveBackend(for: configuration)
                descriptor = resolvedDescriptor
                let runner = resolvedDescriptor.makeRunner()
                let runtime = try await runner.prepare(configuration: configuration)
                guard generation == preflightGeneration else { return }
                preflight = .ready(
                    backendID: resolvedDescriptor.id,
                    backendDisplayName: resolvedDescriptor.displayName,
                    model: runtime.model,
                    digest: runtime.modelDigest,
                    runtimeVersion: runtime.runtimeVersion
                )
            } catch {
                guard generation == preflightGeneration else { return }
                let failedDescriptor = descriptor ?? displayDescriptor(for: requestedBackend)
                preflight = .failed(
                    backendID: failedDescriptor?.id ?? requestedBackend,
                    backendDisplayName: failedDescriptor?.displayName ?? requestedBackend.displayName,
                    message: Self.guidance(for: error, descriptor: failedDescriptor)
                )
            }
        }
    }

    func start(options: AnalysisOptions, inputPath: String, recursive: Bool, outputDir: String?, expectedTotal: Int) {
        guard !isRunning else { return }
        phase = .running
        done = 0
        writtenCount = 0
        // A sequential quality run reports every image twice — once per pass —
        // so the progress denominator has to cover both passes.
        total =
            expectedTotal
            * Self.passCount(assessQuality: options.assessQuality, qualityScanMode: options.qualityScanMode)
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
            var descriptor: (any VisionBackendDescriptor)?
            do {
                let configuration = try options.buildConfiguration(recursive: recursive, outputDir: outputDir)
                descriptor = displayDescriptor(for: configuration.modelBackend)
                // The factory gates a pinned backend inside `prepare`, so a run
                // whose images are all skipped still needs no backend I/O.
                let runner = try await runnerFactory.make(for: configuration)
                let pipeline = AnalyzePipeline(logger: GUILog.shared.makeLogger(), runner: runner)
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
                phase = .failed(message: Self.guidance(for: error, descriptor: descriptor))
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

    /// How many pipeline passes the configured options will run per image.
    nonisolated static func passCount(assessQuality: Bool, qualityScanMode: QualityScanMode) -> Int {
        assessQuality && qualityScanMode == .sequential ? 2 : 1
    }

    /// Reduce a run's progress records to the Step 5 summary. Pure so tests
    /// can exercise it without a pipeline run.
    ///
    /// A sequential quality run emits one record per pass per image; records
    /// are grouped by source so the summary counts images, with a failure in
    /// either pass dominating and written dominating skipped.
    nonisolated static func outcome(from records: [ProgressRecord], interrupted: Bool) -> RunOutcome {
        var outcome = RunOutcome(interrupted: interrupted)
        var errorCounts: [String: Int] = [:]
        var groupedStatus: [String: ProgressStatus] = [:]
        var ungrouped: [ProgressStatus] = []
        for record in records {
            if record.status == .failed {
                for error in record.errors {
                    errorCounts[error.code.rawValue, default: 0] += 1
                }
            }
            guard let sourcePath = record.sourcePath else {
                ungrouped.append(record.status)
                continue
            }
            if let existing = groupedStatus[sourcePath] {
                groupedStatus[sourcePath] = mergedStatus(existing, record.status)
            } else {
                groupedStatus[sourcePath] = record.status
            }
        }
        for status in Array(groupedStatus.values) + ungrouped {
            switch status {
            case .written: outcome.written += 1
            case .skippedExisting: outcome.skipped += 1
            case .failed: outcome.failed += 1
            case .dryRun: break
            }
        }
        outcome.errorSummaries =
            errorCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) × \($0.value)" }
        return outcome
    }

    private nonisolated static func mergedStatus(_ lhs: ProgressStatus, _ rhs: ProgressStatus) -> ProgressStatus {
        func rank(_ status: ProgressStatus) -> Int {
            switch status {
            case .failed: 3
            case .written: 2
            case .skippedExisting: 1
            case .dryRun: 0
            }
        }
        return rank(rhs) > rank(lhs) ? rhs : lhs
    }

    func descriptor(for backend: ModelBackend) -> (any VisionBackendDescriptor)? {
        displayDescriptor(for: backend)
    }

    func resolveBackend(for configuration: ResolvedRunConfiguration) async throws -> any VisionBackendDescriptor {
        try await runnerFactory.resolveBackend(for: configuration)
    }

    func supportedTuningKnobs(for backend: ModelBackend) -> Set<ModelTuningKnob> {
        displayDescriptor(for: backend)?.supportedTuningKnobs ?? []
    }

    private func displayDescriptor(for backend: ModelBackend) -> (any VisionBackendDescriptor)? {
        if case .ready(let backendID, _, _, _, _) = preflight,
            backend == .auto || backend == backendID,
            let descriptor = backendRegistry.descriptor(for: backendID)
        {
            return descriptor
        }
        if backend != .auto {
            return backendRegistry.descriptor(for: backend)
        }
        return backendRegistry.descriptor(for: .ollama) ?? backendRegistry.descriptors.first
    }

    /// User-facing preflight/run remediation comes from the selected backend descriptor.
    private static func guidance(for error: Error, descriptor: (any VisionBackendDescriptor)?) -> String {
        guard let sidecarError = error as? SidecarError else {
            return error.localizedDescription
        }
        switch sidecarError.code {
        case .modelEndpointUnreachable, .modelBackendUnavailable:
            return descriptor?.guidance.preflightUnavailableMessage ?? sidecarError.message
        case .modelTagNotFound:
            guard let help = descriptor?.guidance.modelNotFoundHelp else { return sidecarError.message }
            return sidecarError.message + " " + help
        default:
            return sidecarError.message
        }
    }
}
