/// Build a lookup while converting duplicate keys into a caller-defined structured error.
func uniqueLookup<Key: Hashable, Value>(
    _ pairs: [(Key, Value)],
    onDuplicate: (Key) -> SidecarError
) throws -> [Key: Value] {
    var result: [Key: Value] = [:]
    result.reserveCapacity(pairs.count)
    for (key, value) in pairs {
        guard result.updateValue(value, forKey: key) == nil else {
            throw onDuplicate(key)
        }
    }
    return result
}
