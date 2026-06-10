import Darwin
import Dispatch
import Foundation

/// Shared interruption state for the analyze shell pipeline.
///
/// Signal handlers only mark intent; the pipeline observes the flag between
/// files so an in-flight atomic write can finish or remain absent.
public final class InterruptionMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false
    private var sources: [DispatchSourceSignal] = []

    public init() {}

    public var isInterrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return interrupted
    }

    /// Mark the current run as interrupted without terminating the process.
    public func requestInterruption() {
        lock.lock()
        interrupted = true
        lock.unlock()
    }

    /// Install SIGINT/SIGTERM handlers that request a graceful batch stop.
    public func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        // A dedicated queue lets signals be observed while the CLI task is
        // rendering, isolating, or writing the current file.
        let queue = DispatchQueue(label: "aisidecar.signal-monitor")
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        interruptSource.setEventHandler { [weak self] in
            self?.requestInterruption()
        }

        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        terminateSource.setEventHandler { [weak self] in
            self?.requestInterruption()
        }

        lock.lock()
        sources = [interruptSource, terminateSource]
        lock.unlock()

        interruptSource.resume()
        terminateSource.resume()
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}
