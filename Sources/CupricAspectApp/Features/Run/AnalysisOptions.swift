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
    var assessQuality = false
    var qualityScanMode: QualityScanMode = ResolvedRunConfiguration.builtInDefaults.qualityScanMode
    var qualityGradingEnabled = false
    var qualityWriteRating = QualityGradingPolicy.builtInDefaults.writeRating
    var qualityConflictPolicy = ResolvedQualityGradingConfiguration.builtInDefaults.conflictPolicy
    /// Rendering profile name controlling the image size sent to the model.
    var profile: String = ModelInputProfile.defaultProfile.name
    /// Context-window value recorded for every run and ignored by backends that do not support it.
    var contextWindow: Int = ResolvedRunConfiguration.builtInDefaults.modelContextWindow

    /// Resolved display values (model tag, endpoint) from the config chain.
    private(set) var resolvedModel = ""
    private(set) var resolvedBackend = ModelBackend.ollama
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
        resolvedBackend = resolved.modelBackend
        resolvedEndpoint = resolved.modelEndpoint.absoluteString
        guard !defaultsLoaded else { return }
        defaultsLoaded = true
        mode = resolved.mode
        gps = resolved.gpsContext
        existing = resolved.existing
        concurrency = min(8, max(1, resolved.stageConcurrency))
        profile = resolved.profile
        contextWindow = resolved.modelContextWindow
        assessQuality = resolved.taskProfile == .taggingWithQuality
        qualityScanMode = resolved.qualityScanMode
        if let exportDefaults = try? ConfigurationResolver.resolveApplySession(
            environment: environment,
            defaultConfigPath: defaultConfigPath
        ) {
            xmpConflictPolicy = exportDefaults.xmpConflictPolicy
            qualityGradingEnabled = exportDefaults.qualityGrading.enabled
            qualityWriteRating = exportDefaults.qualityGrading.policy.writeRating
            qualityConflictPolicy = exportDefaults.qualityGrading.conflictPolicy
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
                qualityAssessment: assessQuality,
                qualityScanMode: qualityScanMode,
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

    func qualityGradingOverrides(enabled: Bool? = nil) -> QualityGradingConfigurationOverrides {
        QualityGradingConfigurationOverrides(
            enabled: enabled ?? qualityGradingEnabled,
            conflictPolicy: qualityConflictPolicy,
            writeRating: qualityWriteRating
        )
    }

    func qualityGradingOverrides(controlsEnabled: Bool) -> QualityGradingConfigurationOverrides {
        guard controlsEnabled else {
            return QualityGradingConfigurationOverrides(enabled: false)
        }
        return qualityGradingOverrides()
    }
}
