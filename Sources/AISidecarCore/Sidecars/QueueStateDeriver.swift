import Foundation

/// Durable queue state inferred from the artifacts currently present for one source image.
///
/// Run-only failures remain presentation state in the GUI and are deliberately
/// excluded from this disk-derived value.
public enum QueueDerivedState: Sendable, Equatable {
    case discovered
    case analyzed
    case exported
    case xmpPresentExternal
    case xmpMissingWasExported
}

/// Derives the between-launch queue state without hashing or decoding a full raw sidecar.
///
/// The input is a discovery-only inventory entry so interactive rescans retain
/// the Phase 4 lazy-identity boundary. Artifact paths come from the same naming
/// implementations used by the write pipelines.
public struct QueueStateDeriver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Derive the five-state queue truth table for one scanned source image.
    public func derive(for source: ScanInventoryEntry, outputDir: String?) -> QueueDerivedState {
        let rawSidecarPath = SidecarNaming.destinationPath(for: source, outputDir: outputDir)
        let xmpTargetPath = XMPNaming.destinationPath(
            for: source,
            outputDir: outputDir,
            fileManager: fileManager
        )
        let hasRawSidecar = fileManager.fileExists(atPath: rawSidecarPath)
        let hasXMP = fileManager.fileExists(atPath: xmpTargetPath)

        guard hasRawSidecar else {
            return hasXMP ? .xmpPresentExternal : .discovered
        }
        guard hasXMPExportBlock(atPath: rawSidecarPath) else {
            return hasXMP ? .xmpPresentExternal : .analyzed
        }
        return hasXMP ? .exported : .xmpMissingWasExported
    }

    func hasXMPExportBlock(atPath path: String) -> Bool {
        guard let data = fileManager.contents(atPath: path),
            let probe = try? JSONDecoder().decode(XMPExportPresenceProbe.self, from: data)
        else {
            return false
        }
        return probe.xmpExport != nil
    }
}

private struct XMPExportPresenceProbe: Decodable {
    struct Present: Decodable {
        init(from decoder: Decoder) throws {}
    }

    var xmpExport: Present?

    enum CodingKeys: String, CodingKey {
        case xmpExport = "xmp_export"
    }
}
