import XCTest
@testable import AISidecarCore

final class ErrorTaxonomyTests: XCTestCase {
    func testFrozenErrorCodeSetEncodesStableStrings() throws {
        let expectedRawValues = [
            "E_UNSUPPORTED_FORMAT",
            "E_DECODE_FAILED",
            "E_RENDER_FAILED",
            "E_ORIENTATION_UNRESOLVED",
            "E_SUBJECT_ISOLATION_NO_FOREGROUND",
            "E_SUBJECT_ISOLATION_FAILED",
            "E_MODEL_ENDPOINT_UNREACHABLE",
            "E_MODEL_TAG_NOT_FOUND",
            "E_MODEL_TIMEOUT",
            "E_MODEL_INVALID_JSON",
            "E_MODEL_SCHEMA_VIOLATION",
            "E_SIDECAR_EXISTS",
            "E_SIDECAR_COLLISION",
            "E_WRITE_FAILED",
            "E_VALIDATION_FAILED",
            "E_SCHEMA_UNSUPPORTED",
            "E_VOCABULARY_INVALID",
            "E_SESSION_STALE",
            "E_CONFIG_INVALID",
            "E_EXIFTOOL_MISSING",
            "E_INTERRUPTED"
        ]

        XCTAssertEqual(SidecarErrorCode.allCases.map(\.rawValue), expectedRawValues)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for code in SidecarErrorCode.allCases {
            let data = try encoder.encode(code)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"\(code.rawValue)\"")
            XCTAssertEqual(try decoder.decode(SidecarErrorCode.self, from: data), code)
        }
    }

    func testSidecarErrorPreservesStructuredFields() throws {
        let error = SidecarError(
            code: .renderFailed,
            stage: .render,
            message: "Image failed to render.",
            recoverable: true
        )

        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(SidecarError.self, from: data)

        XCTAssertEqual(decoded, error)
        XCTAssertEqual(decoded.code, .renderFailed)
        XCTAssertEqual(decoded.stage, .render)
        XCTAssertEqual(decoded.message, "Image failed to render.")
        XCTAssertTrue(decoded.recoverable)
    }
}
