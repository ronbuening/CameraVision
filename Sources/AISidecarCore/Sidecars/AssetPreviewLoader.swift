import Foundation

/// Filesystem paths and sidecar facts needed to present one asset preview.
///
/// The value contains no framework image objects, so it can cross concurrency
/// boundaries without unchecked sendability. Derivative paths are present only
/// while their cache files exist; recorded isolation facts remain available
/// after those cache files are purged.
public struct AssetPreviewPresentation: Sendable, Equatable {
    public var sourcePath: String
    public var rawSidecarPath: String
    public var wholeImageDerivativePath: String?
    public var subjectImageDerivativePath: String?
    public var instanceCount: Int?
    public var selectedInstanceIndices: [Int]
    public var isolationStatus: String?
    public var modelRunCount: Int
    public var keywordCandidateCount: Int?
    public var sidecarErrors: [String]

    public init(
        sourcePath: String,
        rawSidecarPath: String,
        wholeImageDerivativePath: String? = nil,
        subjectImageDerivativePath: String? = nil,
        instanceCount: Int? = nil,
        selectedInstanceIndices: [Int] = [],
        isolationStatus: String? = nil,
        modelRunCount: Int = 0,
        keywordCandidateCount: Int? = nil,
        sidecarErrors: [String] = []
    ) {
        self.sourcePath = sourcePath
        self.rawSidecarPath = rawSidecarPath
        self.wholeImageDerivativePath = wholeImageDerivativePath
        self.subjectImageDerivativePath = subjectImageDerivativePath
        self.instanceCount = instanceCount
        self.selectedInstanceIndices = selectedInstanceIndices
        self.isolationStatus = isolationStatus
        self.modelRunCount = modelRunCount
        self.keywordCandidateCount = keywordCandidateCount
        self.sidecarErrors = sidecarErrors
    }
}

/// Loads preview metadata through the canonical raw-sidecar contract.
///
/// Missing sidecars are a normal pre-analysis state. Present sidecars are read
/// once and interpreted through `RawJSONSidecarReader`; presentation-level
/// errors retain the strings used by the existing GUI preview surface.
public struct AssetPreviewLoader {
    private let fileManager: FileManager
    private let reader: RawJSONSidecarReader

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.reader = RawJSONSidecarReader(fileManager: fileManager)
    }

    /// Load paths and facts for one source, using mirrored output naming when requested.
    public func load(
        sourcePath: String,
        relativePath: String,
        outputDir: String?
    ) -> AssetPreviewPresentation {
        let rawSidecarPath = SidecarNaming.destinationPath(
            sourcePath: sourcePath,
            relativePath: relativePath,
            outputDir: outputDir
        )
        var presentation = AssetPreviewPresentation(
            sourcePath: sourcePath,
            rawSidecarPath: rawSidecarPath
        )

        guard fileManager.fileExists(atPath: rawSidecarPath) else {
            return presentation
        }
        guard let data = fileManager.contents(atPath: rawSidecarPath) else {
            presentation.sidecarErrors.append(
                "sidecar unreadable: \(URL(fileURLWithPath: rawSidecarPath).lastPathComponent)"
            )
            return presentation
        }

        let sidecar: RawJSONSidecar
        do {
            sidecar = try reader.decodeForPreview(from: data)
        } catch {
            presentation.sidecarErrors.append("sidecar malformed: \(error.localizedDescription)")
            return presentation
        }

        presentation.modelRunCount = sidecar.modelRuns.count
        presentation.sidecarErrors = sidecar.errors.map { "\($0.code.rawValue): \($0.message)" }
        if let isolation = sidecar.subjectIsolation {
            presentation.instanceCount = isolation.instanceCount
            presentation.selectedInstanceIndices = isolation.selectedInstanceIndices
            presentation.isolationStatus = isolation.status.rawValue
        }

        for derivative in sidecar.derivatives where fileManager.fileExists(atPath: derivative.cachePath) {
            switch derivative.role {
            case .wholeImage:
                presentation.wholeImageDerivativePath = derivative.cachePath
            case .subjectIsolated:
                presentation.subjectImageDerivativePath = derivative.cachePath
            case .fullResolution:
                break
            }
        }
        return presentation
    }
}
