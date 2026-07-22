import Foundation

/// Recoverable input failure carried into Phase 3 session/report artifacts.
public struct NormalizationInputFailure: Codable, Sendable, Equatable {
    public var path: String
    public var relativePath: String?
    public var error: SidecarError

    enum CodingKeys: String, CodingKey {
        case path
        case relativePath = "relative_path"
        case error
    }

    public init(path: String, relativePath: String?, error: SidecarError) {
        self.path = path
        self.relativePath = relativePath
        self.error = error
    }
}

/// Resolved source inputs prepared for a Phase 3 normalization session.
public struct NormalizationResolvedInputBatch: Sendable, Equatable {
    public var workflow: NormalizationInputWorkflow
    public var inputPath: String
    public var inputBasePath: String
    public var scanRoot: String?
    public var rawSidecarInputs: [ResolvedRawSidecarInput]
    public var sourceAssets: [NormalizationSourceAsset]
    public var sourceAISidecars: [NormalizationSourceAISidecarRecord]
    public var sameBaseNameGroups: [NormalizationSourceGroup]
    public var warnings: [SidecarError]
    public var failures: [NormalizationInputFailure]

    public init(
        workflow: NormalizationInputWorkflow,
        inputPath: String,
        inputBasePath: String,
        scanRoot: String?,
        rawSidecarInputs: [ResolvedRawSidecarInput] = [],
        sourceAssets: [NormalizationSourceAsset],
        sourceAISidecars: [NormalizationSourceAISidecarRecord],
        sameBaseNameGroups: [NormalizationSourceGroup],
        warnings: [SidecarError],
        failures: [NormalizationInputFailure]
    ) {
        self.workflow = workflow
        self.inputPath = inputPath
        self.inputBasePath = inputBasePath
        self.scanRoot = scanRoot
        self.rawSidecarInputs = rawSidecarInputs
        self.sourceAssets = sourceAssets
        self.sourceAISidecars = sourceAISidecars
        self.sameBaseNameGroups = sameBaseNameGroups
        self.warnings = warnings
        self.failures = failures
    }
}

/// Resolves Phase 3 normalize input modes without running model analysis.
public struct NormalizationInputResolver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Resolve the selected `normalize` input mode for a session skeleton.
    public func resolve(
        mode: NormalizationInvocationMode,
        configuration: ResolvedNormalizationConfiguration
    ) throws -> NormalizationResolvedInputBatch {
        switch mode {
        case .fromJSON(let path):
            return try resolveFromJSON(path, configuration: configuration)
        case .fileList(let path):
            return try resolveFileList(path, configuration: configuration)
        case .analyze(let inputPath):
            return try resolveAnalyzeInput(inputPath, configuration: configuration)
        }
    }

    /// Build normalization inputs from raw sidecars already resolved by an upstream pipeline.
    ///
    /// Analyze-and-normalize uses this path to avoid rereading `.ai.json` files
    /// after Phase 1 analysis, especially when the invocation later removes new
    /// raw sidecars for `--no-write-ai-json`.
    public func resolve(
        rawSidecarBatch batch: RawJSONSidecarInputBatch,
        workflow: NormalizationInputWorkflow,
        inputPath: String,
        inputBasePath: String,
        scanRoot: String?,
        configuration: ResolvedNormalizationConfiguration
    ) -> NormalizationResolvedInputBatch {
        let records = buildAssets(from: batch.inputs)
        let grouped = buildGroups(for: records.assets, pairScope: configuration.pairScope)
        let failures = batch.failures.map {
            NormalizationInputFailure(
                path: $0.sidecarPath.standardizedFileURL.path,
                relativePath: $0.relativePath,
                error: $0.error
            )
        }
        return NormalizationResolvedInputBatch(
            workflow: workflow,
            inputPath: inputPath,
            inputBasePath: inputBasePath,
            scanRoot: scanRoot,
            rawSidecarInputs: batch.inputs,
            sourceAssets: grouped.assets,
            sourceAISidecars: records.sidecars,
            sameBaseNameGroups: grouped.groups,
            warnings: records.warnings,
            failures: failures
        )
    }

    private func resolveFromJSON(
        _ path: String,
        configuration: ResolvedNormalizationConfiguration
    ) throws -> NormalizationResolvedInputBatch {
        let exportConfiguration = ResolvedXMPExportConfiguration(
            recursive: configuration.recursive,
            outputDir: configuration.outputDir,
            logLevel: configuration.logLevel,
            logFormat: configuration.logFormat,
            dryRun: configuration.dryRun,
            sourceRoot: configuration.sourceRoot,
            sourceVerification: configuration.sourceVerification,
            writeFlatKeywords: configuration.writeFlatKeywords,
            writeHierarchicalKeywords: configuration.writeHierarchicalKeywords,
            backupSidecars: configuration.backupSidecars,
            xmpConflictPolicy: configuration.xmpConflictPolicy,
            minConfidence: configuration.minConfidence,
            allowSpecificTags: configuration.allowSpecificTags,
            pairScope: configuration.pairScope,
            writeAIJSON: configuration.writeAIJSON
        )
        let batch = try RawJSONSidecarInputResolver(fileManager: fileManager).resolve(
            fromJSONPath: path,
            configuration: exportConfiguration
        )
        let inputURL = absoluteURL(for: path, fileManager: fileManager)
        let inputBasePath = basePath(forInput: inputURL)
        let records = buildAssets(from: batch.inputs)
        let grouped = buildGroups(for: records.assets, pairScope: configuration.pairScope)
        let failures = batch.failures.map {
            NormalizationInputFailure(
                path: $0.sidecarPath.standardizedFileURL.path,
                relativePath: $0.relativePath,
                error: $0.error
            )
        }

        return NormalizationResolvedInputBatch(
            workflow: .fromJSON,
            inputPath: inputURL.path,
            inputBasePath: inputBasePath,
            scanRoot: inputBasePath,
            rawSidecarInputs: batch.inputs,
            sourceAssets: grouped.assets,
            sourceAISidecars: records.sidecars,
            sameBaseNameGroups: grouped.groups,
            warnings: records.warnings,
            failures: failures
        )
    }

    private func resolveFileList(
        _ path: String,
        configuration: ResolvedNormalizationConfiguration
    ) throws -> NormalizationResolvedInputBatch {
        let listURL = absoluteURL(for: path, fileManager: fileManager)
        let baseURL = listURL.deletingLastPathComponent()
        let text = try readUTF8FileList(at: listURL)
        let parsed = parseFileList(text, listURL: listURL, baseURL: baseURL)
        let records = buildFileListAssets(parsed.entries, baseURL: baseURL)
        let grouped = buildGroups(for: records.assets, pairScope: configuration.pairScope)

        return NormalizationResolvedInputBatch(
            workflow: .fileList,
            inputPath: listURL.path,
            inputBasePath: baseURL.path,
            scanRoot: baseURL.path,
            sourceAssets: grouped.assets,
            sourceAISidecars: [],
            sameBaseNameGroups: grouped.groups,
            warnings: parsed.warnings,
            failures: records.failures
        )
    }

    private func resolveAnalyzeInput(
        _ inputPath: String,
        configuration: ResolvedNormalizationConfiguration
    ) throws -> NormalizationResolvedInputBatch {
        let scan = try ImageScanner(fileManager: fileManager).scan(
            inputPath: inputPath,
            recursive: configuration.recursive,
            identityPolicy: .sha256
        )
        let assets = scan.images.enumerated().map { index, source in
            sourceAsset(
                source: source,
                assetID: assetID(for: index),
                sourcePath: source.path,
                sourceSidecarPath: nil,
                sourceSidecarRelativePath: nil,
                sourceIdentityStatus: nil,
                fileListIndex: nil
            )
        }
        let grouped = buildGroups(for: assets, pairScope: configuration.pairScope)
        let failures = scan.errors.map {
            NormalizationInputFailure(path: $0.path, relativePath: $0.relativePath, error: $0.error)
        }

        return NormalizationResolvedInputBatch(
            workflow: .analyze,
            inputPath: URL(fileURLWithPath: scan.inputPath).standardizedFileURL.path,
            inputBasePath: scan.scanRoot,
            scanRoot: scan.scanRoot,
            sourceAssets: grouped.assets,
            sourceAISidecars: [],
            sameBaseNameGroups: grouped.groups,
            warnings: [],
            failures: failures
        )
    }

    private func buildAssets(
        from inputs: [ResolvedRawSidecarInput]
    ) -> (assets: [NormalizationSourceAsset], sidecars: [NormalizationSourceAISidecarRecord], warnings: [SidecarError])
    {
        var assets: [NormalizationSourceAsset] = []
        var sidecars: [NormalizationSourceAISidecarRecord] = []
        var warnings: [SidecarError] = []

        for (index, input) in inputs.enumerated() {
            let assetID = assetID(for: index)
            let source = input.document.sidecar.source
            let asset = sourceAsset(
                source: source,
                assetID: assetID,
                sourcePath: input.sourcePath?.standardizedFileURL.path ?? source.path,
                sourceSidecarPath: input.sidecarPath.standardizedFileURL.path,
                sourceSidecarRelativePath: input.relativePath,
                sourceIdentityStatus: input.sourceIdentityStatus,
                fileListIndex: nil
            )
            assets.append(asset)
            sidecars.append(
                NormalizationSourceAISidecarRecord(
                    sidecarPath: input.sidecarPath.standardizedFileURL.path,
                    relativePath: input.relativePath,
                    sourceAssetID: assetID,
                    schemaVersion: input.document.sidecar.schemaVersion,
                    sourceIdentityStatus: input.sourceIdentityStatus,
                    warnings: input.warnings
                )
            )
            warnings.append(contentsOf: input.warnings)
        }

        return (assets, sidecars, warnings)
    }

    private func buildFileListAssets(
        _ entries: [FileListResolvedEntry],
        baseURL: URL
    ) -> (assets: [NormalizationSourceAsset], failures: [NormalizationInputFailure]) {
        var assets: [NormalizationSourceAsset] = []
        var failures: [NormalizationInputFailure] = []

        for entry in entries {
            let url = entry.url.standardizedFileURL
            guard isRegularFile(url) else {
                failures.append(
                    inputFailure(
                        url,
                        relativePath: entry.relativePath,
                        code: .sourceMissing,
                        message: "File-list source does not exist: \(url.path)"
                    )
                )
                continue
            }
            guard let type = SupportedImageType(fileExtension: url.pathExtension) else {
                failures.append(
                    inputFailure(
                        url,
                        relativePath: entry.relativePath,
                        code: .unsupportedFormat,
                        message: "Unsupported image format in file list: \(entry.relativePath)"
                    )
                )
                continue
            }
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let identity = try SourceIdentityCalculator.compute(for: url, policy: .sha256, fileManager: fileManager)
                let source = SourceImage(
                    path: url.path,
                    relativePath: relativePath(for: url, root: baseURL),
                    fileName: url.lastPathComponent,
                    fileExtension: url.pathExtension,
                    fileSize: fileSize(from: attributes),
                    modifiedAt: modificationDate(from: attributes),
                    detectedType: type,
                    identity: identity
                )
                let assetID = assetID(for: assets.count)
                assets.append(
                    sourceAsset(
                        source: source,
                        assetID: assetID,
                        sourcePath: url.path,
                        sourceSidecarPath: nil,
                        sourceSidecarRelativePath: nil,
                        sourceIdentityStatus: nil,
                        fileListIndex: entry.index
                    )
                )
            } catch {
                failures.append(
                    inputFailure(
                        url,
                        relativePath: entry.relativePath,
                        code: .validationFailed,
                        message: "Unable to read file-list source \(url.path): \(error.localizedDescription)"
                    )
                )
            }
        }

        return (assets, failures)
    }

    private func sourceAsset(
        source: SourceImage,
        assetID: String,
        sourcePath: String?,
        sourceSidecarPath: String?,
        sourceSidecarRelativePath: String?,
        sourceIdentityStatus: SourceIdentityStatus?,
        fileListIndex: Int?
    ) -> NormalizationSourceAsset {
        NormalizationSourceAsset(
            assetID: assetID,
            sourcePath: sourcePath,
            sourceRelativePath: source.relativePath,
            fileName: source.fileName,
            sourceType: source.detectedType,
            sourceIdentity: source.identity,
            sourceSidecarPath: sourceSidecarPath,
            sourceSidecarRelativePath: sourceSidecarRelativePath,
            sourceIdentityStatus: sourceIdentityStatus,
            fileListIndex: fileListIndex,
            affinityInputs: AssetAffinityInputExtractor().make(
                assetID: assetID,
                source: source,
                fileListIndex: fileListIndex
            )
        )
    }

    private func buildGroups(
        for inputAssets: [NormalizationSourceAsset],
        pairScope: XMPPairScope
    ) -> (assets: [NormalizationSourceAsset], groups: [NormalizationSourceGroup]) {
        let sortedAssets = inputAssets.sorted {
            comparePaths($0.sourceRelativePath, $1.sourceRelativePath)
        }
        let grouped = Dictionary(grouping: sortedAssets) { groupKey(for: $0) }
        // Display paths come from each group's first member in sorted order, so a
        // group merged across symlinked spellings of one physical directory keeps
        // a deterministic directory and target path.
        let displayDirectories = grouped.mapValues { members in
            displayDirectory(for: members[0])
        }
        let keys = grouped.keys.sorted { lhs, rhs in
            let lhsDirectory = displayDirectories[lhs] ?? ""
            let rhsDirectory = displayDirectories[rhs] ?? ""
            if lhsDirectory == rhsDirectory {
                if lhs.basename == rhs.basename {
                    return lhs.identityDirectory < rhs.identityDirectory
                }
                return lhs.basename < rhs.basename
            }
            return lhsDirectory < rhsDirectory
        }
        let baseTargetPaths = Dictionary(
            uniqueKeysWithValues: keys.map { key in
                (key, targetRelativePath(directory: displayDirectories[key] ?? "", basename: key.basename))
            })
        let targetPathCounts = Dictionary(grouping: baseTargetPaths.values, by: { $0 }).mapValues(\.count)

        var groupIDByAsset: [String: String] = [:]
        let groups = keys.enumerated().map { index, key in
            let members = grouped[key] ?? []
            let groupID = groupID(for: index)
            for member in members {
                groupIDByAsset[member.assetID] = groupID
            }
            let selected = members.filter { isSelected($0, pairScope: pairScope) }
            let selectedIDs = selected.map(\.assetID)
            let skippedIDs = members.map(\.assetID).filter { !selectedIDs.contains($0) }
            let groupDirectory = displayDirectories[key] ?? ""
            let baseTargetPath =
                baseTargetPaths[key]
                ?? targetRelativePath(
                    directory: groupDirectory,
                    basename: key.basename
                )
            let targetRelativePath =
                targetPathCounts[baseTargetPath, default: 0] > 1
                ? disambiguatedTargetRelativePath(for: key, directory: groupDirectory)
                : baseTargetPath
            return NormalizationSourceGroup(
                groupID: groupID,
                groupDirectory: groupDirectory,
                groupBasename: key.basename,
                targetRelativePath: targetRelativePath,
                memberAssetIDs: members.map(\.assetID),
                selectedAssetIDs: selectedIDs,
                skippedAssetIDs: skippedIDs
            )
        }

        let assets = sortedAssets.map { asset in
            var updated = asset
            updated.affinityInputs.sameBaseNameGroupID = groupIDByAsset[asset.assetID]
            return updated
        }
        return (assets, groups)
    }

    private func groupKey(for asset: NormalizationSourceAsset) -> NormalizationGroupBuildKey {
        let components = asset.sourceRelativePath.split(separator: "/").map(String.init)
        let fileName = components.last ?? asset.fileName
        // Resolve symlinks so identity is physical: a linked and a real path to
        // the same directory must share one group (and one XMP target), never two.
        let identityDirectory =
            asset.sourcePath.map {
                URL(fileURLWithPath: $0)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .deletingLastPathComponent()
                    .path
            } ?? displayDirectory(for: asset)
        let basename = (fileName as NSString).deletingPathExtension
        return NormalizationGroupBuildKey(
            identityDirectory: identityDirectory,
            basename: basename
        )
    }

    private func displayDirectory(for asset: NormalizationSourceAsset) -> String {
        let components = asset.sourceRelativePath.split(separator: "/").map(String.init)
        return Array(components.dropLast()).joined(separator: "/")
    }

    private func isSelected(_ asset: NormalizationSourceAsset, pairScope: XMPPairScope) -> Bool {
        switch pairScope {
        case .union:
            return true
        case .rawOnly:
            return XMPSourcePairKind(sourceType: asset.sourceType) == .rawLike
        case .jpegOnly:
            return XMPSourcePairKind(sourceType: asset.sourceType) == .jpeg
        }
    }

    private func targetRelativePath(directory: String, basename: String) -> String {
        let fileName = "\(basename).xmp"
        return directory.isEmpty ? fileName : "\(directory)/\(fileName)"
    }

    private func disambiguatedTargetRelativePath(
        for key: NormalizationGroupBuildKey,
        directory: String
    ) -> String {
        let identitySuffix = AssetAffinityInputBuilder.stableSessionHash(key.identityDirectory).prefix(12)
        let fileName = "\(key.basename)-\(identitySuffix).xmp"
        return directory.isEmpty ? fileName : "\(directory)/\(fileName)"
    }

    private func readUTF8FileList(at url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw validationError("File list must be UTF-8 text: \(url.path)")
            }
            return text
        } catch let error as SidecarError {
            throw error
        } catch {
            throw validationError("Unable to read file list \(url.path): \(error.localizedDescription)")
        }
    }

    private func parseFileList(
        _ text: String,
        listURL: URL,
        baseURL: URL
    ) -> (entries: [FileListResolvedEntry], warnings: [SidecarError]) {
        var entries: [FileListResolvedEntry] = []
        var seen: Set<String> = []
        var warnings: [SidecarError] = []

        for (lineOffset, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            let url = absoluteURL(for: trimmed, fileManager: fileManager, relativeTo: baseURL)
            // Dedupe on the physical path: symlinked and real spellings of one
            // file are one entry, not two assets writing the same sidecar.
            let key = url.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else {
                warnings.append(
                    SidecarError(
                        code: .validationFailed,
                        stage: .scan,
                        message:
                            "Duplicate file-list entry ignored at \(listURL.lastPathComponent):\(lineOffset + 1): \(trimmed)",
                        recoverable: true
                    )
                )
                continue
            }
            entries.append(
                FileListResolvedEntry(
                    index: entries.count,
                    url: url,
                    relativePath: relativePath(for: url, root: baseURL)
                )
            )
        }

        return (entries, warnings)
    }

    private func inputFailure(
        _ url: URL,
        relativePath: String?,
        code: SidecarErrorCode,
        message: String
    ) -> NormalizationInputFailure {
        NormalizationInputFailure(
            path: url.standardizedFileURL.path,
            relativePath: relativePath,
            error: SidecarError(code: code, stage: .scan, message: message, recoverable: true)
        )
    }

    private func validationError(_ message: String) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .scan, message: message, recoverable: false)
    }

    private func basePath(forInput url: URL) -> String {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.standardizedFileURL.path
        }
        return url.deletingLastPathComponent().standardizedFileURL.path
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        var rootPath = root.standardizedFileURL.path
        if !rootPath.hasSuffix("/") {
            rootPath += "/"
        }
        guard path.hasPrefix(rootPath) else {
            return path
        }
        return String(path.dropFirst(rootPath.count))
    }

    private func fileSize(from attributes: [FileAttributeKey: Any]) -> Int64 {
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    private func modificationDate(from attributes: [FileAttributeKey: Any]) -> Date {
        attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
    }

    private func assetID(for index: Int) -> String {
        String(format: "asset-%06d", index + 1)
    }

    private func groupID(for index: Int) -> String {
        String(format: "group-%06d", index + 1)
    }
}

private struct FileListResolvedEntry: Sendable, Equatable {
    var index: Int
    var url: URL
    var relativePath: String
}

private struct NormalizationGroupBuildKey: Hashable, Sendable {
    var identityDirectory: String
    var basename: String
}
