import Foundation

/// M8 hygiene: the review/normalize/export flows write per-run artifact
/// directories (session, report, progress files) under the app state
/// directory. They are working scratch, not user data — prune the stale ones
/// on launch so the state directory cannot grow without bound.
///
/// Never touches the recovery file, user folders, or anything outside the
/// listed subdirectories.
enum StateHousekeeping {
    static let artifactSubdirectories = [
        "review-artifacts",
        "normalize-artifacts",
        "export-sessions",
    ]

    static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Remove artifact entries older than `maxAge`. Returns how many were
    /// removed (for logging/tests).
    @discardableResult
    static func pruneArtifacts(
        in stateDirectory: URL,
        olderThan maxAge: TimeInterval = defaultMaxAge,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Int {
        var removed = 0
        for name in artifactSubdirectories {
            let directory = stateDirectory.appendingPathComponent(name, isDirectory: true)
            guard
                let entries = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
            else {
                continue
            }
            for entry in entries {
                let modified =
                    (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? now
                if now.timeIntervalSince(modified) > maxAge {
                    if (try? fileManager.removeItem(at: entry)) != nil {
                        removed += 1
                    }
                }
            }
        }
        return removed
    }
}
