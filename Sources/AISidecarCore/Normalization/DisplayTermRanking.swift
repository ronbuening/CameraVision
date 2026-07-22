enum DisplayTermRanking {
    static func preferredTerm(in terms: [String]) -> String {
        let counts = frequencyCounts(terms)
        let keyedTerms = terms.map {
            (
                term: $0,
                lowercased: $0.lowercased(),
                titleCaseWordCount: titleCaseWordCount($0)
            )
        }
        return keyedTerms.sorted { lhs, rhs in
            let lhsCount = counts[lhs.term, default: 0]
            let rhsCount = counts[rhs.term, default: 0]
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            if lhs.titleCaseWordCount != rhs.titleCaseWordCount {
                return lhs.titleCaseWordCount > rhs.titleCaseWordCount
            }
            if lhs.term.count != rhs.term.count {
                return lhs.term.count < rhs.term.count
            }
            if lhs.lowercased != rhs.lowercased {
                return lhs.lowercased < rhs.lowercased
            }
            return lhs.term < rhs.term
        }.first?.term ?? ""
    }

    private static func titleCaseWordCount(_ value: String) -> Int {
        value.split(whereSeparator: \.isWhitespace).filter { word in
            guard let first = word.first, first.isUppercase else {
                return false
            }
            return word.dropFirst().contains { $0.isLowercase }
        }.count
    }
}
