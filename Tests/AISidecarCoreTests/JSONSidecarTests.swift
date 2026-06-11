import Foundation
import XCTest
@testable import AISidecarCore

final class JSONSidecarTests: XCTestCase {
    func testRawSidecarEncodesSchemaVersionAndEmptyObjectSlots() throws {
        let sidecar = makeSidecar()
        let json = try jsonValue(for: sidecar)
        let object = try XCTUnwrap(json.objectValue)

        XCTAssertEqual(object["schema_version"]?.stringValue, "ai-sidecar-json/1.2")
        XCTAssertNotNil(object["source"])
        XCTAssertNotNil(object["run_configuration"])
        XCTAssertNotNil(object["model_input_profile"])
        XCTAssertEqual(object["subject_isolation"], .object([:]))
        XCTAssertEqual(object["derivatives"]?.arrayValue?.count, 1)
        XCTAssertEqual(object["model_runs"]?.arrayValue?.count, 1)
        XCTAssertNil(object["timing"])
    }

    func testModelRunProvenanceCompletenessIsSerializable() throws {
        let sidecar = makeSidecar()
        let run = try XCTUnwrap(sidecar.modelRuns.first)

        XCTAssertEqual(run.model, "gemma4:26b-a4b-it-qat")
        XCTAssertEqual(run.modelDigest, "sha256:modeldigest")
        XCTAssertEqual(run.runtime, "ollama")
        XCTAssertEqual(run.runtimeVersion, "0.12.6")
        XCTAssertEqual(run.promptVersion, "aisidecar.prompt.whole_image/1.3.0")
        XCTAssertEqual(run.promptSHA256.count, 64)
        XCTAssertEqual(run.responseSchemaVersion, "urn:aisidecar:response:whole-image:1.3.0")
        XCTAssertEqual(run.requestOptions.seed, 123)
        XCTAssertFalse(run.requestOptions.thinkingEnabled)
        XCTAssertEqual(run.inputDerivativeSHA256, sidecar.derivatives.first?.sha256)
    }

    func testRawSidecarDecodesLegacySchemaWithoutTimingOrRuntimeMetrics() throws {
        var object = try XCTUnwrap(try jsonValue(for: makeSidecar()).objectValue)
        object["schema_version"] = .string("ai-sidecar-json/1.0")
        object["timing"] = nil
        var modelRuns = try XCTUnwrap(object["model_runs"]?.arrayValue)
        var modelRun = try XCTUnwrap(modelRuns.first?.objectValue)
        modelRun["runtime_metrics"] = nil
        modelRuns[0] = .object(modelRun)
        object["model_runs"] = .array(modelRuns)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RawJSONSidecar.self, from: try encodedData(for: .object(object)))

        XCTAssertEqual(decoded.schemaVersion, "ai-sidecar-json/1.0")
        XCTAssertNil(decoded.timing)
        XCTAssertNil(decoded.modelRuns.first?.runtimeMetrics)
    }

    func testStructuredErrorsUseStableMachineReadableFields() throws {
        let error = SidecarError(
            code: .modelSchemaViolation,
            stage: .model,
            message: "fixture schema violation",
            recoverable: true
        )
        let sidecar = makeSidecar(errors: [error])
        let object = try XCTUnwrap(try jsonValue(for: sidecar).objectValue)
        let errors = try XCTUnwrap(object["errors"]?.arrayValue)
        let first = try XCTUnwrap(errors.first?.objectValue)

        XCTAssertEqual(first["code"]?.stringValue, "E_MODEL_SCHEMA_VIOLATION")
        XCTAssertEqual(first["stage"]?.stringValue, "model")
        XCTAssertEqual(first["message"]?.stringValue, "fixture schema violation")
        XCTAssertEqual(first["recoverable"]?.boolValue, true)
    }

    func testSidecarDocumentAcceptsMinorVersionAndRejectsHigherMajorVersion() throws {
        var sidecar = makeSidecar()
        sidecar.schemaVersion = "ai-sidecar-json/1.2"
        let data = try encodedData(for: sidecar)

        let document = try RawJSONSidecarDocument(data: data)
        XCTAssertEqual(document.sidecar.schemaVersion, "ai-sidecar-json/1.2")

        var unsupported = sidecar
        unsupported.schemaVersion = "ai-sidecar-json/2.0"
        XCTAssertThrowsError(try RawJSONSidecarDocument(data: try encodedData(for: unsupported))) { error in
            guard let sidecarError = error as? SidecarError else {
                return XCTFail("Expected SidecarError")
            }
            XCTAssertEqual(sidecarError.code, .schemaUnsupported)
            XCTAssertFalse(sidecarError.recoverable)
        }
    }

    func testSidecarDocumentPreservesUnknownFieldsOnRewrite() throws {
        var originalObject = try XCTUnwrap(try jsonValue(for: makeSidecar()).objectValue)
        originalObject["schema_version"] = .string("ai-sidecar-json/1.2")
        originalObject["future_top_level"] = .object(["kept": .bool(true)])

        var source = try XCTUnwrap(originalObject["source"]?.objectValue)
        source["future_source_field"] = .string("source metadata")
        originalObject["source"] = .object(source)

        var runConfiguration = try XCTUnwrap(originalObject["run_configuration"]?.objectValue)
        runConfiguration["future_config_field"] = .number(42)
        originalObject["run_configuration"] = .object(runConfiguration)

        var derivatives = try XCTUnwrap(originalObject["derivatives"]?.arrayValue)
        var derivative = try XCTUnwrap(derivatives[0].objectValue)
        derivative["future_derivative_field"] = .string("derivative metadata")
        derivatives[0] = .object(derivative)
        originalObject["derivatives"] = .array(derivatives)

        var modelRuns = try XCTUnwrap(originalObject["model_runs"]?.arrayValue)
        var modelRun = try XCTUnwrap(modelRuns[0].objectValue)
        modelRun["future_model_run_field"] = .string("run metadata")
        var requestOptions = try XCTUnwrap(modelRun["request_options"]?.objectValue)
        requestOptions["future_request_option"] = .bool(true)
        modelRun["request_options"] = .object(requestOptions)
        modelRuns[0] = .object(modelRun)
        originalObject["model_runs"] = .array(modelRuns)

        var document = try RawJSONSidecarDocument(data: try encodedData(for: .object(originalObject)))
        document.sidecar.errors.append(
            SidecarError(
                code: .validationFailed,
                stage: .write,
                message: "known-field rewrite",
                recoverable: true
            )
        )

        let rewritten = try XCTUnwrap(try document.jsonValue().objectValue)
        XCTAssertEqual(rewritten["future_top_level"]?.objectValue?["kept"]?.boolValue, true)
        XCTAssertEqual(rewritten["source"]?.objectValue?["future_source_field"]?.stringValue, "source metadata")
        XCTAssertEqual(rewritten["run_configuration"]?.objectValue?["future_config_field"]?.numberValue, 42)
        XCTAssertEqual(
            rewritten["derivatives"]?.arrayValue?.first?.objectValue?["future_derivative_field"]?.stringValue,
            "derivative metadata"
        )
        XCTAssertEqual(
            rewritten["model_runs"]?.arrayValue?.first?.objectValue?["future_model_run_field"]?.stringValue,
            "run metadata"
        )
        XCTAssertEqual(
            rewritten["model_runs"]?.arrayValue?.first?.objectValue?["request_options"]?.objectValue?["future_request_option"]?.boolValue,
            true
        )
        XCTAssertEqual(rewritten["errors"]?.arrayValue?.first?.objectValue?["code"]?.stringValue, "E_VALIDATION_FAILED")
    }

    private func makeSidecar(errors: [SidecarError] = []) -> RawJSONSidecar {
        let source = makeSource(fileName: "Bird.NEF", relativePath: "Bird.NEF")
        let derivative = DerivativeRecord(
            role: .wholeImage,
            cachePath: "/cache/Bird.whole.jpg",
            format: .jpeg,
            width: 64,
            height: 32,
            colorSpace: .sRGB,
            appliedOrientation: AppliedOrientation(exifValue: 1),
            recipeVersion: "render-v2-test",
            sha256: String(repeating: "b", count: 64),
            sourceIdentity: source.identity
        )
        let prompt = VersionedPrompt(version: "aisidecar.prompt.whole_image/1.3.0", text: "Prompt")
        let modelRun = ModelRunRecord(
            inputRole: .wholeImage,
            model: "gemma4:26b-a4b-it-qat",
            modelDigest: "sha256:modeldigest",
            runtime: "ollama",
            runtimeVersion: "0.12.6",
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: "urn:aisidecar:response:whole-image:1.3.0",
            requestOptions: ModelRunOptions(seed: 123),
            inputDerivativeSHA256: derivative.sha256,
            rawResponseText: #"{"summary":"fixture"}"#,
            parsedResponseJSON: .object(["summary": .string("fixture")]),
            jsonValid: true,
            durationMs: 9,
            error: nil
        )
        return RawJSONSidecar(
            source: source,
            runConfiguration: .builtInDefaults,
            derivatives: [derivative],
            modelRuns: [modelRun],
            errors: errors,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func jsonValue(for sidecar: RawJSONSidecar) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: encodedData(for: sidecar))
    }

    private func encodedData(for sidecar: RawJSONSidecar) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(sidecar)
    }

    private func encodedData(for value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
