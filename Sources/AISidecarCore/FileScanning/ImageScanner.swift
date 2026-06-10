import Foundation

public struct ImageScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(
        inputPath: String,
        recursive: Bool,
        identityPolicy: SourceIdentityPolicy
    ) throws -> ScanResult {
        let inputURL = absoluteURL(for: inputPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw validationError("Input path does not exist: \(inputURL.path)")
        }

        if isDirectory.boolValue {
            return try scanDirectory(inputURL, recursive: recursive, identityPolicy: identityPolicy)
        }

        return try scanFileInput(inputURL, recursive: recursive, identityPolicy: identityPolicy)
    }

    private func scanDirectory(
        _ root: URL,
        recursive: Bool,
        identityPolicy: SourceIdentityPolicy
    ) throws -> ScanResult {
        let root = root.standardizedFileURL
        let candidates = try candidateFiles(in: root, recursive: recursive)
        let scanned = scanCandidates(candidates, root: root, identityPolicy: identityPolicy)
        return ScanResult(
            inputPath: root.path,
            scanRoot: root.path,
            recursive: recursive,
            identityPolicy: identityPolicy,
            images: scanned.images,
            errors: scanned.errors
        )
    }

    private func scanFileInput(
        _ fileURL: URL,
        recursive: Bool,
        identityPolicy: SourceIdentityPolicy
    ) throws -> ScanResult {
        let fileURL = fileURL.standardizedFileURL
        let root = fileURL.deletingLastPathComponent()
        guard !shouldIgnore(url: fileURL, root: root) else {
            return ScanResult(
                inputPath: fileURL.path,
                scanRoot: root.path,
                recursive: recursive,
                identityPolicy: identityPolicy,
                images: [],
                errors: []
            )
        }

        let scanned = scanCandidates([fileURL], root: root, identityPolicy: identityPolicy)
        return ScanResult(
            inputPath: fileURL.path,
            scanRoot: root.path,
            recursive: recursive,
            identityPolicy: identityPolicy,
            images: scanned.images,
            errors: scanned.errors
        )
    }

    private func candidateFiles(in root: URL, recursive: Bool) throws -> [URL] {
        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                throw validationError("Unable to enumerate input folder: \(root.path)")
            }

            var urls: [URL] = []
            for case let url as URL in enumerator {
                let url = url.standardizedFileURL
                if shouldIgnore(url: url, root: root) {
                    if isDirectory(url) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if isRegularFile(url) {
                    urls.append(url)
                }
            }
            return sorted(urls, root: root)
        }

        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        )
        return sorted(
            urls
                .map(\.standardizedFileURL)
                .filter { !shouldIgnore(url: $0, root: root) }
                .filter { isRegularFile($0) },
            root: root
        )
    }

    private func scanCandidates(
        _ candidates: [URL],
        root: URL,
        identityPolicy: SourceIdentityPolicy
    ) -> (images: [SourceImage], errors: [ScanErrorRecord]) {
        var images: [SourceImage] = []
        var errors: [ScanErrorRecord] = []

        for candidate in candidates {
            let relativePath = relativePath(for: candidate, root: root)
            guard let type = SupportedImageType(fileExtension: candidate.pathExtension) else {
                errors.append(
                    ScanErrorRecord(
                        path: candidate.path,
                        relativePath: relativePath,
                        error: SidecarError(
                            code: .unsupportedFormat,
                            stage: .scan,
                            message: "Unsupported image format: \(relativePath)",
                            recoverable: true
                        )
                    )
                )
                continue
            }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: candidate.path)
                let identity = try SourceIdentityCalculator.compute(
                    for: candidate,
                    policy: identityPolicy,
                    fileManager: fileManager
                )
                images.append(
                    SourceImage(
                        path: candidate.path,
                        relativePath: relativePath,
                        fileName: candidate.lastPathComponent,
                        fileExtension: candidate.pathExtension,
                        fileSize: fileSize(from: attributes),
                        modifiedAt: modificationDate(from: attributes),
                        detectedType: type,
                        identity: identity
                    )
                )
            } catch {
                errors.append(
                    ScanErrorRecord(
                        path: candidate.path,
                        relativePath: relativePath,
                        error: SidecarError(
                            code: .validationFailed,
                            stage: .scan,
                            message: "Unable to read source image metadata or identity for \(relativePath): \(error.localizedDescription)",
                            recoverable: true
                        )
                    )
                )
            }
        }

        return (
            images: images.sorted { comparePaths($0.relativePath, $1.relativePath) },
            errors: errors.sorted { comparePaths($0.relativePath ?? $0.path, $1.relativePath ?? $1.path) }
        )
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

    private func shouldIgnore(url: URL, root: URL) -> Bool {
        let relativePath = relativePath(for: url, root: root)
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            return true
        }

        if components.contains(where: { $0.hasPrefix(".") }) {
            return true
        }

        let lowercasedName = fileName.lowercased()
        return lowercasedName == ".ds_store"
            || lowercasedName.hasPrefix("._")
            || lowercasedName.hasSuffix(".ai.json")
            || lowercasedName.hasSuffix(".xmp")
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func sorted(_ urls: [URL], root: URL) -> [URL] {
        urls.sorted {
            comparePaths(relativePath(for: $0, root: root), relativePath(for: $1, root: root))
        }
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        var rootPath = root.standardizedFileURL.path
        if !rootPath.hasSuffix("/") {
            rootPath += "/"
        }
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
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

    private func validationError(_ message: String) -> SidecarError {
        SidecarError(code: .validationFailed, stage: .scan, message: message, recoverable: false)
    }
}

private func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}
