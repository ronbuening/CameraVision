func stableUnique<Value: Hashable>(_ values: [Value]) -> [Value] {
    var seen: Set<Value> = []
    var result: [Value] = []
    for value in values where seen.insert(value).inserted {
        result.append(value)
    }
    return result
}

func frequencyCounts<Value: Hashable>(_ values: [Value]) -> [Value: Int] {
    values.reduce(into: [:]) { partial, value in
        partial[value, default: 0] += 1
    }
}
