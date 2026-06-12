import XCTest
@testable import AISidecarCore

final class XMPExportInvocationTests: XCTestCase {
    func testRequiresExactlyOneInputMode() throws {
        try assertConfigInvalid {
            _ = try XMPExportInvocationValidator.validate(XMPExportInvocationRequest())
        }

        try assertConfigInvalid {
            _ = try XMPExportInvocationValidator.validate(
                XMPExportInvocationRequest(inputPath: "Image.JPG", fromJSONPath: "Image.JPG.ai.json")
            )
        }
    }

    func testAcceptsFromJSONAndAnalyzeAndWriteModes() throws {
        let fromJSON = try XMPExportInvocationValidator.validate(
            XMPExportInvocationRequest(fromJSONPath: "Image.JPG.ai.json", sourceRoot: "/tmp/images")
        )
        XCTAssertEqual(fromJSON, .fromJSON(path: "Image.JPG.ai.json"))

        let analyze = try XMPExportInvocationValidator.validate(
            XMPExportInvocationRequest(inputPath: "Image.JPG", mode: .both)
        )
        XCTAssertEqual(analyze, .analyzeAndWrite(inputPath: "Image.JPG"))
    }

    func testRejectsFromJSONWithAnalyzeOnlyOptions() throws {
        let invalidRequests = [
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", mode: .both),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", existing: .overwrite),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", model: "custom:model"),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", modelEndpoint: "http://localhost:11434"),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", profile: "gemma4-26b-default"),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", debugDerivatives: true),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", clearDerivativeCacheOnStart: true),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", clearDerivativeCacheAfterSuccess: true),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", modelResponseRepairAttempts: 1),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", writeAIJSON: true),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", noWriteAIJSON: true)
        ]

        for request in invalidRequests {
            try assertConfigInvalid {
                _ = try XMPExportInvocationValidator.validate(request)
            }
        }
    }

    func testRejectsFromJSONOnlyOptionsWithAnalyzeAndWrite() throws {
        try assertConfigInvalid {
            _ = try XMPExportInvocationValidator.validate(
                XMPExportInvocationRequest(inputPath: "Image.JPG", sourceRoot: "/tmp/source")
            )
        }

        try assertConfigInvalid {
            _ = try XMPExportInvocationValidator.validate(
                XMPExportInvocationRequest(inputPath: "Image.JPG", sourceVerification: .warn)
            )
        }
    }

    func testRejectsConflictingBooleanPairs() throws {
        let invalidRequests = [
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", writeFlatKeywords: true, noWriteFlatKeywords: true),
            XMPExportInvocationRequest(
                fromJSONPath: "A.ai.json",
                writeHierarchicalKeywords: true,
                noWriteHierarchicalKeywords: true
            ),
            XMPExportInvocationRequest(fromJSONPath: "A.ai.json", backupSidecars: true, noBackupSidecars: true),
            XMPExportInvocationRequest(inputPath: "Image.JPG", writeAIJSON: true, noWriteAIJSON: true)
        ]

        for request in invalidRequests {
            try assertConfigInvalid {
                _ = try XMPExportInvocationValidator.validate(request)
            }
        }
    }

    func testSchemaIdentifierConstantsAreStable() {
        XCTAssertEqual(XMPExportSchemaIdentifiers.exportReport, "ai-sidecar-xmp-export/1.0")
        XCTAssertEqual(XMPExportSchemaIdentifiers.changePlan, "ai-sidecar-xmp-change-plan/1.0")
    }

    private func assertConfigInvalid(_ operation: () throws -> Void) throws {
        do {
            try operation()
            XCTFail("Expected E_CONFIG_INVALID")
        } catch let error as SidecarError {
            XCTAssertEqual(error.code, .configInvalid)
            XCTAssertEqual(error.stage, .configuration)
            XCTAssertFalse(error.recoverable)
        }
    }
}
