import AISidecarCore
import Foundation

/// FR4-059 diagnostic file logging: a shared, size-bounded log file under the
/// app state directory that the pipeline `Logger` sinks into — replacing the
/// discarded `Logger(sink: { _ in })` so failed runs leave readable evidence
/// (AC4-035). One rotation generation is kept (`.previous`), so disk use is
/// bounded at ~2× the cap.
final class FileLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private let fileManager: FileManager
    private var sizeCapBytes: Int
    private var currentSize: Int

    let logURL: URL
    let previousLogURL: URL

    init(
        directory: URL,
        fileName: String = "cupricaspect.log",
        sizeCapBytes: Int = 5_000_000,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.sizeCapBytes = sizeCapBytes
        logURL = directory.appendingPathComponent(fileName)
        previousLogURL = directory.appendingPathComponent(fileName + ".previous")
        currentSize = (try? fileManager.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
    }

    /// User-adjustable cap (Settings → About). Applies from the next write —
    /// an oversized current file rotates as soon as anything else is logged.
    func updateSizeCap(bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        sizeCapBytes = max(100_000, bytes)
    }

    /// A pipeline logger writing to the shared file. Text format keeps the
    /// file human-readable; structured error codes are rendered inline.
    func makeLogger(minimumLevel: LogLevel = .info) -> Logger {
        Logger(
            minimumLevel: minimumLevel, format: .text,
            sink: { [self] line in
                write(line)
            })
    }

    func write(_ line: String) {
        let data = Data((line + "\n").utf8)
        lock.lock()
        defer { lock.unlock() }
        do {
            if currentSize + data.count > sizeCapBytes {
                try? fileManager.removeItem(at: previousLogURL)
                do {
                    try fileManager.moveItem(at: logURL, to: previousLogURL)
                    currentSize = 0
                } catch {
                    // Keep accounting for the oversized current file; the
                    // next write will retry rotation instead of growing blind.
                }
            }
            if !fileManager.fileExists(atPath: logURL.path) {
                try fileManager.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: logURL, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            currentSize += data.count
        } catch {
            // Diagnostics must never take down the app; stderr still sees it.
            FileHandle.standardError.write(Data(("log write failed: \(error)\n").utf8))
        }
    }
}

/// Process-wide sink under the GUI state directory (path shown in Settings).
enum GUILog {
    /// Default and selectable caps for Settings, in megabytes. GUI-only
    /// state, so the choice lives in UserDefaults (packaging plan WI-6),
    /// not the shared config.json.
    static let defaultSizeCapMB = 5
    static let sizeCapChoicesMB = [1, 5, 10, 25, 50]

    static func storedSizeCapMB(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: PreferenceKeys.logSizeCapMB)
        return stored > 0 ? stored : defaultSizeCapMB
    }

    static let shared = FileLogSink(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CupricAspect", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true),
        sizeCapBytes: storedSizeCapMB() * 1_000_000
    )
}
