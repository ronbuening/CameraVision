import Foundation
import XCTest

func assertNoXMPFiles(
    in roots: [URL],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    for root in roots where FileManager.default.fileExists(atPath: root.path) {
        if root.pathExtension.lowercased() == "xmp" {
            XCTFail("Unexpected XMP file at \(root.path)", file: file, line: line)
            continue
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            continue
        }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "xmp" {
            XCTFail("Unexpected XMP file at \(url.path)", file: file, line: line)
        }
    }
}
