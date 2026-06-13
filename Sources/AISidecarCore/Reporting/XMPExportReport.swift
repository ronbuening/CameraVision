import Foundation

/// Source-file hash comparison proving Phase 2 did not modify source images.
public struct XMPSourceHashCheck: Codable, Sendable, Equatable {
    public var sourcePath: String
    public var beforeSHA256: String?
    public var afterSHA256: String?
    public var unchanged: Bool
    public var error: SidecarError?

    enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case beforeSHA256 = "before_sha256"
        case afterSHA256 = "after_sha256"
        case unchanged
        case error
    }

    public init(
        sourcePath: String,
        beforeSHA256: String?,
        afterSHA256: String?,
        unchanged: Bool,
        error: SidecarError? = nil
    ) {
        self.sourcePath = sourcePath
        self.beforeSHA256 = beforeSHA256
        self.afterSHA256 = afterSHA256
        self.unchanged = unchanged
        self.error = error
    }
}

/// Report entry for one target XMP sidecar.
public struct XMPExportTargetReport: Codable, Sendable, Equatable {
    public var plan: XMPChangePlan
    public var status: XMPExportTargetStatus
    public var preview: XMPWritePreview?
    public var writeResult: XMPWriteResult?
    public var validation: XMPMergeValidationResult?
    public var backup: XMPBackupRecord?
    public var sourceHashChecks: [XMPSourceHashCheck]
    public var errors: [SidecarError]
    public var durationMs: Int

    enum CodingKeys: String, CodingKey {
        case plan
        case status
        case preview
        case writeResult = "write_result"
        case validation
        case backup
        case sourceHashChecks = "source_hash_checks"
        case errors
        case durationMs = "duration_ms"
    }

    public init(
        plan: XMPChangePlan,
        status: XMPExportTargetStatus,
        preview: XMPWritePreview? = nil,
        writeResult: XMPWriteResult? = nil,
        validation: XMPMergeValidationResult? = nil,
        backup: XMPBackupRecord? = nil,
        sourceHashChecks: [XMPSourceHashCheck] = [],
        errors: [SidecarError] = [],
        durationMs: Int
    ) {
        self.plan = plan
        self.status = status
        self.preview = preview
        self.writeResult = writeResult
        self.validation = validation
        self.backup = backup
        self.sourceHashChecks = sourceHashChecks
        self.errors = errors
        self.durationMs = durationMs
    }
}

/// Machine-readable report for a Phase 2 XMP export run.
public struct XMPExportReport: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var createdAt: Date
    public var inputPath: String
    public var reportDirectory: String?
    public var dryRun: Bool
    public var configuration: ResolvedXMPExportConfiguration
    public var engine: MetadataWriteEngineContext
    public var targetReports: [XMPExportTargetReport]
    public var inputFailures: [XMPChangePlanInputFailure]
    public var applicationInstructions: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case inputPath = "input_path"
        case reportDirectory = "report_directory"
        case dryRun = "dry_run"
        case configuration
        case engine
        case targetReports = "target_reports"
        case inputFailures = "input_failures"
        case applicationInstructions = "application_instructions"
    }

    public init(
        schemaVersion: String = XMPExportSchemaIdentifiers.exportReport,
        createdAt: Date,
        inputPath: String,
        reportDirectory: String?,
        dryRun: Bool,
        configuration: ResolvedXMPExportConfiguration,
        engine: MetadataWriteEngineContext,
        targetReports: [XMPExportTargetReport],
        inputFailures: [XMPChangePlanInputFailure],
        applicationInstructions: [String] = XMPExportReport.applicationInstructions
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.inputPath = inputPath
        self.reportDirectory = reportDirectory
        self.dryRun = dryRun
        self.configuration = configuration
        self.engine = engine
        self.targetReports = targetReports
        self.inputFailures = inputFailures
        self.applicationInstructions = applicationInstructions
    }

    public static let applicationInstructions = [
        "Lightroom Classic: select already-imported photos and use Metadata > Read Metadata from Files to load sidecar changes.",
        "Capture One: sidecar loading depends on Metadata preferences, especially Auto Sync Sidecar XMP, Load, and Full Sync."
    ]

    public var writtenCount: Int {
        targetReports.filter { $0.status == .written || $0.status == .created }.count
    }

    public var failedCount: Int {
        targetReports.filter { $0.status == .failed }.count + inputFailures.count
    }
}

/// Writes XMP export reports atomically.
public struct XMPExportReportWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func write(_ report: XMPExportReport, to path: String) throws {
        do {
            let data = try encoder.encode(report)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write XMP export report \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
