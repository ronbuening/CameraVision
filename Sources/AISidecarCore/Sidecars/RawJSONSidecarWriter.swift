import Foundation

/// Result category for a sidecar write attempt.
///
/// Existing-file skips are successful per-file outcomes, not failures, because
/// FR1-012c uses `--existing skip` as the resume mechanism.
public enum RawJSONSidecarWriteStatus: String, Codable, Sendable, Equatable {
    case written
    case skippedExisting = "skipped_existing"
}

/// Outcome returned after applying the configured existing-file policy.
public struct RawJSONSidecarWriteOutcome: Sendable, Equatable {
    public var status: RawJSONSidecarWriteStatus
    public var sidecarPath: String

    public init(status: RawJSONSidecarWriteStatus, sidecarPath: String) {
        self.status = status
        self.sidecarPath = sidecarPath
    }
}

/// Writes Phase 1 raw JSON sidecars with FR1-010 existing-file semantics.
public struct RawJSONSidecarWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    /// Write a raw sidecar or return a structured existing-file outcome.
    public func write(
        _ sidecar: RawJSONSidecar,
        to destinationPath: String,
        existingPolicy: ExistingPolicy
    ) throws -> RawJSONSidecarWriteOutcome {
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL

        if fileManager.fileExists(atPath: destination.path) {
            switch existingPolicy {
            case .skip:
                // Skips are recorded by the pipeline so reruns can prove that
                // resume behavior came from existing sidecars, not reanalysis.
                return RawJSONSidecarWriteOutcome(status: .skippedExisting, sidecarPath: destination.path)
            case .fail:
                throw SidecarError(
                    code: .sidecarExists,
                    stage: .write,
                    message: "Sidecar already exists: \(destination.path)",
                    recoverable: true
                )
            case .overwrite:
                break
            }
        }

        do {
            let data = try encoder.encode(sidecar)
            try AtomicFileWriter.write(data, to: destination, fileManager: fileManager)
            return RawJSONSidecarWriteOutcome(status: .written, sidecarPath: destination.path)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to encode sidecar \(destination.path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
