import AISidecarCore
import Foundation

/// Between-launch queue states derived from files on disk, per the binding
/// table in the plan's M1 (requirements FR4-011 in-memory form + FR4-049).
/// Transient in-run states (rendering, analyzing, …) arrive with M2's job
/// engine; do not add derived states beyond this table.
enum AssetQueueState: Equatable {
    case discovered
    case analyzed
    case exported
    case xmpPresentExternal
    case xmpMissingWasExported
    case failed(code: String)

    var displayName: String {
        switch self {
        case .discovered: "discovered"
        case .analyzed: "analyzed"
        case .exported: "exported"
        case .xmpPresentExternal: "XMP present (external)"
        case .xmpMissingWasExported: "XMP missing (was exported)"
        case .failed(let code): "failed · \(code)"
        }
    }
}

/// One row of the in-memory asset queue (FR4-046: no persistence).
struct AssetRecord: Identifiable, Equatable, Sendable {
    var path: String
    var relativePath: String
    var fileName: String
    var fileExtension: String
    var fileSize: Int64
    var stateKind: StateKind
    var failureCode: String?
    var failureMessage: String?

    var id: String { path }

    /// Sendable-friendly flat mirror of `AssetQueueState`.
    enum StateKind: String, Sendable {
        case discovered
        case analyzed
        case exported
        case xmpPresentExternal
        case xmpMissingWasExported
        case failed
    }

    var state: AssetQueueState {
        switch stateKind {
        case .discovered: .discovered
        case .analyzed: .analyzed
        case .exported: .exported
        case .xmpPresentExternal: .xmpPresentExternal
        case .xmpMissingWasExported: .xmpMissingWasExported
        case .failed: .failed(code: failureCode ?? "unknown")
        }
    }
}

/// Pure file→state derivation. Mirrors Core's naming rules —
/// `SidecarNaming` (`<file-name>.ai.json`, mirrored under an output dir) and
/// `XMPNaming` (image extension replaced by `.xmp`) — so the GUI never
/// invents artifact paths Core would not produce.
enum AssetQueueDerivation {
    /// Raw-sidecar path for a source image (beside source, or mirrored under
    /// `outputDir` exactly like `SidecarNaming.destinationPath`).
    static func rawSidecarPath(sourcePath: String, relativePath: String, outputDir: String?) -> String {
        if let outputDir {
            return URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath)
                .appendingPathComponent(relativePath + ".ai.json")
                .standardizedFileURL.path
        }
        return sourcePath + ".ai.json"
    }

    /// XMP target path for a source image (image extension replaced by
    /// `.xmp`, beside source or mirrored under `outputDir` like `XMPNaming`).
    static func xmpTargetPath(sourcePath: String, relativePath: String, outputDir: String?) -> String {
        if let outputDir {
            return URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath)
                .appendingPathComponent(replacingExtensionWithXMP(relativePath))
                .standardizedFileURL.path
        }
        let url = URL(fileURLWithPath: sourcePath)
        return url.deletingLastPathComponent()
            .appendingPathComponent(replacingExtensionWithXMP(url.lastPathComponent))
            .path
    }

    private static func replacingExtensionWithXMP(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.isEmpty {
            return path + ".xmp"
        }
        return url.deletingPathExtension().appendingPathExtension("xmp").relativePath
    }

    /// True when the raw sidecar carries the FR4-049 `xmp_export` block.
    /// Until CORE-4 lands no file has it, so XMP presence derives
    /// "XMP present (external)" — correct by construction.
    static func hasXMPExportBlock(rawSidecarPath: String, fileManager: FileManager = .default) -> Bool {
        guard let data = fileManager.contents(atPath: rawSidecarPath),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return false
        }
        return dictionary["xmp_export"] != nil
    }

    /// Derive the between-launch state for one asset from disk (plan M1 table).
    static func deriveState(
        sourcePath: String,
        relativePath: String,
        outputDir: String?,
        fileManager: FileManager = .default
    ) -> AssetRecord.StateKind {
        let sidecar = rawSidecarPath(sourcePath: sourcePath, relativePath: relativePath, outputDir: outputDir)
        let xmpTarget = xmpTargetPath(sourcePath: sourcePath, relativePath: relativePath, outputDir: outputDir)
        let hasSidecar = fileManager.fileExists(atPath: sidecar)
        let hasXMP = fileManager.fileExists(atPath: xmpTarget)

        guard hasSidecar else {
            return hasXMP ? .xmpPresentExternal : .discovered
        }
        guard hasXMPExportBlock(rawSidecarPath: sidecar, fileManager: fileManager) else {
            return hasXMP ? .xmpPresentExternal : .analyzed
        }
        return hasXMP ? .exported : .xmpMissingWasExported
    }
}
