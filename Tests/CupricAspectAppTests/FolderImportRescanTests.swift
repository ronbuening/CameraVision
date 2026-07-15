import AISidecarCore
import Foundation
import XCTest

@testable import CupricAspectApp

final class FolderImportRescanTests: XCTestCase {
    private final class ScanGate: @unchecked Sendable {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
    }

    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folder-import-rescan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "folder-import-rescan-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testStaleScanResultIsDropped() async throws {
        let slowFolder = try makeFolder("slow", files: ["A.JPG", "B.JPG"])
        let fastFolder = try makeFolder("fast", files: ["C.JPG"])
        let slowInventory = inventory(for: slowFolder, files: ["A.JPG", "B.JPG"])
        let fastInventory = inventory(for: fastFolder, files: ["C.JPG"])
        let gate = ScanGate()
        let model = FolderImportModel(defaults: defaults)
        let slowPath = slowFolder.path
        let fastPath = fastFolder.path
        model.inventoryProvider = { path, _ in
            if path == slowPath {
                gate.started.signal()
                _ = gate.release.wait(timeout: .now() + 2)
                return slowInventory
            }
            if path == fastPath {
                return fastInventory
            }
            return ScanInventory(inputPath: path, scanRoot: path, recursive: false, entries: [], errors: [])
        }

        model.sourceFolder = slowFolder
        let firstScan = Task { await model.rescan() }
        let startResult = await Self.wait(for: gate.started, timeout: 2)
        XCTAssertEqual(startResult, .success)

        model.sourceFolder = fastFolder
        await model.rescan()
        XCTAssertEqual(model.assets.map(\.fileName), ["C.JPG"])
        XCTAssertFalse(model.scanning)

        gate.release.signal()
        await firstScan.value

        XCTAssertEqual(
            model.assets.map(\.fileName), ["C.JPG"], "stale slow-scan results must not overwrite the newer scan")
        XCTAssertFalse(model.scanning)
    }

    @MainActor
    func testScanFailureSurfacesScannerErrorMessage() async {
        let model = FolderImportModel(defaults: defaults)
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        model.sourceFolder = missing
        await model.rescan()

        XCTAssertEqual(model.assets, [])
        let issue = model.scanErrors.first
        XCTAssertEqual(issue?.code, SidecarErrorCode.validationFailed.rawValue)
        XCTAssertTrue(issue?.message.contains("Input path does not exist") == true)
        XCTAssertNotEqual(issue?.message, "Unable to scan the selected folder.")
        XCTAssertFalse(model.scanning)
    }

    private func makeFolder(_ name: String, files: [String]) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try Data([0]).write(to: folder.appendingPathComponent(file))
        }
        return folder
    }

    private func inventory(for folder: URL, files: [String]) -> ScanInventory {
        ScanInventory(
            inputPath: folder.path,
            scanRoot: folder.path,
            recursive: false,
            entries: files.map { file in
                let url = folder.appendingPathComponent(file)
                return ScanInventoryEntry(
                    path: url.path,
                    relativePath: file,
                    fileName: file,
                    fileExtension: url.pathExtension.lowercased(),
                    fileSize: 1,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    detectedType: .jpg
                )
            },
            errors: []
        )
    }

    private static func wait(for semaphore: DispatchSemaphore, timeout: TimeInterval) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + timeout))
            }
        }
    }
}
