import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

@MainActor
final class BackendAwareGUITests: XCTestCase {
    func testProductionAppleDescriptorAppearsUnavailableInSettingsPicker() async throws {
        let fixture = try ConfigFixture(modelBackend: .apple)
        addTeardownBlock { fixture.remove() }
        let registry = VisionBackendRegistry(descriptors: [
            AppleFoundationModelsDescriptor(),
            GUIBackendDescriptor.ollamaAvailable,
        ])
        let settings = SettingsModel(
            configPath: fixture.path,
            environment: [:],
            backendRegistry: registry
        )

        await settings.loadBackendDataIfNeeded()

        let apple = try XCTUnwrap(settings.backendOptions.first { $0.id == .apple })
        XCTAssertEqual(apple.displayName, "Apple on-device")
        XCTAssertEqual(
            apple.availabilityText,
            "unavailable: \(AppleFoundationModelsDescriptor.unavailableReason)"
        )
        XCTAssertEqual(settings.selectedBackendID, .apple)
        XCTAssertFalse(settings.usesEndpoint)
    }

    func testSettingsPickerAvailabilityWriteThroughAndKnobFilteringUseDescriptors() async throws {
        let fixture = try ConfigFixture()
        addTeardownBlock { fixture.remove() }
        let apple = GUIBackendDescriptor(
            id: .apple,
            displayName: "Apple test",
            guidance: .appleTest,
            supportedTuningKnobs: [.temperature],
            availability: .unavailable(reason: "vision API missing", guidance: .appleTest),
            discovery: .failure(.backendUnavailable("vision API missing"))
        )
        let ollama = GUIBackendDescriptor(
            id: .ollama,
            displayName: "Ollama",
            guidance: OllamaBackendDescriptor().guidance,
            supportedTuningKnobs: Set(ModelTuningKnob.allCases),
            availability: .available,
            discovery: .success([BackendModelChoice(id: "vision:test", displayName: "Vision Test")])
        )
        let registry = VisionBackendRegistry(descriptors: [apple, ollama])
        let settings = SettingsModel(
            configPath: fixture.path,
            environment: [:],
            backendRegistry: registry
        )

        await settings.loadBackendDataIfNeeded()

        XCTAssertEqual(settings.backendOptions.map(\.id), [.auto, .apple, .ollama])
        XCTAssertEqual(
            settings.backendOptions.first(where: { $0.id == .apple })?.availabilityText,
            "unavailable: vision API missing"
        )
        XCTAssertEqual(settings.visionTags, ["vision:test"])
        XCTAssertEqual(settings.supportedTuningKnobs, Set(ModelTuningKnob.allCases))

        settings.setModelBackend(.apple)

        XCTAssertEqual(settings.modelBackend, .apple)
        XCTAssertEqual(settings.selectedBackendDisplayName, "Apple test")
        XCTAssertEqual(settings.supportedTuningKnobs, [.temperature])
        XCTAssertFalse(settings.usesEndpoint)
        XCTAssertEqual(
            try ConfigurationResolver.resolve(environment: [:], defaultConfigPath: fixture.path).modelBackend,
            .apple
        )
    }

    func testVisionDiscoveryFailureIsScopedByBackendAtTheSameEndpoint() async {
        let calls = BackendDiscoveryCalls()
        let model = VisionTagsModel(backendLoader: { descriptor, _ in
            await calls.record(descriptor.id)
            if descriptor.id == .apple {
                throw SidecarError.backendUnavailable("Apple discovery failed")
            }
            return [BackendModelChoice(id: "ollama:vision", displayName: "Ollama Vision")]
        })
        let apple = GUIBackendDescriptor.appleAvailable
        let ollama = GUIBackendDescriptor.ollamaAvailable
        let configuration = ResolvedRunConfiguration.builtInDefaults

        await model.loadIfNeeded(descriptor: apple, configuration: configuration)
        XCTAssertEqual(model.backendID, .apple)
        XCTAssertEqual(model.state, .failed(message: "Apple discovery failed"))

        await model.loadIfNeeded(descriptor: ollama, configuration: configuration)
        XCTAssertEqual(model.backendID, .ollama)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.models, [BackendModelChoice(id: "ollama:vision", displayName: "Ollama Vision")])

        await model.loadIfNeeded(descriptor: apple, configuration: configuration)
        XCTAssertEqual(model.backendID, .apple)
        XCTAssertEqual(model.state, .failed(message: "Apple discovery failed"))
        let recordedCalls = await calls.values()
        XCTAssertEqual(recordedCalls, [.apple, .ollama], "the Apple failure is restored from its own cache")
    }

    func testRuntimeGuidanceSwitchesWithConfiguredBackend() async throws {
        let fixture = try ConfigFixture(modelBackend: .apple)
        addTeardownBlock { fixture.remove() }
        let apple = GUIBackendDescriptor(
            id: .apple,
            displayName: "Apple test",
            guidance: .appleTest,
            supportedTuningKnobs: [.temperature],
            availability: .unavailable(reason: "vision API missing", guidance: .appleTest),
            discovery: .failure(.backendUnavailable("vision API missing"))
        )
        let ollama = GUIBackendDescriptor.ollamaAvailable
        let registry = VisionBackendRegistry(descriptors: [apple, ollama])
        let model = RuntimeGuidanceModel(configPath: fixture.path, backendRegistry: registry)

        model.check(environment: [:])
        try await waitForRuntime(model) { $0 == .unreachable(message: "vision API missing") }

        XCTAssertEqual(model.backendID, .apple)
        XCTAssertEqual(model.backendDisplayName, "Apple test")
        XCTAssertEqual(model.backendGuidance.runtimeUnavailableMessage, "Apple runtime guidance")

        try ConfigFileEditor.merge(["model_backend": .string(ModelBackend.ollama.rawValue)], atPath: fixture.path)
        model.check(environment: [:])
        try await waitForRuntime(model) { $0 == .ready(visionTagCount: 1) }

        XCTAssertEqual(model.backendID, .ollama)
        XCTAssertEqual(model.backendDisplayName, "Ollama")
        XCTAssertEqual(model.backendGuidance, OllamaBackendDescriptor().guidance)
    }

    func testPreflightCarriesBackendIdentityAndDescriptorGuidance() async throws {
        let fixture = try ConfigFixture(modelBackend: .apple)
        addTeardownBlock { fixture.remove() }
        let available = GUIBackendDescriptor.appleAvailable
        let availableRegistry = VisionBackendRegistry(descriptors: [available, GUIBackendDescriptor.ollamaAvailable])
        let options = AnalysisOptions(environment: [:], defaultConfigPath: fixture.path)
        options.loadResolvedDefaults()
        let readyModel = AnalysisRunModel(backendRegistry: availableRegistry)

        readyModel.checkPreflight(options: options, recursive: false, outputDir: nil)
        try await waitForPreflight(readyModel)

        XCTAssertEqual(
            readyModel.preflight,
            .ready(
                backendID: .apple,
                backendDisplayName: "Apple test",
                model: "system-language-model",
                digest: "system:test",
                runtimeVersion: "test"
            )
        )
        XCTAssertEqual(readyModel.supportedTuningKnobs(for: .apple), [.temperature])

        let unavailable = GUIBackendDescriptor(
            id: .apple,
            displayName: "Apple test",
            guidance: .appleTest,
            supportedTuningKnobs: [.temperature],
            availability: .unavailable(reason: "vision API missing", guidance: .appleTest),
            discovery: .failure(.backendUnavailable("vision API missing"))
        )
        let failedModel = AnalysisRunModel(
            backendRegistry: VisionBackendRegistry(descriptors: [unavailable, GUIBackendDescriptor.ollamaAvailable])
        )

        failedModel.checkPreflight(options: options, recursive: false, outputDir: nil)
        try await waitForPreflight(failedModel)

        XCTAssertEqual(
            failedModel.preflight,
            .failed(
                backendID: .apple,
                backendDisplayName: "Apple test",
                message: "Apple preflight guidance"
            )
        )
    }

    private func waitForRuntime(
        _ model: RuntimeGuidanceModel,
        predicate: (RuntimeGuidanceModel.Status) -> Bool
    ) async throws {
        for _ in 0..<200 {
            if predicate(model.status) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for runtime guidance; last status: \(model.status)")
    }

    private func waitForPreflight(_ model: AnalysisRunModel) async throws {
        for _ in 0..<200 {
            if model.preflight != .checking { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for backend preflight")
    }
}

private struct GUIBackendDescriptor: VisionBackendDescriptor {
    let id: ModelBackend
    let displayName: String
    let guidance: BackendGuidance
    let supportedTuningKnobs: Set<ModelTuningKnob>
    let availabilityResult: BackendAvailability
    let discovery: Result<[BackendModelChoice], SidecarError>

    init(
        id: ModelBackend,
        displayName: String,
        guidance: BackendGuidance,
        supportedTuningKnobs: Set<ModelTuningKnob>,
        availability: BackendAvailability,
        discovery: Result<[BackendModelChoice], SidecarError>
    ) {
        self.id = id
        self.displayName = displayName
        self.guidance = guidance
        self.supportedTuningKnobs = supportedTuningKnobs
        self.availabilityResult = availability
        self.discovery = discovery
    }

    static let appleAvailable = GUIBackendDescriptor(
        id: .apple,
        displayName: "Apple test",
        guidance: .appleTest,
        supportedTuningKnobs: [.temperature],
        availability: .available,
        discovery: .success([
            BackendModelChoice(id: "system-language-model", displayName: "System Language Model")
        ])
    )

    static let ollamaAvailable = GUIBackendDescriptor(
        id: .ollama,
        displayName: "Ollama",
        guidance: OllamaBackendDescriptor().guidance,
        supportedTuningKnobs: Set(ModelTuningKnob.allCases),
        availability: .available,
        discovery: .success([BackendModelChoice(id: "ollama:vision", displayName: "Ollama Vision")])
    )

    func availability(configuration _: ResolvedRunConfiguration) async -> BackendAvailability {
        availabilityResult
    }

    func discoverModels(configuration _: ResolvedRunConfiguration) async throws -> [BackendModelChoice] {
        try discovery.get()
    }

    func makeRunner() -> any VisionModelRunner {
        GUIBackendRunner(backend: id)
    }
}

private struct GUIBackendRunner: VisionModelRunner {
    let backend: ModelBackend

    func prepare(configuration: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        ModelRuntimeContext(
            model: backend == .apple ? "system-language-model" : configuration.model,
            modelDigest: backend == .apple ? "system:test" : "sha256:test",
            runtime: backend == .apple ? "apple-foundation-models" : "ollama",
            runtimeVersion: "test",
            endpoint: configuration.modelEndpoint
        )
    }

    func analyze(
        image _: DerivativeRecord,
        inputRole _: ModelInputRole,
        prompt _: VersionedPrompt,
        schema _: JSONSchemaDocument,
        options _: ModelRunOptions,
        runtime _: ModelRuntimeContext,
        isInterrupted _: (@Sendable () -> Bool)?
    ) async -> ModelRunRecord {
        fatalError("GUI backend tests never analyze")
    }
}

private actor BackendDiscoveryCalls {
    private var recorded: [ModelBackend] = []

    func record(_ backend: ModelBackend) {
        recorded.append(backend)
    }

    func values() -> [ModelBackend] {
        recorded
    }
}

private struct ConfigFixture: Sendable {
    let directory: URL
    let path: String

    init(modelBackend: ModelBackend? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("backend-aware-gui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("config.json").path
        if let modelBackend {
            try ConfigFileEditor.merge(["model_backend": .string(modelBackend.rawValue)], atPath: path)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension BackendGuidance {
    fileprivate static let appleTest = BackendGuidance(
        runtimeUnavailableMessage: "Apple runtime guidance",
        preflightUnavailableMessage: "Apple preflight guidance"
    )
}

extension SidecarError {
    fileprivate static func backendUnavailable(_ message: String) -> SidecarError {
        SidecarError(code: .modelBackendUnavailable, stage: .model, message: message, recoverable: true)
    }
}
