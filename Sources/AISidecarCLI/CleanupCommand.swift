import Foundation
import ArgumentParser
import AISidecarCore

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Remove AISidecar raw JSON sidecars and run log/report artifacts from a folder."
    )

    @Argument(help: "Folder containing AISidecar artifacts to clean.")
    var folder: String

    @Flag(help: "Recurse into subfolders.")
    var recursive = false

    @Flag(help: "Report matching artifacts without deleting them.")
    var dryRun = false

    mutating func run() throws {
        let report = try ArtifactCleanup().run(rootPath: folder, recursive: recursive, dryRun: dryRun)
        let message: String
        if dryRun {
            message = "Cleanup dry run at \(report.rootPath): \(report.plannedCount) artifacts would be removed.\n"
        } else {
            message = "Cleaned \(report.rootPath): \(report.removedCount) artifacts removed, \(report.failedCount) failed.\n"
        }
        FileHandle.standardOutput.write(Data(message.utf8))

        if report.failedCount > 0 {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Cleanup failed for \(report.failedCount) artifacts.",
                recoverable: true
            )
        }
    }
}
