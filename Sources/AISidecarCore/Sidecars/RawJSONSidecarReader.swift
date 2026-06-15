import Foundation

/// Reads Phase 1 raw JSON sidecars for Phase 2 export planning.
///
/// The reader accepts additive `ai-sidecar-json/1.x` documents, rejects higher
/// major versions, and returns the schema-evolution wrapper so later milestones
/// can preserve unknown fields if a raw sidecar is intentionally rewritten.
public struct RawJSONSidecarReader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Read a raw sidecar document from a filesystem path.
    public func read(from path: String) throws -> RawJSONSidecarDocument {
        try read(from: absoluteURL(for: path))
    }

    /// Read a raw sidecar document from a file URL.
    public func read(from url: URL) throws -> RawJSONSidecarDocument {
        let url = url.standardizedFileURL
        do {
            let data = try Data(contentsOf: url)
            try validateRawSidecarEnvelope(data: data, path: url.path)
            return try RawJSONSidecarDocument(data: data)
        } catch let error as SidecarError {
            throw scanStageError(error)
        } catch {
            throw validationError(
                "Unable to read raw sidecar \(url.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func validateRawSidecarEnvelope(data: Data, path: String) throws {
        let json: JSONValue
        do {
            json = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw validationError("Malformed raw sidecar JSON at \(path): \(error.localizedDescription)", recoverable: true)
        }

        guard let object = json.objectValue else {
            throw validationError("Raw sidecar document must be a JSON object: \(path)", recoverable: true)
        }
        guard let schemaVersion = object["schema_version"]?.stringValue else {
            throw validationError("Raw sidecar document is missing schema_version: \(path)", recoverable: true)
        }
        try validateSchemaVersion(schemaVersion)
    }

    private func validateSchemaVersion(_ schemaVersion: String) throws {
        let supportedSchemaName = "ai-sidecar-json"
        guard
            let slashIndex = schemaVersion.firstIndex(of: "/"),
            schemaVersion[..<slashIndex] == supportedSchemaName
        else {
            throw validationError("JSON file is not a Phase 1 raw sidecar: \(schemaVersion)", recoverable: true)
        }

        let version = schemaVersion[schemaVersion.index(after: slashIndex)...]
        let majorText = version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let majorText, let major = Int(majorText), major == 1 else {
            throw SidecarError(
                code: .schemaUnsupported,
                stage: .scan,
                message: "Unsupported raw sidecar schema version: \(schemaVersion).",
                recoverable: false
            )
        }
    }

    private func scanStageError(_ error: SidecarError) -> SidecarError {
        SidecarError(
            code: error.code,
            stage: .scan,
            message: error.message,
            recoverable: error.recoverable
        )
    }

    private func validationError(_ message: String, recoverable: Bool) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .scan, message: message, recoverable: recoverable)
    }

    private func absoluteURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL
    }
}
