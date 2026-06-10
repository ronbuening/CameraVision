import Foundation

/// Batch-level summary derived from progress records at the end of a folder run.
public struct BatchSummary: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var createdAt: Date
    public var inputPath: String
    public var scanRoot: String
    public var recursive: Bool
    public var outputDir: String?
    public var totalImages: Int
    public var written: Int
    public var skipped: Int
    public var failed: Int
    public var dryRun: Int
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case inputPath = "input_path"
        case scanRoot = "scan_root"
        case recursive
        case outputDir = "output_dir"
        case totalImages = "total_images"
        case written
        case skipped
        case failed
        case dryRun = "dry_run"
        case errors
    }

    public init(
        schemaVersion: String = "ai-sidecar-batch-summary/1.0",
        createdAt: Date = Date(),
        inputPath: String,
        scanRoot: String,
        recursive: Bool,
        outputDir: String?,
        totalImages: Int,
        written: Int,
        skipped: Int,
        failed: Int,
        dryRun: Int,
        errors: [SidecarError]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.inputPath = inputPath
        self.scanRoot = scanRoot
        self.recursive = recursive
        self.outputDir = outputDir
        self.totalImages = totalImages
        self.written = written
        self.skipped = skipped
        self.failed = failed
        self.dryRun = dryRun
        self.errors = errors
    }

    /// Derive folder-run counts and batch-level errors from completed records.
    public static func derive(
        from scanResult: ScanResult,
        records: [ProgressRecord],
        outputDir: String?,
        createdAt: Date = Date(),
        interrupted: Bool = false
    ) -> BatchSummary {
        var errors = records.flatMap(\.errors)
        if interrupted {
            // FR1-012b records interruption in the summary rather than adding a
            // partial per-file record for work that did not complete.
            errors.append(
                SidecarError(
                    code: .interrupted,
                    stage: .write,
                    message: "Batch interrupted before all files completed.",
                    recoverable: true
                )
            )
        }

        return BatchSummary(
            createdAt: createdAt,
            inputPath: scanResult.inputPath,
            scanRoot: scanResult.scanRoot,
            recursive: scanResult.recursive,
            outputDir: outputDir,
            totalImages: scanResult.images.count,
            written: records.filter { $0.status == .written }.count,
            skipped: records.filter { $0.status == .skippedExisting }.count,
            failed: records.filter { $0.status == .failed }.count,
            dryRun: records.filter { $0.status == .dryRun }.count,
            errors: errors
        )
    }
}

/// Writes batch summaries atomically using the same artifact-write contract as sidecars.
public struct BatchSummaryWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    /// Write the summary with the Phase 1 atomic artifact contract.
    public func write(_ summary: BatchSummary, to path: String) throws {
        do {
            let data = try encoder.encode(summary)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to encode batch summary \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
