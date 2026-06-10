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

/// Computes Phase 1 raw JSON sidecar names and destination paths.
///
/// Naming preserves the original source extension so RAW/JPEG pairs do not
/// collapse onto the same `.ai.json` basename.
public enum SidecarNaming {
    /// Return `<original-file-name>.ai.json` for FR1-008.
    public static func sidecarFileName(for source: SourceImage) -> String {
        "\(source.fileName).ai.json"
    }

    /// Return the mirrored relative path used under `--output-dir`.
    public static func sidecarRelativePath(for source: SourceImage) -> String {
        let components = relativeComponents(for: source.relativePath)
        guard let fileName = components.last else {
            return sidecarFileName(for: source)
        }
        return (Array(components.dropLast()) + ["\(fileName).ai.json"]).joined(separator: "/")
    }

    /// Resolve the concrete sidecar path for beside-source or mirrored output.
    public static func destinationPath(
        for source: SourceImage,
        outputDir: String?
    ) -> String {
        let destination: URL
        if let outputDir {
            destination = appendRelativeSidecarPath(
                for: source,
                to: URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath)
            )
        } else {
            destination = URL(fileURLWithPath: source.path)
                .deletingLastPathComponent()
                .appendingPathComponent(sidecarFileName(for: source))
        }
        return destination.standardizedFileURL.path
    }

    /// Build a pre-write plan and classify case-insensitive collisions.
    public static func plan(
        for sources: [SourceImage],
        outputDir: String?
    ) -> SidecarPlan {
        let provisional = sources.map { source in
            SidecarPlanEntry(
                source: source,
                sidecarPath: destinationPath(for: source, outputDir: outputDir),
                sidecarRelativePath: sidecarRelativePath(for: source)
            )
        }
        let grouped = Dictionary(grouping: provisional) { $0.sidecarPath.lowercased() }
        // FR1-009a treats case-only path differences as collisions because the
        // target photo archive may live on a case-insensitive filesystem.
        let collidingKeys = Set(grouped.filter { $0.value.count > 1 }.map(\.key))

        let collisions = grouped
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

        let entries = provisional
            .filter { !collidingKeys.contains($0.sidecarPath.lowercased()) }
            .sorted { $0.source.relativePath < $1.source.relativePath }

        return SidecarPlan(entries: entries, collisions: collisions)
    }

    private static func appendRelativeSidecarPath(for source: SourceImage, to base: URL) -> URL {
        relativeComponents(for: sidecarRelativePath(for: source)).reduce(base) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private static func relativeComponents(for relativePath: String) -> [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}
