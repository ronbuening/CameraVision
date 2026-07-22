import Foundation
import XCTest

@testable import AISidecarCore

final class PathUtilitiesTests: XCTestCase {
    func testComparePathsUsesCaseInsensitiveOrderWithLiteralTieBreak() {
        let paths = ["z/photo.jpg", "A/photo.jpg", "a/photo.jpg", "b/photo.jpg"]

        XCTAssertEqual(
            paths.sorted(by: comparePaths),
            ["A/photo.jpg", "a/photo.jpg", "b/photo.jpg", "z/photo.jpg"]
        )
    }

    func testAbsoluteURLExpandsAndStandardizesPaths() {
        let fileManager = FileManager.default
        let relative = absoluteURL(for: "fixtures/../photo.jpg", fileManager: fileManager)
        let absolute = absoluteURL(for: "/tmp/fixtures/../photo.jpg", fileManager: fileManager)
        let homeRelative = absoluteURL(for: "~/photo.jpg", fileManager: fileManager)
        let customRelative = absoluteURL(
            for: "fixtures/../photo.jpg",
            fileManager: fileManager,
            relativeTo: URL(fileURLWithPath: "/tmp/list", isDirectory: true)
        )
        let inferredDirectory = absoluteURL(for: "/tmp/photos/", fileManager: fileManager)
        let directory = absoluteURL(for: "/tmp/photos", fileManager: fileManager, isDirectory: true)

        XCTAssertEqual(
            relative.path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("photo.jpg")
                .standardizedFileURL.path
        )
        XCTAssertEqual(absolute.path, "/tmp/photo.jpg")
        XCTAssertEqual(
            homeRelative.path, URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("photo.jpg").path)
        XCTAssertEqual(customRelative.path, "/tmp/list/photo.jpg")
        XCTAssertEqual(
            inferredDirectory,
            URL(fileURLWithPath: ("/tmp/photos/" as NSString).expandingTildeInPath).standardizedFileURL
        )
        XCTAssertTrue(directory.hasDirectoryPath)
    }

    func testFileKindPredicatesDistinguishRegularFilesAndDirectories() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("path-utilities-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("photo.jpg")
        let fileLink = root.appendingPathComponent("photo-link.jpg")
        let directoryLink = root.appendingPathComponent("directory-link")
        let danglingLink = root.appendingPathComponent("dangling-link.jpg")
        let missing = root.appendingPathComponent("missing.jpg")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try Data([0x01]).write(to: file)
        try fileManager.createSymbolicLink(at: fileLink, withDestinationURL: file)
        try fileManager.createSymbolicLink(at: directoryLink, withDestinationURL: root)
        try fileManager.createSymbolicLink(at: danglingLink, withDestinationURL: missing)

        XCTAssertTrue(isRegularFile(file))
        XCTAssertFalse(isRegularFile(root))
        XCTAssertTrue(isDirectory(root))
        XCTAssertFalse(isDirectory(file))
        XCTAssertTrue(isRegularFile(fileLink))
        XCTAssertFalse(isDirectory(fileLink))
        XCTAssertFalse(isRegularFile(directoryLink))
        XCTAssertTrue(isDirectory(directoryLink))
        XCTAssertFalse(isRegularFile(danglingLink))
        XCTAssertFalse(isDirectory(danglingLink))
        XCTAssertFalse(isRegularFile(missing))
        XCTAssertFalse(isDirectory(missing))
    }
}
