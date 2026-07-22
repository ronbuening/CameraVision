import Foundation

struct SourceHashVerifier {
    struct Outcome: Equatable {
        var checks: [XMPSourceHashCheck]
        var errors: [SidecarError]
    }

    private let fileManager: FileManager
    private let baseline: [String: String?]

    init(plan: XMPChangePlan, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        var hashes: [String: String?] = [:]
        for path in Self.selectedSourcePaths(for: plan) {
            let hash = try? SourceIdentityCalculator.compute(
                for: URL(fileURLWithPath: path),
                policy: .sha256,
                fileManager: fileManager
            ).sha256
            hashes.updateValue(hash, forKey: path)
        }
        self.baseline = hashes
    }

    func verify() -> Outcome {
        var checks: [XMPSourceHashCheck] = []
        var errors: [SidecarError] = []
        for path in baseline.keys.sorted(by: comparePaths) {
            guard let beforeHash = baseline[path] ?? nil else {
                let sidecarError = SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message: "Unable to read source image before XMP export: \(path)",
                    recoverable: true
                )
                errors.append(sidecarError)
                checks.append(
                    XMPSourceHashCheck(
                        sourcePath: path,
                        beforeSHA256: nil,
                        afterSHA256: nil,
                        unchanged: false,
                        error: sidecarError
                    )
                )
                continue
            }
            do {
                let afterHash = try SourceIdentityCalculator.compute(
                    for: URL(fileURLWithPath: path),
                    policy: .sha256,
                    fileManager: fileManager
                ).sha256
                let unchanged = beforeHash == afterHash
                if !unchanged {
                    errors.append(sourceHashChangedError(path: path))
                }
                checks.append(
                    XMPSourceHashCheck(
                        sourcePath: path,
                        beforeSHA256: beforeHash,
                        afterSHA256: afterHash,
                        unchanged: unchanged
                    )
                )
            } catch {
                let sidecarError = SidecarError(
                    code: .validationFailed,
                    stage: .write,
                    message:
                        "Unable to verify source image hash after XMP export for \(path): \(error.localizedDescription)",
                    recoverable: true
                )
                errors.append(sidecarError)
                checks.append(
                    XMPSourceHashCheck(
                        sourcePath: path,
                        beforeSHA256: beforeHash,
                        afterSHA256: nil,
                        unchanged: false,
                        error: sidecarError
                    )
                )
            }
        }
        return Outcome(checks: checks, errors: errors)
    }

    static func selectedSourcePaths(for plan: XMPChangePlan) -> [String] {
        Array(Set(plan.sourceMembers.filter(\.selected).compactMap(\.sourcePath))).sorted(by: comparePaths)
    }

    private func sourceHashChangedError(path: String) -> SidecarError {
        SidecarError(
            code: .validationFailed,
            stage: .write,
            message: "Source image hash changed during XMP export: \(path)",
            recoverable: true
        )
    }
}
