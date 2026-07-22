/// FileManager enumeration invokes its error callback synchronously. This box
/// gives such callbacks reference semantics; unchecked sendability does not make
/// mutation safe across tasks.
final class SynchronousCallbackAccumulator<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}
