import Foundation

/// One source image and the sidecar path planned for it.
public struct SidecarPlanEntry: Sendable, Equatable {
    public var source: SourceImage
    public var sidecarPath: String
    public var sidecarRelativePath: String

    public init(source: SourceImage, sidecarPath: String, sidecarRelativePath: String) {
        self.source = source
        self.sidecarPath = sidecarPath
        self.sidecarRelativePath = sidecarRelativePath
    }
}

/// Residual destination collision detected before any affected file is written.
public struct SidecarPlanCollision: Sendable, Equatable {
    public var sidecarPath: String
    public var sources: [SourceImage]
    public var error: SidecarError

    public init(sidecarPath: String, sources: [SourceImage], error: SidecarError) {
        self.sidecarPath = sidecarPath
        self.sources = sources
        self.error = error
    }
}

/// Complete sidecar destination plan split into writable entries and failures.
public struct SidecarPlan: Sendable, Equatable {
    public var entries: [SidecarPlanEntry]
    public var collisions: [SidecarPlanCollision]

    public init(entries: [SidecarPlanEntry], collisions: [SidecarPlanCollision]) {
        self.entries = entries
        self.collisions = collisions
    }
}

/// Raw-sidecar contract written for an analyzed source image.
public enum RawSidecarKind: Sendable {
    case tagging
    case quality
}

/// Computes Phase 1 raw JSON sidecar names and destination paths.
///
/// Naming preserves the original source extension so RAW/JPEG pairs do not
/// collapse onto the same `.ai.json` basename.
public enum SidecarNaming {
    public static let taggingSuffix = ".ai.json"
    public static let qualitySuffix = ".quality.ai.json"

    /// Return `<original-file-name>.ai.json` for FR1-008.
    public static func sidecarFileName(
        for source: SourceImage,
        kind: RawSidecarKind = .tagging
    ) -> String {
        sidecarFileName(fileName: source.fileName, kind: kind)
    }

    /// Return the mirrored relative path used under `--output-dir`.
    public static func sidecarRelativePath(
        for source: SourceImage,
        kind: RawSidecarKind = .tagging
    ) -> String {
        sidecarRelativePath(relativePath: source.relativePath, fileName: source.fileName, kind: kind)
    }

    /// Resolve the concrete sidecar path for beside-source or mirrored output.
    public static func destinationPath(
        for source: SourceImage,
        outputDir: String?,
        kind: RawSidecarKind = .tagging
    ) -> String {
        destinationPath(
            sourcePath: source.path,
            relativePath: source.relativePath,
            fileName: source.fileName,
            outputDir: outputDir,
            kind: kind
        )
    }

    /// Resolve a sidecar without forcing discovery-only callers to hash the source.
    static func destinationPath(
        for source: ScanInventoryEntry,
        outputDir: String?,
        kind: RawSidecarKind = .tagging
    ) -> String {
        destinationPath(
            sourcePath: source.path,
            relativePath: source.relativePath,
            fileName: source.fileName,
            outputDir: outputDir,
            kind: kind
        )
    }

    /// Resolve a sidecar when a Core presentation boundary has only source location data.
    static func destinationPath(
        sourcePath: String,
        relativePath: String,
        outputDir: String?,
        kind: RawSidecarKind = .tagging
    ) -> String {
        destinationPath(
            sourcePath: sourcePath,
            relativePath: relativePath,
            fileName: URL(fileURLWithPath: sourcePath).lastPathComponent,
            outputDir: outputDir,
            kind: kind
        )
    }

    private static func destinationPath(
        sourcePath: String,
        relativePath: String,
        fileName: String,
        outputDir: String?,
        kind: RawSidecarKind
    ) -> String {
        let destination: URL
        if let outputDir {
            destination = appendRelativeSidecarPath(
                relativePath: relativePath,
                fileName: fileName,
                to: URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath),
                kind: kind
            )
        } else {
            destination = URL(fileURLWithPath: sourcePath)
                .deletingLastPathComponent()
                .appendingPathComponent(sidecarFileName(fileName: fileName, kind: kind))
        }
        return destination.standardizedFileURL.path
    }

    /// Build a pre-write plan and classify case-insensitive collisions.
    public static func plan(
        for sources: [SourceImage],
        outputDir: String?,
        kind: RawSidecarKind = .tagging
    ) -> SidecarPlan {
        let provisional = sources.map { source in
            SidecarPlanEntry(
                source: source,
                sidecarPath: destinationPath(for: source, outputDir: outputDir, kind: kind),
                sidecarRelativePath: sidecarRelativePath(for: source, kind: kind)
            )
        }
        let grouped = Dictionary(grouping: provisional) {
            $0.sidecarPath.precomposedStringWithCanonicalMapping.lowercased()
        }
        // FR1-009a treats case-only path differences as collisions because the
        // target photo archive may live on a case-insensitive filesystem.
        let collidingKeys = Set(grouped.filter { $0.value.count > 1 }.map(\.key))

        let collisions =
            grouped
            .filter { $0.value.count > 1 }
            .map { _, entries in
                let sortedEntries = entries.sorted { $0.source.relativePath < $1.source.relativePath }
                let path = sortedEntries.map(\.sidecarPath).sorted().first ?? entries[0].sidecarPath
                let relativePaths = sortedEntries.map(\.source.relativePath).joined(separator: ", ")
                return SidecarPlanCollision(
                    sidecarPath: path,
                    sources: sortedEntries.map(\.source),
                    error: SidecarError(
                        code: .sidecarCollision,
                        stage: .write,
                        message: "Multiple sources resolve to the same sidecar path: \(relativePaths)",
                        recoverable: true
                    )
                )
            }
            .sorted { $0.sidecarPath < $1.sidecarPath }

        let entries =
            provisional
            .filter { !collidingKeys.contains($0.sidecarPath.lowercased()) }
            .sorted { $0.source.relativePath < $1.source.relativePath }

        return SidecarPlan(entries: entries, collisions: collisions)
    }

    static func siblingSourceURL(for sidecarURL: URL) -> URL {
        let sourceFileName = sidecarBaseFileName(for: sidecarURL) ?? sidecarURL.lastPathComponent
        return sidecarURL.deletingLastPathComponent().appendingPathComponent(sourceFileName).standardizedFileURL
    }

    static func siblingSidecarURL(for sidecarURL: URL) -> URL {
        guard let kind = sidecarKind(for: sidecarURL), let baseName = sidecarBaseFileName(for: sidecarURL) else {
            return sidecarURL
        }
        let siblingSuffix: String
        switch kind {
        case .tagging:
            siblingSuffix = qualitySuffix
        case .quality:
            siblingSuffix = taggingSuffix
        }
        return sidecarURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(siblingSuffix)")
            .standardizedFileURL
    }

    /// Fold `.quality.ai.json` inputs into their tagging siblings.
    ///
    /// Internal so the analyze-and-* pipelines can apply the same pairing to
    /// records produced by an in-process sequential quality run.
    static func groupedSidecarInputs(_ inputs: [ResolvedRawSidecarInput]) -> [ResolvedRawSidecarInput] {
        let grouped = Dictionary(grouping: inputs) { sidecarPairingKey(for: $0.sidecarPath) }
        return grouped.values.compactMap { group in
            // Existing Phase 2 consumers keep the tagging document as their
            // primary input; quality data rides beside it for grading.
            let tagging = group.first { sidecarKind(for: $0.sidecarPath) == .tagging }
            let quality = group.first { sidecarKind(for: $0.sidecarPath) == .quality }
            guard var primary = tagging ?? quality else {
                return nil
            }
            if let quality {
                primary.qualitySidecarPath = quality.sidecarPath
                primary.qualityDocument = quality.document
                if quality.sidecarPath != primary.sidecarPath {
                    primary.warnings.append(contentsOf: quality.warnings)
                    if quality.sourceIdentityStatus == .mismatched {
                        primary.sourceIdentityStatus = .mismatched
                    }
                }
            }
            return primary
        }
        .sorted {
            comparePaths($0.relativePath ?? $0.sidecarPath.path, $1.relativePath ?? $1.sidecarPath.path)
        }
    }

    static func sidecarPairingKey(for url: URL) -> String {
        url.deletingLastPathComponent()
            .appendingPathComponent(sidecarBaseFileName(for: url) ?? url.lastPathComponent)
            .standardizedFileURL.path
    }

    static func sidecarBaseFileName(for url: URL) -> String? {
        guard let kind = sidecarKind(for: url) else {
            return nil
        }
        let suffix: String
        switch kind {
        case .tagging:
            suffix = taggingSuffix
        case .quality:
            suffix = qualitySuffix
        }
        return String(url.lastPathComponent.dropLast(suffix.count))
    }

    static func sidecarKind(for url: URL) -> RawSidecarKind? {
        let fileName = url.lastPathComponent.lowercased()
        if fileName.hasSuffix(qualitySuffix) {
            return .quality
        }
        if fileName.hasSuffix(taggingSuffix) {
            return .tagging
        }
        return nil
    }

    private static func appendRelativeSidecarPath(
        relativePath: String,
        fileName: String,
        to base: URL,
        kind: RawSidecarKind
    ) -> URL {
        relativeComponents(for: sidecarRelativePath(relativePath: relativePath, fileName: fileName, kind: kind))
            .reduce(base) { url, component in
                url.appendingPathComponent(component)
            }
    }

    private static func sidecarFileName(fileName: String, kind: RawSidecarKind) -> String {
        "\(fileName)\(suffix(for: kind))"
    }

    private static func sidecarRelativePath(
        relativePath: String,
        fileName: String,
        kind: RawSidecarKind
    ) -> String {
        let components = relativeComponents(for: relativePath)
        guard let relativeFileName = components.last else {
            return sidecarFileName(fileName: fileName, kind: kind)
        }
        return (Array(components.dropLast()) + ["\(relativeFileName)\(suffix(for: kind))"]).joined(separator: "/")
    }

    private static func suffix(for kind: RawSidecarKind) -> String {
        switch kind {
        case .tagging:
            taggingSuffix
        case .quality:
            qualitySuffix
        }
    }

    private static func relativeComponents(for relativePath: String) -> [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}
