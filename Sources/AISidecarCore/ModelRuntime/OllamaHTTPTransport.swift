import Foundation

/// HTTP request shape used by the Ollama client.
public struct OllamaHTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var body: Data?
    public var timeoutSeconds: Double

    public init(method: String, path: String, body: Data? = nil, timeoutSeconds: Double = 180) {
        self.method = method
        self.path = path
        self.body = body
        self.timeoutSeconds = timeoutSeconds
    }
}

/// HTTP response returned by an Ollama transport.
public struct OllamaHTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

/// Transport errors that participate in Milestone 5 retry classification.
public enum OllamaHTTPTransportError: Error, Sendable, Equatable, LocalizedError {
    case timeout(String)
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let message), .unreachable(let message):
            return message
        }
    }
}

/// Injectable transport so tests can exercise Ollama request logic offline.
public protocol OllamaHTTPTransport: Sendable {
    func send(_ request: OllamaHTTPRequest, endpoint: URL) async throws -> OllamaHTTPResponse
}

/// Live URLSession-backed transport for local Ollama.
public struct URLSessionOllamaHTTPTransport: OllamaHTTPTransport {
    public init() {}

    public func send(_ request: OllamaHTTPRequest, endpoint: URL) async throws -> OllamaHTTPResponse {
        var urlRequest = URLRequest(url: Self.url(for: request.path, endpoint: endpoint))
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeoutSeconds
        urlRequest.httpBody = request.body
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaHTTPTransportError.unreachable("Ollama returned a non-HTTP response.")
            }
            return OllamaHTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as OllamaHTTPTransportError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaHTTPTransportError.timeout(error.localizedDescription)
        } catch {
            throw OllamaHTTPTransportError.unreachable(error.localizedDescription)
        }
    }

    private static func url(for path: String, endpoint: URL) -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativePath: String
        if endpointPath == "api", cleanPath.hasPrefix("api/") {
            relativePath = String(cleanPath.dropFirst("api/".count))
        } else {
            relativePath = cleanPath
        }
        return endpoint.appendingPathComponent(relativePath)
    }
}
