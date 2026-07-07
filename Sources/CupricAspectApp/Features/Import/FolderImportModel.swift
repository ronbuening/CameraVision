import AISidecarCore
import Foundation
import Observation

/// Shell-agnostic import state (plan Section 4: features live outside the
/// shells). Holds the M1 in-memory queue; scanning and state derivation run
/// off the main actor, per the lazy-identity policy no hashing happens here.
@MainActor
@Observable
final class FolderImportModel {
    var sourceFolder: URL?
    var outputFolder: URL?
    var recursive = true

    private(set) var scanning = false
    private(set) var assets: [AssetRecord] = []
    private(set) var scanErrors: [ScanIssue] = []
    var errorCodeFilter: String?

    struct ScanIssue: Identifiable, Equatable, Sendable {
        var path: String
        var code: String
        var message: String
        var id: String { path }
    }

    var filteredAssets: [AssetRecord] {
        guard let errorCodeFilter else { return assets }
        return assets.filter { $0.failureCode == errorCodeFilter }
    }

    var presentErrorCodes: [String] {
        Array(Set(scanErrors.map(\.code))).sorted()
    }

    var summary: String {
        scanning ? "Scanning…" : "\(assets.count) images detected"
    }

    func chooseSource(_ url: URL) {
        sourceFolder = url
        Task { await rescan() }
    }

    func chooseOutput(_ url: URL?) {
        outputFolder = url
        Task { await rescan() }
    }

    func toggleRecursive() {
        recursive.toggle()
        Task { await rescan() }
    }

    /// Advance one asset's transient in-run state from a pipeline progress
    /// record (M2). Between launches the same information is re-derived from
    /// disk, so this is display state only — never persisted.
    func apply(_ record: ProgressRecord) {
        guard let path = record.sourcePath,
              let index = assets.firstIndex(where: { $0.path == path }) else {
            return
        }
        switch record.status {
        case .written, .skippedExisting:
            assets[index].stateKind = .analyzed
            assets[index].failureCode = nil
            assets[index].failureMessage = nil
        case .failed:
            assets[index].stateKind = .failed
            assets[index].failureCode = record.errors.first?.code.rawValue
            assets[index].failureMessage = record.errors.first?.message
        case .dryRun:
            break
        }
    }

    /// Scan (or idempotently re-scan) the selected folder and derive queue
    /// states from disk. Replaces the queue keyed by path, so re-import of
    /// the same folder yields the same rows.
    func rescan() async {
        guard let sourceFolder else { return }
        scanning = true
        defer { scanning = false }

        let inputPath = sourceFolder.path
        let outputDir = outputFolder?.path
        let recursive = recursive

        let outcome: (records: [AssetRecord], issues: [ScanIssue])? = await Task.detached(priority: .userInitiated) {
            guard let inventory = try? ImageScanner().inventory(inputPath: inputPath, recursive: recursive) else {
                return nil
            }
            let records = inventory.entries.map { entry in
                AssetRecord(
                    path: entry.path,
                    relativePath: entry.relativePath,
                    fileName: entry.fileName,
                    fileExtension: entry.fileExtension,
                    fileSize: entry.fileSize,
                    stateKind: AssetQueueDerivation.deriveState(
                        sourcePath: entry.path,
                        relativePath: entry.relativePath,
                        outputDir: outputDir
                    ),
                    failureCode: nil,
                    failureMessage: nil
                )
            }
            let issues = inventory.errors.map { record in
                ScanIssue(
                    path: record.path,
                    code: record.error.code.rawValue,
                    message: record.error.message
                )
            }
            return (records, issues)
        }.value

        guard let outcome else {
            assets = []
            scanErrors = [ScanIssue(
                path: inputPath,
                code: "validation_failed",
                message: "Unable to scan the selected folder."
            )]
            return
        }
        assets = outcome.records
        scanErrors = outcome.issues
    }
}
