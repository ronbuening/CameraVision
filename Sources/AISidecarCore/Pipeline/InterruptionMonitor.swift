import Darwin
import Dispatch
import Foundation

/// Shared interruption state for the analyze shell pipeline.
///
/// The pipeline observes the flag at file and model-role boundaries. Registered
/// handlers cancel in-flight model requests while atomic writes remain complete
/// or absent.
public final class InterruptionMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false
    private var handlers: [UUID: InterruptionHandlerState] = [:]
    private var sources: [DispatchSourceSignal] = []

    public init() {}

    public var isInterrupted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return interrupted
    }

    /// Mark the current run as interrupted and notify registered in-flight work.
    ///
    /// Returns `true` only for the first request. Handlers are drained once and
    /// invoked outside the state lock so cancellation callbacks cannot deadlock.
    @discardableResult
    public func requestInterruption() -> Bool {
        lock.lock()
        let firstRequest = !interrupted
        interrupted = true
        let pendingHandlers = firstRequest ? Array(handlers.values) : []
        if firstRequest {
            handlers.removeAll()
        }
        lock.unlock()

        for handler in pendingHandlers {
            handler.fire()
        }
        return firstRequest
    }

    /// Register a callback for the first interruption request.
    ///
    /// The callback fires immediately when interruption was already requested.
    /// Cancel the returned registration after the protected work completes.
    @discardableResult
    public func onInterruption(_ handler: @escaping @Sendable () -> Void) -> InterruptionRegistration {
        let id = UUID()
        let state = InterruptionHandlerState(handler)
        lock.lock()
        if interrupted {
            lock.unlock()
            state.fire()
            return InterruptionRegistration(id: id, state: state, monitor: self)
        }
        handlers[id] = state
        lock.unlock()
        return InterruptionRegistration(id: id, state: state, monitor: self)
    }

    fileprivate func removeInterruptionHandler(_ id: UUID) {
        lock.lock()
        handlers.removeValue(forKey: id)
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
        let interruptSourceReference = WeakSignalSourceReference(interruptSource)
        interruptSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let deliveryCount = interruptSourceReference.source?.data ?? 1
            for action in Self.sigintActions(
                alreadyInterrupted: self.isInterrupted,
                deliveryCount: deliveryCount
            ) {
                switch action {
                case .requestInterruption:
                    self.requestInterruption()
                case .armDefaultDisposition:
                    signal(SIGINT, SIG_DFL)
                case .terminate:
                    raise(SIGINT)
                }
            }
        }

        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        terminateSource.setEventHandler { [weak self] in
            self?.requestInterruption()
        }

        lock.lock()
        let previousSources = sources
        sources = [interruptSource, terminateSource]
        lock.unlock()

        for source in previousSources {
            source.cancel()
        }

        interruptSource.resume()
        terminateSource.resume()
    }

    static func sigintActions(alreadyInterrupted: Bool, deliveryCount: UInt) -> [SIGINTAction] {
        let count = max(1, Int(deliveryCount))
        var actions: [SIGINTAction] = []
        var interrupted = alreadyInterrupted
        var defaultArmed = false

        for _ in 0..<count {
            if defaultArmed {
                actions.append(.terminate)
                break
            }
            if interrupted {
                actions.append(.armDefaultDisposition)
                defaultArmed = true
            } else {
                actions.append(.requestInterruption)
                interrupted = true
            }
        }
        return actions
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}

enum SIGINTAction: Sendable, Equatable {
    case requestInterruption
    case armDefaultDisposition
    case terminate
}

private final class WeakSignalSourceReference: @unchecked Sendable {
    weak var source: DispatchSourceSignal?

    init(_ source: DispatchSourceSignal) {
        self.source = source
    }
}

/// Removable lifetime token for one interruption callback.
public final class InterruptionRegistration: @unchecked Sendable {
    private let id: UUID
    private let state: InterruptionHandlerState
    private weak var monitor: InterruptionMonitor?

    fileprivate init(id: UUID, state: InterruptionHandlerState, monitor: InterruptionMonitor) {
        self.id = id
        self.state = state
        self.monitor = monitor
    }

    /// Prevent the callback from firing after the protected work completes.
    public func cancel() {
        state.cancel()
        monitor?.removeInterruptionHandler(id)
    }

    deinit {
        cancel()
    }
}

private final class InterruptionHandlerState: @unchecked Sendable {
    // Recursive so a callback may cancel its own registration. Concurrent
    // cancellation still waits for an already-running callback to finish.
    private let lock = NSRecursiveLock()
    private var handler: (@Sendable () -> Void)?

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func fire() {
        lock.lock()
        guard let handler else {
            lock.unlock()
            return
        }
        self.handler = nil
        handler()
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        handler = nil
        lock.unlock()
    }
}
