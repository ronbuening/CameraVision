import Foundation

/// Per-source outcome for diagnostic model-input export runs.
public enum ModelInputExportStatus: String, Codable, Sendable, Equatable {
    case exported
    case partial
    case skippedExisting = "skipped_existing"
    case failed
}

/// File-level write action recorded for exported model-input artifacts.
public enum ModelInputExportWriteAction: String, Codable, Sendable, Equatable {
    case exported
    case skippedExisting = "skipped_existing"
}

/// One model-input image written, or intentionally left in place, by an export run.
///
/// The provenance mirrors `DerivativeRecord` while using the export destination
/// path, so users can inspect exactly which files would be submitted to a model.
public struct ModelInputExportOutput: Codable, Sendable, Equatable {
    public var role: DerivativeRole
    public var path: String
    public var relativePath: String
    public var action: ModelInputExportWriteAction
    public var format: DerivativeFormat
    public var width: Int
    public var height: Int
    public var colorSpace: ModelInputColorSpace
    public var appliedOrientation: AppliedOrientation
    public var recipeVersion: String
    public var sha256: String
    public var sourceIdentity: SourceIdentity

    enum CodingKeys: String, CodingKey {
        case role
        case path
        case relativePath = "relative_path"
        case action
        case format
        case width
        case height
        case colorSpace = "color_space"
        case appliedOrientation = "applied_orientation"
        case recipeVersion = "recipe_version"
        case sha256
        case sourceIdentity = "source_identity"
    }

    init(
        derivative: DerivativeRecord,
        plannedOutput: ModelInputExportPlannedOutput,
        action: ModelInputExportWriteAction
    ) {
        self.role = derivative.role
        self.path = plannedOutput.path
        self.relativePath = plannedOutput.relativePath
        self.action = action
        self.format = derivative.format
        self.width = derivative.width
        self.height = derivative.height
        self.colorSpace = derivative.colorSpace
        self.appliedOrientation = derivative.appliedOrientation
        self.recipeVersion = derivative.recipeVersion
        self.sha256 = derivative.sha256
        self.sourceIdentity = derivative.sourceIdentity
    }
}

/// One completed source-image record in a model-input export manifest.
public struct ModelInputExportRecord: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var source: SourceImage?
    public var sourcePath: String
    public var relativePath: String?
    public var status: ModelInputExportStatus
    public var outputs: [ModelInputExportOutput]
    public var subjectIsolation: SubjectIsolationRecord?
    public var errors: [SidecarError]
    public var durationMs: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case source
        case sourcePath = "source_path"
        case relativePath = "relative_path"
        case status
        case outputs
        case subjectIsolation = "subject_isolation"
        case errors
        case durationMs = "duration_ms"
    }

    public init(
        timestamp: Date = Date(),
        source: SourceImage?,
        sourcePath: String,
        relativePath: String?,
        status: ModelInputExportStatus,
        outputs: [ModelInputExportOutput] = [],
        subjectIsolation: SubjectIsolationRecord? = nil,
        errors: [SidecarError] = [],
        durationMs: Int
    ) {
        self.timestamp = timestamp
        self.source = source
        self.sourcePath = sourcePath
        self.relativePath = relativePath
        self.status = status
        self.outputs = outputs
        self.subjectIsolation = subjectIsolation
        self.errors = errors
        self.durationMs = durationMs
    }
}

/// Aggregate counts and errors for one diagnostic export run.
public struct ModelInputExportSummary: Codable, Sendable, Equatable {
    public var totalImages: Int
    public var exported: Int
    public var partial: Int
    public var skipped: Int
    public var failed: Int
    public var errors: [SidecarError]

    enum CodingKeys: String, CodingKey {
        case totalImages = "total_images"
        case exported
        case partial
        case skipped
        case failed
        case errors
    }

    public init(
        totalImages: Int,
        exported: Int,
        partial: Int,
        skipped: Int,
        failed: Int,
        errors: [SidecarError]
    ) {
        self.totalImages = totalImages
        self.exported = exported
        self.partial = partial
        self.skipped = skipped
        self.failed = failed
        self.errors = errors
    }

    public static func derive(
        totalImages: Int,
        records: [ModelInputExportRecord],
        interrupted: Bool
    ) -> ModelInputExportSummary {
        var errors = records.flatMap(\.errors)
        if interrupted {
            errors.append(
                SidecarError(
                    code: .interrupted,
                    stage: .write,
                    message: "Model-input export interrupted before all files completed.",
                    recoverable: true
                )
            )
        }

        return ModelInputExportSummary(
            totalImages: totalImages,
            exported: records.filter { $0.status == .exported }.count,
            partial: records.filter { $0.status == .partial }.count,
            skipped: records.filter { $0.status == .skippedExisting }.count,
            failed: records.filter { $0.status == .failed }.count,
            errors: errors
        )
    }
}

/// Manifest written by `aisidecar analyze --export-model-inputs`.
public struct ModelInputExportManifest: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var createdAt: Date
    public var inputPath: String
    public var scanRoot: String
    public var recursive: Bool
    public var mode: AnalysisMode
    public var exportDir: String
    public var modelInputProfile: ModelInputProfile
    public var records: [ModelInputExportRecord]
    public var summary: ModelInputExportSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case inputPath = "input_path"
        case scanRoot = "scan_root"
        case recursive
        case mode
        case exportDir = "export_dir"
        case modelInputProfile = "model_input_profile"
        case records
        case summary
    }

    public init(
        schemaVersion: String = "ai-sidecar-model-input-export/1.0",
        createdAt: Date = Date(),
        inputPath: String,
        scanRoot: String,
        recursive: Bool,
        mode: AnalysisMode,
        exportDir: String,
        modelInputProfile: ModelInputProfile,
        records: [ModelInputExportRecord],
        summary: ModelInputExportSummary
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.inputPath = inputPath
        self.scanRoot = scanRoot
        self.recursive = recursive
        self.mode = mode
        self.exportDir = exportDir
        self.modelInputProfile = modelInputProfile
        self.records = records
        self.summary = summary
    }
}

/// Result returned by a diagnostic model-input export run.
public struct ModelInputExportResult: Sendable, Equatable {
    public var scanResult: ScanResult
    public var records: [ModelInputExportRecord]
    public var manifestPath: String
    public var manifest: ModelInputExportManifest
    public var interrupted: Bool

    public init(
        scanResult: ScanResult,
        records: [ModelInputExportRecord],
        manifestPath: String,
        manifest: ModelInputExportManifest,
        interrupted: Bool
    ) {
        self.scanResult = scanResult
        self.records = records
        self.manifestPath = manifestPath
        self.manifest = manifest
        self.interrupted = interrupted
    }
}
