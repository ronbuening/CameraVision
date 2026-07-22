import Foundation

func comparePaths(_ lhs: String, _ rhs: String) -> Bool {
    // Case-folded ordering stays stable on case-insensitive filesystems; the
    // literal comparison makes case-only ties deterministic.
    let lowerLHS = lhs.lowercased()
    let lowerRHS = rhs.lowercased()
    if lowerLHS == lowerRHS {
        return lhs < rhs
    }
    return lowerLHS < lowerRHS
}

func absoluteURL(
    for path: String,
    fileManager: FileManager,
    relativeTo baseURL: URL? = nil,
    isDirectory: Bool? = nil
) -> URL {
    let expandedPath = (path as NSString).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
        if let isDirectory {
            return URL(fileURLWithPath: expandedPath, isDirectory: isDirectory).standardizedFileURL
        }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }
    let baseURL = baseURL ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    if let isDirectory {
        return baseURL.appendingPathComponent(expandedPath, isDirectory: isDirectory).standardizedFileURL
    }
    return baseURL.appendingPathComponent(expandedPath).standardizedFileURL
}

// Both predicates classify the symlink target, matching
// `FileManager.fileExists(atPath:isDirectory:)`, so symlinked sources and
// folder inputs behave like their targets; dangling links are neither. The
// scanner's per-entry symlink policy is enforced upstream of these predicates.
func isRegularFile(_ url: URL) -> Bool {
    (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
}

func isDirectory(_ url: URL) -> Bool {
    (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
}
