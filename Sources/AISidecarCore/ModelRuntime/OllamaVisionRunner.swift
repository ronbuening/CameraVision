import Foundation

/// Ollama `/api/chat` implementation of `VisionModelRunner`.
public struct OllamaVisionRunner: VisionModelRunner {
    private let transport: any OllamaHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        transport: any OllamaHTTPTransport = URLSessionOllamaHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    public func prepare(configuration: ResolvedRunConfiguration) async throws -> ModelRuntimeContext {
        do {
            let tags = try await getTags(endpoint: configuration.modelEndpoint)
            let visionTags = await installedVisionTags(from: tags, endpoint: configuration.modelEndpoint)
            guard let model = tags.models.first(where: { $0.name == configuration.model || $0.model == configuration.model }) else {
                throw tagNotFound(configuration.model, visionTags: visionTags)
            }

            let show = try await showModel(model.name, endpoint: configuration.modelEndpoint)
            guard show.capabilities.contains("vision") else {
                throw tagNotFound(configuration.model, visionTags: visionTags)
            }

            let version = try await getVersion(endpoint: configuration.modelEndpoint)
            return ModelRuntimeContext(
                model: model.name,
                modelDigest: Self.normalizedDigest(model.digest),
                runtimeVersion: version.version,
                endpoint: configuration.modelEndpoint,
                installedVisionTags: visionTags
            )
        } catch let error as SidecarError {
            throw error
        } catch {
            throw endpointUnreachable(error)
        }
    }

    public func analyze(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext
    ) async -> ModelRunRecord {
        let startedAt = now()
        do {
            let imageData = try Data(contentsOf: URL(fileURLWithPath: image.cachePath))
            let primaryStartedAt = now()
            let request = try chatRequest(
                imageData: imageData,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime
            )
            let chat = try await chatResponse(request, endpoint: runtime.endpoint, options: options)
            let rawText = chat.message.content
            let evaluation = evaluateModelResponse(rawText, schema: schema)
            let primaryAttempt = responseAttempt(
                kind: .primary,
                prompt: prompt,
                schema: schema,
                options: options,
                rawResponseText: rawText,
                evaluation: evaluation,
                runtimeMetrics: chat.runtimeMetrics,
                startedAt: primaryStartedAt
            )
            if evaluation.jsonValid {
                return record(
                    image: image,
                    inputRole: inputRole,
                    prompt: prompt,
                    schema: schema,
                    options: options,
                    runtime: runtime,
                    rawResponseText: rawText,
                    parsedResponseJSON: evaluation.parsedResponseJSON,
                    jsonValid: true,
                    runtimeMetrics: chat.runtimeMetrics,
                    startedAt: startedAt,
                    error: nil
                )
            }

            var attempts = [primaryAttempt]
            var latestRawText = rawText
            var latestError = evaluation.error
            var finalAttempt = primaryAttempt
            let repairAttemptLimit = max(0, options.responseRepairAttempts)

            for _ in 0..<repairAttemptLimit {
                guard let repairSourceError = latestError else {
                    break
                }
                let repairOptions = Self.repairOptions(from: options)
                let repairPrompt = try repairPrompt(
                    rawResponseText: latestRawText,
                    error: repairSourceError,
                    schema: schema
                )
                let repairStartedAt = now()
                let repairRequest = try chatRequest(
                    imageData: nil,
                    prompt: repairPrompt,
                    schema: schema,
                    options: repairOptions,
                    runtime: runtime
                )

                do {
                    let repairChat = try await chatResponse(
                        repairRequest,
                        endpoint: runtime.endpoint,
                        options: repairOptions
                    )
                    let repairRawText = repairChat.message.content
                    let repairEvaluation = evaluateModelResponse(repairRawText, schema: schema)
                    let repairAttempt = responseAttempt(
                        kind: .repair,
                        prompt: repairPrompt,
                        schema: schema,
                        options: repairOptions,
                        rawResponseText: repairRawText,
                        evaluation: repairEvaluation,
                        runtimeMetrics: repairChat.runtimeMetrics,
                        startedAt: repairStartedAt
                    )
                    attempts.append(repairAttempt)
                    finalAttempt = repairAttempt

                    if repairEvaluation.jsonValid {
                        return record(
                            image: image,
                            inputRole: inputRole,
                            prompt: prompt,
                            schema: schema,
                            options: options,
                            runtime: runtime,
                            rawResponseText: repairRawText,
                            parsedResponseJSON: repairEvaluation.parsedResponseJSON,
                            jsonValid: true,
                            runtimeMetrics: repairChat.runtimeMetrics,
                            startedAt: startedAt,
                            error: nil,
                            responseAttempts: attempts
                        )
                    }

                    latestRawText = repairRawText
                    latestError = repairEvaluation.error
                } catch let error as SidecarError {
                    return record(
                        image: image,
                        inputRole: inputRole,
                        prompt: prompt,
                        schema: schema,
                        options: options,
                        runtime: runtime,
                        rawResponseText: latestRawText,
                        parsedResponseJSON: finalAttempt.parsedResponseJSON,
                        jsonValid: false,
                        runtimeMetrics: finalAttempt.runtimeMetrics,
                        startedAt: startedAt,
                        error: error,
                        responseAttempts: attempts
                    )
                }
            }

            return record(
                image: image,
                inputRole: inputRole,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime,
                rawResponseText: finalAttempt.rawResponseText,
                parsedResponseJSON: finalAttempt.parsedResponseJSON,
                jsonValid: false,
                runtimeMetrics: finalAttempt.runtimeMetrics,
                startedAt: startedAt,
                error: finalAttempt.error,
                responseAttempts: attempts.count > 1 ? attempts : nil
            )
        } catch let error as SidecarError {
            return record(
                image: image,
                inputRole: inputRole,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime,
                rawResponseText: "",
                parsedResponseJSON: nil,
                jsonValid: false,
                startedAt: startedAt,
                error: error
            )
        } catch {
            return record(
                image: image,
                inputRole: inputRole,
                prompt: prompt,
                schema: schema,
                options: options,
                runtime: runtime,
                rawResponseText: "",
                parsedResponseJSON: nil,
                jsonValid: false,
                startedAt: startedAt,
                error: SidecarError(
                    code: .validationFailed,
                    stage: .model,
                    message: "Unable to prepare model input \(image.cachePath): \(error.localizedDescription)",
                    recoverable: true
                )
            )
        }
    }

    private func getTags(endpoint: URL) async throws -> OllamaTagsResponse {
        try await requestJSON(
            OllamaTagsResponse.self,
            request: OllamaHTTPRequest(method: "GET", path: "/api/tags", timeoutSeconds: ModelRunOptions.default.timeoutSeconds),
            endpoint: endpoint
        )
    }

    private func getVersion(endpoint: URL) async throws -> OllamaVersionResponse {
        try await requestJSON(
            OllamaVersionResponse.self,
            request: OllamaHTTPRequest(method: "GET", path: "/api/version", timeoutSeconds: ModelRunOptions.default.timeoutSeconds),
            endpoint: endpoint
        )
    }

    private func showModel(_ model: String, endpoint: URL) async throws -> OllamaShowResponse {
        let body = try Self.encoder().encode(OllamaShowRequest(model: model))
        return try await requestJSON(
            OllamaShowResponse.self,
            request: OllamaHTTPRequest(method: "POST", path: "/api/show", body: body, timeoutSeconds: ModelRunOptions.default.timeoutSeconds),
            endpoint: endpoint
        )
    }

    private func installedVisionTags(from tags: OllamaTagsResponse, endpoint: URL) async -> [String] {
        var visionTags: [String] = []
        for model in tags.models {
            guard let show = try? await showModel(model.name, endpoint: endpoint),
                  show.capabilities.contains("vision")
            else {
                continue
            }
            visionTags.append(model.name)
        }
        return visionTags.sorted()
    }

    private func requestJSON<T: Decodable>(
        _ type: T.Type,
        request: OllamaHTTPRequest,
        endpoint: URL
    ) async throws -> T {
        let response = try await transport.send(request, endpoint: endpoint)
        guard (200..<300).contains(response.statusCode) else {
            throw OllamaHTTPTransportError.unreachable("HTTP \(response.statusCode) from \(request.path).")
        }
        do {
            return try Self.decoder().decode(type, from: response.data)
        } catch {
            throw OllamaHTTPTransportError.unreachable("Invalid JSON from \(request.path): \(error.localizedDescription)")
        }
    }

    private func chatRequest(
        imageData: Data?,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext
    ) throws -> OllamaHTTPRequest {
        let requestBody = OllamaChatRequest(
            model: runtime.model,
            messages: [
                OllamaChatMessage(
                    role: "user",
                    content: prompt.text,
                    images: imageData.map { [$0.base64EncodedString()] }
                )
            ],
            format: schema.schema,
            options: OllamaChatOptions(
                temperature: options.temperature,
                seed: options.seed,
                numCtx: options.contextWindow
            ),
            stream: false,
            think: options.thinkingEnabled,
            keepAlive: options.keepAlive
        )
        return OllamaHTTPRequest(
            method: "POST",
            path: "/api/chat",
            body: try Self.encoder().encode(requestBody),
            timeoutSeconds: options.timeoutSeconds
        )
    }

    private func chatResponse(
        _ request: OllamaHTTPRequest,
        endpoint: URL,
        options: ModelRunOptions
    ) async throws -> OllamaChatResponse {
        let response = try await sendChatWithRetries(request, endpoint: endpoint, options: options)
        return try decodeChatResponse(response)
    }

    private func sendChatWithRetries(
        _ request: OllamaHTTPRequest,
        endpoint: URL,
        options: ModelRunOptions
    ) async throws -> OllamaHTTPResponse {
        let maxAttempts = max(0, options.retryLimit) + 1
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let response = try await transport.send(request, endpoint: endpoint)
                guard (200..<300).contains(response.statusCode) else {
                    throw OllamaHTTPTransportError.unreachable("HTTP \(response.statusCode) from /api/chat.")
                }
                return response
            } catch {
                lastError = error
                if attempt == maxAttempts {
                    break
                }
            }
        }

        if case .timeout(let message)? = lastError as? OllamaHTTPTransportError {
            throw SidecarError(
                code: .modelTimeout,
                stage: .model,
                message: "Ollama model request timed out after \(maxAttempts) attempt(s): \(message)",
                recoverable: true
            )
        }
        throw endpointUnreachable(lastError ?? OllamaHTTPTransportError.unreachable("Unknown transport error."))
    }

    private func decodeChatResponse(_ response: OllamaHTTPResponse) throws -> OllamaChatResponse {
        do {
            return try Self.decoder().decode(OllamaChatResponse.self, from: response.data)
        } catch {
            throw SidecarError(
                code: .modelEndpointUnreachable,
                stage: .model,
                message: "Invalid Ollama /api/chat response: \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func evaluateModelResponse(_ rawResponseText: String, schema: JSONSchemaDocument) -> ModelResponseEvaluation {
        let strippedText = Self.strippingMarkdownFence(from: rawResponseText)
        do {
            let parsed = try Self.decoder().decode(JSONValue.self, from: Data(strippedText.utf8))
            do {
                try JSONSchemaValidator.validate(parsed, against: schema)
                return ModelResponseEvaluation(parsedResponseJSON: parsed, jsonValid: true, error: nil)
            } catch {
                return ModelResponseEvaluation(
                    parsedResponseJSON: parsed,
                    jsonValid: false,
                    error: SidecarError(
                        code: .modelSchemaViolation,
                        stage: .model,
                        message: "Model response violated schema \(schema.version): \(error.localizedDescription)",
                        recoverable: true
                    )
                )
            }
        } catch {
            return ModelResponseEvaluation(
                parsedResponseJSON: nil,
                jsonValid: false,
                error: SidecarError(
                    code: .modelInvalidJSON,
                    stage: .model,
                    message: "Model response was not valid JSON: \(error.localizedDescription)",
                    recoverable: true
                )
            )
        }
    }

    private func responseAttempt(
        kind: ModelResponseAttemptKind,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        rawResponseText: String,
        evaluation: ModelResponseEvaluation,
        runtimeMetrics: ModelRuntimeMetrics?,
        startedAt: Date
    ) -> ModelResponseAttemptRecord {
        ModelResponseAttemptRecord(
            kind: kind,
            promptVersion: prompt.version,
            promptSHA256: prompt.sha256,
            responseSchemaVersion: schema.version,
            requestOptions: options,
            rawResponseText: rawResponseText,
            parsedResponseJSON: evaluation.parsedResponseJSON,
            jsonValid: evaluation.jsonValid,
            durationMs: durationMs(from: startedAt, to: now()),
            runtimeMetrics: runtimeMetrics,
            error: evaluation.error
        )
    }

    private func repairPrompt(
        rawResponseText: String,
        error: SidecarError,
        schema: JSONSchemaDocument
    ) throws -> VersionedPrompt {
        let schemaData = try Self.encoder().encode(schema.schema)
        let schemaText = String(decoding: schemaData, as: UTF8.self)
        let text = """
        PROMPT_VERSION: aisidecar.prompt.model_response_repair/1.0.0

        Return exactly one JSON object matching the JSON Schema below.
        Do not analyze an image; no image is attached.
        Repair only the provided model output.
        Do not add facts that are not already present in the provided model output.
        If a field cannot be recovered from the provided output, use the schema-compliant empty value.
        Do not wrap the response in Markdown.
        Do not include code fences.
        Do not include comments.

        JSON Schema:
        \(schemaText)

        Validation error:
        \(error.code.rawValue): \(error.message)

        Model output to repair:
        ```text
        \(rawResponseText)
        ```

        Return only the repaired JSON object.
        """
        return VersionedPrompt(version: "aisidecar.prompt.model_response_repair/1.0.0", text: text)
    }

    private func record(
        image: DerivativeRecord,
        inputRole: ModelInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchemaDocument,
        options: ModelRunOptions,
        runtime: ModelRuntimeContext,
        rawResponseText: String,
        parsedResponseJSON: JSONValue?,
        jsonValid: Bool,
        runtimeMetrics: ModelRuntimeMetrics? = nil,
        startedAt: Date,
        error: SidecarError?,
        responseAttempts: [ModelResponseAttemptRecord]? = nil
    ) -> ModelRunRecord {
        ModelRunRecord(
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
            rawResponseText: rawResponseText,
            parsedResponseJSON: parsedResponseJSON,
            jsonValid: jsonValid,
            durationMs: durationMs(from: startedAt, to: now()),
            runtimeMetrics: runtimeMetrics,
            error: error,
            responseAttempts: responseAttempts
        )
    }

    private func endpointUnreachable(_ error: Error) -> SidecarError {
        SidecarError(
            code: .modelEndpointUnreachable,
            stage: .model,
            message: "Unable to reach Ollama endpoint: \(error.localizedDescription)",
            recoverable: true
        )
    }

    private func tagNotFound(_ model: String, visionTags: [String]) -> SidecarError {
        let installed = visionTags.isEmpty ? "none" : visionTags.joined(separator: ", ")
        return SidecarError(
            code: .modelTagNotFound,
            stage: .model,
            message: "Ollama model tag not found or not vision-capable: \(model). Installed vision-capable tags: \(installed)",
            recoverable: false
        )
    }

    private func durationMs(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private static func normalizedDigest(_ digest: String) -> String {
        digest.hasPrefix("sha256:") ? digest : "sha256:\(digest)"
    }

    private static func repairOptions(from options: ModelRunOptions) -> ModelRunOptions {
        var repairOptions = options
        repairOptions.temperature = 0
        repairOptions.thinkingEnabled = false
        return repairOptions
    }

    static func strippingMarkdownFence(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), let newline = trimmed.firstIndex(of: "\n") else {
            return rawText
        }
        var body = String(trimmed[trimmed.index(after: newline)...])
        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("```"),
           let fenceStart = body.range(of: "```", options: .backwards)?.lowerBound {
            body = String(body[..<fenceStart])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}

private struct ModelResponseEvaluation {
    var parsedResponseJSON: JSONValue?
    var jsonValid: Bool
    var error: SidecarError?
}

private struct OllamaTagsResponse: Decodable {
    var models: [OllamaTagModel]
}

private struct OllamaTagModel: Decodable {
    var name: String
    var model: String
    var digest: String
}

private struct OllamaVersionResponse: Decodable {
    var version: String
}

private struct OllamaShowRequest: Encodable {
    var model: String
}

private struct OllamaShowResponse: Decodable {
    var capabilities: [String]
}

private struct OllamaChatRequest: Encodable {
    var model: String
    var messages: [OllamaChatMessage]
    var format: JSONValue
    var options: OllamaChatOptions
    var stream: Bool
    var think: Bool
    var keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case format
        case options
        case stream
        case think
        case keepAlive = "keep_alive"
    }
}

private struct OllamaChatMessage: Encodable {
    var role: String
    var content: String
    var images: [String]?
}

private struct OllamaChatOptions: Encodable {
    var temperature: Double
    var seed: Int
    var numCtx: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case seed
        case numCtx = "num_ctx"
    }
}

private struct OllamaChatResponse: Decodable {
    var message: OllamaChatResponseMessage
    var totalDuration: Int64?
    var loadDuration: Int64?
    var promptEvalCount: Int?
    var promptEvalDuration: Int64?
    var evalCount: Int?
    var evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case message
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }

    var runtimeMetrics: ModelRuntimeMetrics? {
        let metrics = ModelRuntimeMetrics(
            totalDurationNs: totalDuration,
            loadDurationNs: loadDuration,
            promptEvalCount: promptEvalCount,
            promptEvalDurationNs: promptEvalDuration,
            evalCount: evalCount,
            evalDurationNs: evalDuration
        )
        return metrics.isEmpty ? nil : metrics
    }
}

private struct OllamaChatResponseMessage: Decodable {
    var content: String
}
