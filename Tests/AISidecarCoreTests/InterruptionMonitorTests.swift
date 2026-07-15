import Foundation
import XCTest

@testable import AISidecarCore

final class InterruptionMonitorTests: XCTestCase {
    func testInterruptionDrainsRegisteredHandlersOnce() {
        let monitor = InterruptionMonitor()
        let counter = LockedCounter()
        let registration = monitor.onInterruption { counter.increment() }

        XCTAssertTrue(monitor.requestInterruption())
        XCTAssertFalse(monitor.requestInterruption())
        XCTAssertEqual(counter.value, 1)
        registration.cancel()
    }

    func testRemovedHandlerDoesNotFire() {
        let monitor = InterruptionMonitor()
        let counter = LockedCounter()
        let registration = monitor.onInterruption { counter.increment() }

        registration.cancel()
        monitor.requestInterruption()

        XCTAssertEqual(counter.value, 0)
    }

    func testHandlerRegisteredAfterInterruptionFiresImmediately() {
        let monitor = InterruptionMonitor()
        let counter = LockedCounter()
        monitor.requestInterruption()

        let registration = monitor.onInterruption { counter.increment() }

        registration.cancel()
        XCTAssertEqual(counter.value, 1)
    }

    func testCallbackCanReenterMonitorWithoutDeadlocking() {
        let monitor = InterruptionMonitor()
        let counter = LockedCounter()
        let registration = monitor.onInterruption {
            if monitor.isInterrupted {
                counter.increment()
            }
        }

        monitor.requestInterruption()

        XCTAssertEqual(counter.value, 1)
        registration.cancel()
    }

    func testConcurrentCancellationAndInterruptionFireAtMostOnce() {
        for _ in 0..<100 {
            let monitor = InterruptionMonitor()
            let counter = LockedCounter()
            let registration = monitor.onInterruption { counter.increment() }

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    registration.cancel()
                } else {
                    monitor.requestInterruption()
                }
            }

            XCTAssertLessThanOrEqual(counter.value, 1)
        }
    }

    func testCallbackCanCancelItsOwnRegistration() {
        let monitor = InterruptionMonitor()
        let counter = LockedCounter()
        let holder = RegistrationHolder()
        let registration = monitor.onInterruption {
            holder.cancel()
            counter.increment()
        }
        holder.store(registration)

        monitor.requestInterruption()

        XCTAssertEqual(counter.value, 1)
    }

    func testSIGINTActionsAccountForCoalescedDeliveries() {
        XCTAssertEqual(
            InterruptionMonitor.sigintActions(alreadyInterrupted: false, deliveryCount: 1),
            [.requestInterruption]
        )
        XCTAssertEqual(
            InterruptionMonitor.sigintActions(alreadyInterrupted: false, deliveryCount: 3),
            [.requestInterruption, .armDefaultDisposition, .terminate]
        )
        XCTAssertEqual(
            InterruptionMonitor.sigintActions(alreadyInterrupted: true, deliveryCount: 2),
            [.armDefaultDisposition, .terminate]
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class RegistrationHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: InterruptionRegistration?

    func store(_ registration: InterruptionRegistration) {
        lock.withLock { self.registration = registration }
    }

    func cancel() {
        let registration = lock.withLock { self.registration }
        registration?.cancel()
    }
}
