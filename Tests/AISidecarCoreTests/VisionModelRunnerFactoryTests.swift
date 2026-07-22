import Foundation
import XCTest

@testable import AISidecarCore

final class VisionModelRunnerFactoryTests: XCTestCase {
    func testPinnedAvailableBackendReturnsItsRunner() async throws {
        let apple = FactoryTestDescriptor(id: .apple, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .apple

        let selection = try await factory.make(for: configuration)

        XCTAssertEqual((selection.runner as? FactoryTestRunner)?.backend, .apple)
        XCTAssertEqual(selection.configuration, configuration)
    }

    func testPinnedUnavailableBackendFailsWithAdditiveError() async {
        let apple = FactoryTestDescriptor(
            id: .apple,
            availability: .unavailable(reason: "vision input is unavailable", guidance: .test)
        )
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .apple

        do {
            _ = try await factory.resolveBackend(for: configuration)
            XCTFail("expected unavailable backend failure")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelBackendUnavailable)
            XCTAssertEqual(error.stage, .model)
            XCTAssertEqual(
                error.message,
                "Model backend 'apple' is unavailable: vision input is unavailable"
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// A pinned backend is chosen by configuration alone, so constructing its
    /// runner must not touch the network: runs whose images are all skipped
    /// never prepare a model and must keep working with the backend down.
    func testPinnedBackendConstructionPerformsNoAvailabilityProbe() async throws {
        let probe = FactoryAvailabilityProbe()
        let ollama = FactoryTestDescriptor(
            id: .ollama,
            availability: .unavailable(reason: "connection refused", guidance: .test),
            probe: probe
        )
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .ollama

        let selection = try await factory.make(for: configuration)
        let probeCount = await probe.count()

        XCTAssertEqual((selection.runner as? FactoryTestRunner)?.backend, .ollama)
        XCTAssertEqual(selection.configuration, configuration)
        XCTAssertEqual(probeCount, 0)
    }

    /// The pinned Apple backend still fails closed — from its own runner, with
    /// the additive code and the descriptor's reason.
    func testPinnedAppleRunnerRefusesInsidePrepare() async {
        let factory = VisionModelRunnerFactory(
            registry: VisionBackendRegistry(descriptors: [AppleFoundationModelsDescriptor()])
        )
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .apple

        do {
            let selection = try await factory.make(for: configuration)
            _ = try await selection.runner.prepare(configuration: selection.configuration)
            XCTFail("expected unavailable backend failure")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelBackendUnavailable)
            XCTAssertEqual(error.stage, .model)
            XCTAssertEqual(
                error.message,
                "Model backend 'apple' is unavailable: \(AppleFoundationModelsDescriptor.unavailableReason)"
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAutoSelectsFirstAvailableBackendInRegistryOrder() async throws {
        let apple = FactoryTestDescriptor(id: .apple, availability: .available)
        let ollama = FactoryTestDescriptor(id: .ollama, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto

        let selection = try await factory.make(for: configuration)

        XCTAssertEqual((selection.runner as? FactoryTestRunner)?.backend, .apple)
        XCTAssertEqual(selection.configuration.modelBackend, .apple)
    }

    func testAutoFallsBackAfterUnavailableAppleBackend() async throws {
        let apple = FactoryTestDescriptor(
            id: .apple,
            availability: .unavailable(reason: "no vision API", guidance: .test)
        )
        let ollama = FactoryTestDescriptor(id: .ollama, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto

        let descriptor = try await factory.resolveBackend(for: configuration)

        XCTAssertEqual(descriptor.id, .ollama)
    }

    func testAutoFailsWithDeterministicReasonsWhenNoBackendIsAvailable() async {
        let apple = FactoryTestDescriptor(
            id: .apple,
            availability: .unavailable(reason: "no vision API", guidance: .test)
        )
        let ollama = FactoryTestDescriptor(
            id: .ollama,
            availability: .unavailable(reason: "connection refused", guidance: .test)
        )
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto

        do {
            _ = try await factory.make(for: configuration)
            XCTFail("expected unavailable backend failure")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .modelBackendUnavailable)
            XCTAssertEqual(
                error.message,
                "Model backend 'auto' is unavailable: No registered vision backend is available (Apple test: no vision API; Ollama test: connection refused)."
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDryRunPreservesOfflinePlanningWithoutAvailabilityProbe() async throws {
        let probe = FactoryAvailabilityProbe()
        let ollama = FactoryTestDescriptor(
            id: .ollama,
            availability: .unavailable(reason: "connection refused", guidance: .test),
            probe: probe
        )
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto
        configuration.dryRun = true

        let selection = try await factory.make(for: configuration)
        let probeCount = await probe.count()

        XCTAssertEqual((selection.runner as? FactoryTestRunner)?.backend, .ollama)
        XCTAssertEqual(selection.configuration.modelBackend, .ollama)
        XCTAssertEqual(probeCount, 0)
    }

    /// With the live Apple-first registry order, an `auto` planning run must
    /// still carry the default backend's inert runner — not the Apple stub —
    /// and must not probe anyone.
    func testAutoDryRunPrefersDefaultBackendRegardlessOfRegistryOrder() async throws {
        let probe = FactoryAvailabilityProbe()
        let apple = FactoryTestDescriptor(id: .apple, availability: .available, probe: probe)
        let ollama = FactoryTestDescriptor(
            id: .ollama,
            availability: .unavailable(reason: "connection refused", guidance: .test),
            probe: probe
        )
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto
        configuration.dryRun = true

        let selection = try await factory.make(for: configuration)
        let probeCount = await probe.count()

        XCTAssertEqual((selection.runner as? FactoryTestRunner)?.backend, .ollama)
        XCTAssertEqual(selection.configuration.modelBackend, .ollama)
        XCTAssertEqual(probeCount, 0)
    }

    /// The D8-B1 guarantee, reachable half: an `auto` request that resolves the
    /// default backend hands the pipelines a configuration that is byte-identical
    /// to a pinned-Ollama run, so `"auto"` can never reach sidecar provenance.
    func testAutoResolvingOllamaStampsConfigurationByteIdenticalToPinnedRun() async throws {
        let apple = FactoryTestDescriptor(
            id: .apple,
            availability: .unavailable(reason: "no vision API", guidance: .test)
        )
        let ollama = FactoryTestDescriptor(id: .ollama, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var autoConfiguration = ResolvedRunConfiguration.builtInDefaults
        autoConfiguration.modelBackend = .auto
        var pinnedConfiguration = autoConfiguration
        pinnedConfiguration.modelBackend = .ollama

        let selection = try await factory.make(for: autoConfiguration)

        XCTAssertEqual(selection.configuration.modelBackend, .ollama)
        XCTAssertEqual(selection.configuration, pinnedConfiguration)
        let encoder = JSONCoding.documentEncoder()
        XCTAssertEqual(
            try encoder.encode(selection.configuration),
            try encoder.encode(pinnedConfiguration)
        )
        XCTAssertFalse(
            String(decoding: try encoder.encode(selection.configuration), as: UTF8.self)
                .contains("model_backend")
        )
    }
}

private struct FactoryTestDescriptor: VisionBackendDescriptor {
    let id: ModelBackend
    let availabilityResult: BackendAvailability
    let probe: FactoryAvailabilityProbe?

    var displayName: String { id == .apple ? "Apple test" : "Ollama test" }
    let guidance = BackendGuidance.test
    let supportedTuningKnobs: Set<ModelTuningKnob> = []

    init(
        id: ModelBackend,
        availability: BackendAvailability,
        probe: FactoryAvailabilityProbe? = nil
    ) {
        self.id = id
        self.availabilityResult = availability
        self.probe = probe
    }

    func availability(configuration _: ResolvedRunConfiguration) async -> BackendAvailability {
        await probe?.record()
        return availabilityResult
    }

    func discoverModels(configuration _: ResolvedRunConfiguration) async throws -> [BackendModelChoice] {
        []
    }

    func makeRunner() -> any VisionModelRunner {
        FactoryTestRunner(backend: id)
    }
}

private actor FactoryAvailabilityProbe {
    private var value = 0

    func record() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

private struct FactoryTestRunner: VisionModelRunner {
    let backend: ModelBackend

    func prepare(configuration: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        ModelRuntimeContext(
            model: configuration.model,
            modelDigest: "test",
            runtime: backend.rawValue,
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
        fatalError("factory tests never analyze")
    }
}

extension BackendGuidance {
    fileprivate static let test = BackendGuidance(runtimeUnavailableMessage: "test guidance")
}
