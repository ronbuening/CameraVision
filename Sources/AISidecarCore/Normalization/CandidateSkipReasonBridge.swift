enum CandidateSkipReasonBridge {
    static func normalizationReason(
        for reason: SkippedCandidateReason
    ) -> NormalizationCandidateSkipReason {
        bridge(reason, to: NormalizationCandidateSkipReason.self)
    }

    static func skippedCandidateReason(
        for reason: NormalizationCandidateSkipReason
    ) -> SkippedCandidateReason {
        bridge(reason, to: SkippedCandidateReason.self)
    }

    private static func bridge<Source: RawRepresentable, Destination: RawRepresentable>(
        _ source: Source,
        to _: Destination.Type
    ) -> Destination where Source.RawValue == String, Destination.RawValue == String {
        guard let destination = Destination(rawValue: source.rawValue) else {
            preconditionFailure("Candidate skip-reason raw-value parity violated: \(source.rawValue)")
        }
        return destination
    }
}
