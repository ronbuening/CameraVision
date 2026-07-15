import AISidecarCore
import Foundation
import Observation

/// Shell-agnostic import state (plan Section 4: features live outside the
/// shells). Holds the M1 in-memory queue; scanning and state derivation run
/// off the main actor, per the lazy-identity policy no hashing happens here.
@MainActor
@Observable
final class FolderImportModel {
    enum DefaultsKeys {
        static let lastSource = "cupricaspect.lastSourceFolder"
        static let lastOutput = "cupricaspect.lastOutputFolder"
    }

    var sourceFolder: URL?
    var outputFolder: URL?
    var recursive = true

    /// B0-6 reopen-last-folder: the previous session's source folder, offered
    /// on launch (never auto-imported) while nothing is selected yet.
    private(set) var reopenCandidate: URL?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: DefaultsKeys.lastSource),
            FileManager.default.fileExists(atPath: path)
        {
            reopenCandidate = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    func reopenLastFolder() {
        guard let reopenCandidate else { return }
        if let outputPath = defaults.string(forKey: DefaultsKeys.lastOutput),
            FileManager.default.fileExists(atPath: outputPath)
        {
            outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
        }
        chooseSource(reopenCandidate)
    }

    func dismissReopenOffer() {
        reopenCandidate = nil
    }

    private(set) var scanning = false
    private(set) var assets: [AssetRecord] = []
    private(set) var scanErrors: [ScanIssue] = []
    var errorCodeFilter: String?
    var inventoryProvider: @Sendable (String, Bool) throws -> ScanInventory = {
        try ImageScanner().inventory(inputPath: $0, recursive: $1)
    }
    private var scanGeneration = 0

    struct ScanIssue: Identifiable, Equatable, Sendable {
        var path: String
        var code: String
        var message: String
        var id: String { path }
    }

    private struct RescanOutcome: Sendable {
        var records: [AssetRecord]
        var issues: [ScanIssue]
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
        reopenCandidate = nil
        defaults.set(url.path, forKey: DefaultsKeys.lastSource)
        Task { await rescan() }
    }

    func chooseOutput(_ url: URL?) {
        outputFolder = url
        if let url {
            defaults.set(url.path, forKey: DefaultsKeys.lastOutput)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.lastOutput)
        }
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
            let index = assets.firstIndex(where: { $0.path == path })
        else {
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
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
        defer {
            if generation == scanGeneration {
                scanning = false
            }
        }

        let inputPath = sourceFolder.path
        let outputDir = outputFolder?.path
        let recursive = recursive
        let inventoryProvider = inventoryProvider

        let outcome: RescanOutcome = await Task.detached(priority: .userInitiated) {
            do {
                let inventory = try inventoryProvider(inputPath, recursive)
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
                return RescanOutcome(records: records, issues: issues)
            } catch {
                return RescanOutcome(
                    records: [],
                    issues: [
                        Self.scanIssue(for: inputPath, error: error)
                    ])
            }
        }.value

        guard generation == scanGeneration else { return }
        assets = outcome.records
        scanErrors = outcome.issues
    }

    nonisolated private static func scanIssue(for path: String, error: Error) -> ScanIssue {
        if let sidecarError = error as? SidecarError {
            return ScanIssue(
                path: path,
                code: sidecarError.code.rawValue,
                message: sidecarError.message
            )
        }
        return ScanIssue(
            path: path,
            code: SidecarErrorCode.validationFailed.rawValue,
            message: error.localizedDescription
        )
    }
}
