import Foundation

/// Locates the SwiftPM resource bundle (prompts, response schemas, the
/// bundled vocabulary) in every deployment shape (packaging plan WI-2).
///
/// SwiftPM's generated `Bundle.module` accessor checks only the main bundle
/// root and the absolute build-machine path, so a relocated executable — the
/// GUI in `CupricAspect.app/Contents/MacOS`, the CLI in `Contents/Helpers` —
/// resolves resources only on the machine that built it. This locator adds
/// the two placements the app bundle actually uses, then falls back to
/// `Bundle.module` for dev builds and test runners:
///
/// 1. `Bundle.main.resourceURL` — `Contents/Resources` inside an app bundle.
/// 2. Beside the running executable — the CLI copied out to a bin dir.
/// 3. `../Resources` relative to the executable — the embedded CLI in
///    `Contents/Helpers` sharing the app's copy (the SwiftPM bundle is flat,
///    so codesign rejects a second copy under `Helpers/`).
/// 4. `Bundle.module` — `swift run`/`swift test`, where the generated
///    accessor's build-path fallback is correct.
enum AISidecarResourceBundle {
    static let bundleName = "CameraVision_AISidecarCore.bundle"

    static let current: Bundle = {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName))
        }
        if let executableURL = Bundle.main.executableURL {
            let executableDir = executableURL.deletingLastPathComponent()
            candidates.append(executableDir.appendingPathComponent(bundleName))
            candidates.append(
                executableDir.deletingLastPathComponent()
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(bundleName)
            )
        }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return Bundle.module
    }()
}
