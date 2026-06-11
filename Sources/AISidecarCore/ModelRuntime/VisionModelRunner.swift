import Foundation

/// Adapter boundary for vision model runtimes used by Phase 1 and later phases.
public protocol VisionModelRunner: Sendable {
    /// Resolve model/runtime identity before a batch starts.
    func prepare(configuration: ResolvedRunConfiguration) async throws -> ModelRuntimeContext

    /// Analyze one model-input derivative and return a provenance-ready record.
    func analyze(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord
}

/// Deterministic runner for tests that need a model result without I/O.
public struct MockVisionModelRunner: VisionModelRunner {
    private let context: ModelRuntimeContext
    private let record: ModelRunRecord

    public init(context: ModelRuntimeContext, record: ModelRunRecord) {
        self.context = context
        self.record = record
    }

    public func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        context
    }

    public func analyze(
        image _: DerivativeRecord,
        inputRole _: ModelInputRole,
        prompt _: VersionedPrompt,
        schema _: JSONSchemaDocument,
        options _: ModelRunOptions,
        runtime _: ModelRuntimeContext
    ) async -> ModelRunRecord {
        record
    }
}

/// Serializable fixture used by `RecordedFixtureRunner`.
public struct RecordedModelFixture: Codable, Sendable, Equatable {
    public var context: ModelRuntimeContext
    public var records: [ModelRunRecord]

    public init(context: ModelRuntimeContext, records: [ModelRunRecord]) {
        self.context = context
        self.records = records
    }
}

/// Replays captured model-run records for offline pipeline tests.
public struct RecordedFixtureRunner: VisionModelRunner {
    private let fixture: RecordedModelFixture

    public init(fixture: RecordedModelFixture) {
        self.fixture = fixture
    }

    public init(fixtureURL: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.fixture = try decoder.decode(RecordedModelFixture.self, from: Data(contentsOf: fixtureURL))
    }

    public func prepare(configuration _: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        fixture.context
    }

    public func analyze(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord {
        if let exact = fixture.records.first(where: {
            $0.inputRole == inputRole && $0.inputDerivativeSHA256 == image.sha256
        }) {
            return exact
        }
        if let byRole = fixture.records.first(where: { $0.inputRole == inputRole }) {
            return byRole
        }

        return ModelRunRecord(
            inputRole: inputRole,
            model: runtime.model,
            modelDigest: runtime.modelDigest,
            runtime: runtime.runtime,
            runtimeVersion: runtime.runtimeVersion,
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: schema.version,
            requestOptions: options,
            inputDerivativeSHA256: image.sha256,
            rawResponseText: "",
            parsedResponseJSON: nil,
            jsonValid: false,
            durationMs: 0,
            error: SidecarError(
                code: .validationFailed,
                stage: .model,
                message: "No recorded model fixture for \(inputRole.rawValue) and derivative \(image.sha256).",
                recoverable: true
            )
        )
    }
}
