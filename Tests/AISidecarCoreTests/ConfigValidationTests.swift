import XCTest
@testable import AISidecarCore

final class ConfigValidationTests: XCTestCase {
    func testInvalidEnumFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "mode": "invalid" }"#)
            )
        }
    }

    func testInvalidURLFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "model_endpoint": "not-a-url" }"#)
            )
        }
    }

    func testMalformedJSONFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "mode": "whole" "#)
            )
        }
    }

    func testMissingExplicitConfigFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                cli: RunConfigurationOverrides(configPath: missingConfigPath()),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testYAMLConfigPathFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                cli: RunConfigurationOverrides(configPath: "\(NSTemporaryDirectory())config.yaml"),
                environment: [:],
                defaultConfigPath: missingConfigPath()
            )
        }
    }

    func testUnknownConfigKeyFailsAsConfigInvalid() throws {
        try assertConfigInvalid {
            _ = try ConfigurationResolver.resolve(
                environment: [:],
                defaultConfigPath: writeConfig(#"{ "surprise": true }"#)
            )
        }
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

    private func missingConfigPath() -> String {
        "\(NSTemporaryDirectory())aisidecar-tests/\(UUID().uuidString)/missing-config.json"
    }

    private func writeConfig(_ contents: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisidecar-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        try contents.data(using: .utf8)!.write(to: file)
        return file.path
    }
}
