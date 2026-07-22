import Foundation
import XCTest

@testable import AISidecarCore

final class VisionModelRunnerFactoryTests: XCTestCase {
    func testPinnedAvailableBackendReturnsItsRunner() async throws {
        let apple = FactoryTestDescriptor(id: .apple, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .apple

        let runner = try await factory.make(for: configuration)

        XCTAssertEqual((runner as? FactoryTestRunner)?.backend, .apple)
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
            _ = try await factory.make(for: configuration)
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

    func testAutoSelectsFirstAvailableBackendInRegistryOrder() async throws {
        let apple = FactoryTestDescriptor(id: .apple, availability: .available)
        let ollama = FactoryTestDescriptor(id: .ollama, availability: .available)
        let factory = VisionModelRunnerFactory(registry: VisionBackendRegistry(descriptors: [apple, ollama]))
        var configuration = ResolvedRunConfiguration.builtInDefaults
        configuration.modelBackend = .auto

        let runner = try await factory.make(for: configuration)

        XCTAssertEqual((runner as? FactoryTestRunner)?.backend, .apple)
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
        configuration.dryRun = true

        let runner = try await factory.make(for: configuration)
        let probeCount = await probe.count()

        XCTAssertEqual((runner as? FactoryTestRunner)?.backend, .ollama)
        XCTAssertEqual(probeCount, 0)
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
