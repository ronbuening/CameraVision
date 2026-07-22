import XCTest

@testable import AISidecarCore

/// CORE-5: the discovery-only inventory must agree with the identity-computing
/// scan about what a folder contains, while computing no identities.
final class ImageScannerInventoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inventory-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try write("a.NEF", bytes: 1200)
        try write("b.jpg", bytes: 800)
        try write("notes.txt", bytes: 10)
        try write(".hidden.nef", bytes: 5)
        try write("b.jpg.ai.json", bytes: 5)
        try write("b.xmp", bytes: 5)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sub"), withIntermediateDirectories: true
        )
        try write("sub/e.arw", bytes: 300)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try Data(repeating: 0xA5, count: bytes).write(to: url)
    }

    func testInventoryDiscoversSupportedImagesAndRecordsUnsupported() throws {
        let inventory = try ImageScanner().inventory(inputPath: root.path, recursive: true)

        XCTAssertEqual(inventory.entries.map(\.relativePath), ["a.NEF", "b.jpg", "sub/e.arw"])
        XCTAssertEqual(inventory.entries.map(\.detectedType), [.nef, .jpg, .arw])
        XCTAssertEqual(inventory.errors.count, 1)
        XCTAssertEqual(inventory.errors.first?.relativePath, "notes.txt")
        XCTAssertEqual(inventory.errors.first?.error.code, .unsupportedFormat)

        let nef = try XCTUnwrap(inventory.entries.first)
        XCTAssertEqual(nef.fileSize, 1200)
        XCTAssertEqual(nef.fileName, "a.NEF")
        XCTAssertEqual(nef.fileExtension, "NEF")
    }

    func testNonRecursiveInventoryExcludesSubfolders() throws {
        let inventory = try ImageScanner().inventory(inputPath: root.path, recursive: false)
        XCTAssertEqual(inventory.entries.map(\.relativePath), ["a.NEF", "b.jpg"])
    }

    func testInventoryMatchesScanDiscovery() throws {
        let scanner = ImageScanner()
        let inventory = try scanner.inventory(inputPath: root.path, recursive: true)
        let scan = try scanner.scan(inputPath: root.path, recursive: true, identityPolicy: .fast)

        XCTAssertEqual(inventory.entries.map(\.path), scan.images.map(\.path))
        XCTAssertEqual(inventory.entries.map(\.fileSize), scan.images.map(\.fileSize))
        XCTAssertEqual(inventory.errors, scan.errors)
        XCTAssertEqual(inventory.scanRoot, scan.scanRoot)
    }

    func testInventoryNeverComputesSourceIdentities() throws {
        let probe = InventoryIdentityProbe()
        let scanner = ImageScanner(
            identityCalculator: { _, policy, _ in
                probe.recordInvocation()
                return SourceIdentity(policy: policy, sha256: String(repeating: "a", count: 64))
            }
        )

        let inventory = try scanner.inventory(inputPath: root.path, recursive: true)

        XCTAssertEqual(inventory.entries.count, 3)
        XCTAssertEqual(probe.invocationCount, 0)
    }

    func testSingleFileInputInventory() throws {
        let inventory = try ImageScanner().inventory(
            inputPath: root.appendingPathComponent("a.NEF").path, recursive: false
        )
        XCTAssertEqual(inventory.entries.map(\.fileName), ["a.NEF"])
        XCTAssertEqual(inventory.scanRoot, root.standardizedFileURL.path)
    }
}

private final class InventoryIdentityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvocationCount = 0

    var invocationCount: Int {
        lock.withLock { storedInvocationCount }
    }

    func recordInvocation() {
        lock.withLock {
            storedInvocationCount += 1
        }
    }
}
