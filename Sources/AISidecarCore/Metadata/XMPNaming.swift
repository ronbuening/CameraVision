import Foundation

/// Destination path selected for one Phase 2 XMP sidecar candidate.
///
/// The relative path is rooted at the source scan tree and mirrors
/// `SourceImage.relativePath` with the image extension replaced by `.xmp`.
public struct XMPNamingDestination: Sendable, Equatable {
    public var targetXMPPath: String
    public var targetRelativePath: String
    public var groupDirectory: String
    public var groupBasename: String

    public init(
        targetXMPPath: String,
        targetRelativePath: String,
        groupDirectory: String,
        groupBasename: String
    ) {
        self.targetXMPPath = targetXMPPath
        self.targetRelativePath = targetRelativePath
        self.groupDirectory = groupDirectory
        self.groupBasename = groupBasename
    }
}

/// Raw sidecar input plus the XMP destination derived for its source image.
public struct XMPNamingEntry: Sendable, Equatable {
    public var input: ResolvedRawSidecarInput
    public var destination: XMPNamingDestination

    public init(input: ResolvedRawSidecarInput, destination: XMPNamingDestination) {
        self.input = input
        self.destination = destination
    }
}

/// Computes Phase 2 sidecar-only XMP names and destination paths.
public struct XMPNaming {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Resolve an XMP destination for one raw sidecar input.
    ///
    /// Without `--output-dir`, a source path must be resolved so the XMP sidecar
    /// can be planned beside the source image. With `--output-dir`, the
    /// recorded source-relative path is enough for the staging workflow allowed
    /// by FR2-000d.
    public func destination(
        for input: ResolvedRawSidecarInput,
        configuration: ResolvedXMPExportConfiguration
    ) throws -> XMPNamingDestination {
        let source = input.document.sidecar.source
        let relativePath = Self.xmpRelativePath(for: source)
        let components = Self.relativeComponents(for: relativePath)
        let fileName = components.last ?? Self.xmpFileName(for: source)
        let groupDirectory = Array(components.dropLast()).joined(separator: "/")
        let groupBasename = Self.baseName(from: fileName)

        let targetURL: URL
        if let outputDir = configuration.outputDir {
            targetURL = Self.relativeComponents(for: relativePath).reduce(absoluteURL(for: outputDir)) { url, component in
                url.appendingPathComponent(component)
            }
        } else if let sourcePath = input.sourcePath {
            targetURL = sourcePath
                .standardizedFileURL
                .deletingLastPathComponent()
                .appendingPathComponent(Self.xmpFileName(for: source))
        } else {
            throw SidecarError(
                code: .sourceMissing,
                stage: .write,
                message: "Unable to derive beside-source XMP path without a resolved source image: \(input.sidecarPath.path)",
                recoverable: true
            )
        }

        return XMPNamingDestination(
            targetXMPPath: targetURL.standardizedFileURL.path,
            targetRelativePath: relativePath,
            groupDirectory: groupDirectory,
            groupBasename: groupBasename
        )
    }

    /// Return `<base>.xmp` for FR2-001, replacing the image extension.
    public static func xmpFileName(for source: SourceImage) -> String {
        "\(baseName(from: source.fileName)).xmp"
    }

    /// Return the mirrored `.xmp` relative path for staged output.
    public static func xmpRelativePath(for source: SourceImage) -> String {
        let components = relativeComponents(for: source.relativePath)
        guard let fileName = components.last else {
            return xmpFileName(for: source)
        }
        return (Array(components.dropLast()) + ["\(baseName(from: fileName)).xmp"]).joined(separator: "/")
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

    private static func baseName(from fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? fileName : base
    }

    private static func relativeComponents(for relativePath: String) -> [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}
