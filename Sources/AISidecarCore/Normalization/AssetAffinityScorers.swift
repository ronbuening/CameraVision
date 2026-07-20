import Foundation

/// Capture-time proximity scorer using the Phase 3 decay formula.
public enum CaptureTimeAffinityScorer {
    public static func score(deltaSeconds: Double?, profile: AssetAffinityProfile) -> Double? {
        AffinityDecay.score(
            value: deltaSeconds.map(abs),
            halfLife: profile.timeHalfLifeSeconds,
            cutoff: profile.timeCutoffSeconds
        )
    }
}

/// GPS proximity scorer. Distance calculation is kept separate for deterministic tests.
public enum GPSAffinityScorer {
    public static func score(distanceMeters: Double?, profile: AssetAffinityProfile) -> Double? {
        AffinityDecay.score(
            value: distanceMeters,
            halfLife: profile.gpsHalfDistanceMeters,
            cutoff: profile.gpsCutoffMeters
        )
    }

    public static func haversineMeters(
        latitudeA: Double,
        longitudeA: Double,
        latitudeB: Double,
        longitudeB: Double
    ) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitudeA * .pi / 180
        let lat2 = latitudeB * .pi / 180
        let deltaLat = (latitudeB - latitudeA) * .pi / 180
        let deltaLon = (longitudeB - longitudeA) * .pi / 180
        let a =
            sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Filename and explicit-list adjacency scorer for deterministic offline affinity.
public enum FilenameSequenceAffinityScorer {
    public static func score(
        lhs: AssetAffinityInputs,
        rhs: AssetAffinityInputs,
        profile: AssetAffinityProfile
    ) -> (score: Double?, basis: String?) {
        if lhs.relativeDirectory == rhs.relativeDirectory,
            let lhsSequence = lhs.parsedSequenceNumber,
            let rhsSequence = rhs.parsedSequenceNumber
        {
            let gap = Double(abs(lhsSequence - rhsSequence))
            return (
                AffinityDecay.score(value: gap, halfLife: profile.filenameHalfGap, cutoff: profile.filenameCutoff),
                "filename_sequence"
            )
        }

        if let lhsIndex = lhs.fileListIndex, let rhsIndex = rhs.fileListIndex {
            let gap = Double(abs(lhsIndex - rhsIndex))
            return (
                AffinityDecay.score(value: gap, halfLife: profile.filenameHalfGap, cutoff: profile.filenameCutoff),
                "explicit_file_list_adjacency"
            )
        }

        return (nil, nil)
    }
}

/// Camera and lens agreement scorer used only as a boost on primary evidence.
public enum CameraLensAffinityScorer {
    public static func score(lhs: AssetAffinityInputs, rhs: AssetAffinityInputs) -> Double {
        let bodyScore: Double
        if let lhsSerial = lhs.cameraSerialHash, lhsSerial == rhs.cameraSerialHash {
            bodyScore = 1.0
        } else if let lhsClass = lhs.cameraIdentityClass, lhsClass == rhs.cameraIdentityClass {
            bodyScore = 0.75
        } else {
            bodyScore = 0.0
        }

        let lensScore: Double
        if let lhsLens = lhs.lensIdentityClass, lhsLens == rhs.lensIdentityClass {
            lensScore = 0.80
        } else {
            lensScore = 0.0
        }

        return (0.35 * bodyScore) + (0.65 * lensScore)
    }
}

/// Six-decimal score rounding and deterministic score-band assignment.
public enum AffinityScoreFormatter {
    public static func rounded(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    public static func band(for score: Double) -> String {
        switch score {
        case 0.75...:
            return "very_strong"
        case 0.55..<0.75:
            return "strong"
        case 0.35..<0.55:
            return "moderate"
        case 0.15..<0.35:
            return "weak"
        default:
            return "ignored"
        }
    }
}
