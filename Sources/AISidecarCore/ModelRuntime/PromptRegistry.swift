import Foundation

/// Loads the versioned Phase 1 prompts submitted to vision model runs.
public enum PromptRegistry {
    /// Return the submitted prompt for the requested model-input role.
    public static func prompt(for role: ModelInputRole) throws -> VersionedPrompt {
        let text = try normalizedResourceText(named: resourceName(for: role))
        let version = try promptVersion(from: text, resourceName: resourceName(for: role))
        return VersionedPrompt(version: version, text: text)
    }

    private static func resourceName(for role: ModelInputRole) -> String {
        switch role {
        case .wholeImage:
            return "whole_image_v1.3.0"
        case .subjectIsolated:
            return "subject_isolated_v1.3.0"
        }
    }

    private static func normalizedResourceText(named resourceName: String) throws -> String {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "txt") else {
            throw resourceError("Missing bundled prompt resource: \(resourceName).txt")
        }
        let data = try Data(contentsOf: url)
        guard let rawText = String(data: data, encoding: .utf8) else {
            throw resourceError("Prompt resource is not UTF-8 text: \(resourceName).txt")
        }
        return normalizeFinalNewline(rawText)
    }

    private static func promptVersion(from text: String, resourceName: String) throws -> String {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            throw resourceError("Prompt resource is empty: \(resourceName).txt")
        }
        let prefix = "PROMPT_VERSION: "
        guard firstLine.hasPrefix(prefix) else {
            throw resourceError("Prompt resource is missing PROMPT_VERSION header: \(resourceName).txt")
        }
        let version = String(firstLine.dropFirst(prefix.count))
        guard !version.isEmpty else {
            throw resourceError("Prompt resource has an empty PROMPT_VERSION header: \(resourceName).txt")
        }
        return version
    }
}

private func normalizeFinalNewline(_ text: String) -> String {
    var normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    while normalized.last == "\n" {
        normalized.removeLast()
    }
    return normalized + "\n"
}

private func resourceError(_ message: String) -> SidecarError {
    SidecarError(code: .validationFailed, stage: .model, message: message, recoverable: false)
}
