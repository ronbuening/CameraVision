import Foundation

struct ModelInputExportPlannedOutput: Sendable, Equatable {
    var role: DerivativeRole
    var path: String
    var relativePath: String
}

struct ModelInputExportPlanEntry: Sendable, Equatable {
    var source: SourceImage
    var plannedOutputs: [ModelInputExportPlannedOutput]

    func plannedOutput(for role: DerivativeRole) -> ModelInputExportPlannedOutput? {
        plannedOutputs.first { $0.role == role }
    }
}

struct ModelInputExportPlanCollision: Sendable, Equatable {
    var sources: [SourceImage]
    var error: SidecarError
}

struct ModelInputExportPlan: Sendable, Equatable {
    var entries: [ModelInputExportPlanEntry]
    var collisions: [ModelInputExportPlanCollision]
}

enum ModelInputExportNaming {
    static func plan(
        for sources: [SourceImage],
        mode: AnalysisMode,
        profile: ModelInputProfile,
        exportDirectory: String
    ) -> ModelInputExportPlan {
        let provisional = sources.map { source in
            ModelInputExportPlanEntry(
                source: source,
                plannedOutputs: plannedOutputs(
                    for: source,
                    mode: mode,
                    profile: profile,
                    exportDirectory: exportDirectory
                )
            )
        }
        let outputPairs = provisional.flatMap { entry in
            entry.plannedOutputs.map { output in (entry.source, output) }
        }
        let grouped = Dictionary(grouping: outputPairs) {
            $0.1.path.precomposedStringWithCanonicalMapping.lowercased()
        }
        let collidingKeys = Set(grouped.filter { $0.value.count > 1 }.map(\.key))
        let collidingSourcePaths = Set(
            grouped
                .filter { collidingKeys.contains($0.key) }
                .flatMap { $0.value.map(\.0.path) }
        )

        let collisions =
            grouped
            .filter { collidingKeys.contains($0.key) }
            .map { _, pairs in
                let sources = pairs.map(\.0).sorted { $0.relativePath < $1.relativePath }
                let outputPath = pairs.map(\.1.path).sorted().first ?? "unknown"
                let relativePaths = sources.map(\.relativePath).joined(separator: ", ")
                return ModelInputExportPlanCollision(
                    sources: sources,
                    error: SidecarError(
                        code: .sidecarCollision,
                        stage: .write,
                        message:
                            "Multiple sources resolve to the same model-input export path \(outputPath): \(relativePaths)",
                        recoverable: true
                    )
                )
            }

        return ModelInputExportPlan(
            entries:
                provisional
                .filter { !collidingSourcePaths.contains($0.source.path) }
                .sorted { $0.source.relativePath < $1.source.relativePath },
            collisions: collisions
        )
    }

    private static func plannedOutputs(
        for source: SourceImage,
        mode: AnalysisMode,
        profile: ModelInputProfile,
        exportDirectory: String
    ) -> [ModelInputExportPlannedOutput] {
        roles(for: mode).map { role in
            let relativePath = relativeOutputPath(for: source, role: role, profile: profile)
            let path = relativeComponents(for: relativePath)
                .reduce(URL(fileURLWithPath: exportDirectory)) { url, component in
                    url.appendingPathComponent(component)
                }
                .standardizedFileURL
                .path
            return ModelInputExportPlannedOutput(role: role, path: path, relativePath: relativePath)
        }
    }

    private static func roles(for mode: AnalysisMode) -> [DerivativeRole] {
        switch mode {
        case .whole:
            return [.wholeImage]
        case .subject:
            return [.subjectIsolated]
        case .both:
            return [.wholeImage, .subjectIsolated]
        }
    }

    private static func relativeOutputPath(
        for source: SourceImage,
        role: DerivativeRole,
        profile: ModelInputProfile
    ) -> String {
        let components = relativeComponents(for: source.relativePath)
        let directoryComponents = Array(components.dropLast())
        let fileName = components.last ?? source.fileName
        let outputName = "\(fileName).aisidecar.\(role.rawValue).\(format(for: role, profile: profile).fileExtension)"
        return (directoryComponents + [outputName]).joined(separator: "/")
    }

    private static func format(for role: DerivativeRole, profile: ModelInputProfile) -> DerivativeFormat {
        switch role {
        case .wholeImage:
            return profile.preferredWholeImageFormat
        case .subjectIsolated:
            return .jpeg
        case .fullResolution:
            return .tiff
        }
    }

    private static func relativeComponents(for relativePath: String) -> [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}
