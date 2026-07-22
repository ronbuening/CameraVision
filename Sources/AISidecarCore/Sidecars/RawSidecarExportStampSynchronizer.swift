import CryptoKit
import Foundation

// CORE-4 (FR4-049): stamp synchronization is best-effort because failures
// cannot invalidate an XMP sidecar that already passed post-write validation.
struct RawSidecarExportStampSynchronizer {
    private let fileManager: FileManager
    private let logger: Logger
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.now = now
    }

    func synchronize(
        report: XMPExportTargetReport,
        context: MetadataWriteEngineContext,
        gradingEnabled: Bool
    ) {
        guard report.status == .written || report.status == .created || report.status == .unchanged else {
            return
        }
        let targetPath = report.plan.targetXMPPath
        guard let xmpData = fileManager.contents(atPath: targetPath),
            let postSnapshot = report.writeResult?.postWriteSnapshot
        else {
            return
        }
        let sidecarPaths = selectedContributorSidecarPaths(for: report.plan)
        guard !sidecarPaths.isEmpty else {
            try? logger.log(
                LogRecord(
                    level: .warn,
                    event: "write_xmp.stamp_skipped",
                    message: "Skipped export stamp because this target has no contributing raw .ai.json sidecar.",
                    sidecarPath: targetPath,
                    status: "skipped"
                ))
            return
        }

        let xmpSHA256 = SHA256.hash(data: xmpData).map { String(format: "%02x", $0) }.joined()
        let prior = trustedPriorStampOwnership(sidecarPaths: sidecarPaths, targetXMPPath: targetPath)
        let contents = RawSidecarExportStamp.Contents(
            targetXMPPath: targetPath,
            xmpSHA256: xmpSHA256,
            writerRecipeVersion: context.writerRecipeVersion,
            engineVersion: context.engineVersion,
            exportedAt: now(),
            rating: ownedStampedScalar(
                write: report.plan.ratingWrite,
                postWriteValue: postSnapshot.rating,
                priorOwnedValue: prior.rating,
                gradingEnabled: gradingEnabled
            ),
            label: ownedStampedScalar(
                write: report.plan.labelWrite,
                postWriteValue: postSnapshot.label,
                priorOwnedValue: prior.label,
                gradingEnabled: gradingEnabled
            ),
            urgency: ownedStampedScalar(
                write: report.plan.urgencyWrite,
                postWriteValue: postSnapshot.urgency,
                priorOwnedValue: prior.urgency,
                gradingEnabled: gradingEnabled
            ),
            pick: ownedStampedScalar(
                write: report.plan.pickWrite,
                postWriteValue: postSnapshot.pick,
                priorOwnedValue: prior.pick,
                gradingEnabled: gradingEnabled
            ),
            good: ownedStampedScalar(
                write: report.plan.goodWrite,
                postWriteValue: postSnapshot.good,
                priorOwnedValue: prior.good,
                gradingEnabled: gradingEnabled
            ),
            qualityTier: gradingEnabled ? report.plan.qualityTier : prior.qualityTier
        )
        for sidecarPath in sidecarPaths {
            if let existing = RawSidecarExportStamp.contents(
                sidecarPath: sidecarPath,
                fileManager: fileManager
            ), stampSemanticallyMatches(existing, contents) {
                continue
            }
            do {
                try RawSidecarExportStamp.stamp(
                    sidecarPath: sidecarPath,
                    contents: contents,
                    fileManager: fileManager
                )
            } catch {
                try? logger.log(
                    LogRecord(
                        level: .warn,
                        event: "write_xmp.stamp_failed",
                        message:
                            "XMP was written, but its raw-sidecar export stamp failed: \(error.localizedDescription)",
                        sidecarPath: sidecarPath,
                        status: "warning",
                        errors: (error as? SidecarError).map { [$0] } ?? []
                    ))
            }
        }
    }

    func selectedContributorSidecarPaths(for plan: XMPChangePlan) -> [String] {
        var paths: Set<String> = []
        for member in plan.sourceMembers where member.selected {
            for path in [member.sourceSidecarPath, member.qualitySidecarPath].compactMap({ $0 })
            where path.lowercased().hasSuffix(".ai.json") {
                paths.insert(URL(fileURLWithPath: path).standardizedFileURL.path)
            }
        }
        return paths.sorted(by: comparePaths)
    }

    private func trustedPriorStampOwnership(
        sidecarPaths: [String],
        targetXMPPath: String
    ) -> PriorStampOwnership {
        var stamps: [RawSidecarExportStamp.Contents] = []
        for path in sidecarPaths {
            let contents = RawSidecarExportStamp.contents(sidecarPath: path, fileManager: fileManager)
            if RawSidecarExportStamp.isStamped(sidecarPath: path, fileManager: fileManager), contents == nil {
                return PriorStampOwnership()
            }
            if let contents {
                stamps.append(contents)
            }
        }
        guard let newestDate = stamps.map(\.exportedAt).max() else {
            return PriorStampOwnership()
        }
        let newest = stamps.filter { $0.exportedAt == newestDate }
        let standardizedTarget = URL(fileURLWithPath: targetXMPPath).standardizedFileURL.path
        guard
            newest.allSatisfy({
                URL(fileURLWithPath: $0.targetXMPPath).standardizedFileURL.path == standardizedTarget
            })
        else {
            return PriorStampOwnership()
        }
        return PriorStampOwnership(
            rating: commonOptionalValue(newest.map(\.rating)),
            label: commonOptionalValue(newest.map(\.label)),
            urgency: commonOptionalValue(newest.map(\.urgency)),
            pick: commonOptionalValue(newest.map(\.pick)),
            good: commonOptionalValue(newest.map(\.good)),
            qualityTier: commonOptionalValue(newest.map(\.qualityTier))
        )
    }

    private func commonOptionalValue<Value: Equatable>(_ values: [Value?]) -> Value? {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    private func ownedStampedScalar(
        write: PlannedScalarWrite?,
        postWriteValue: String?,
        priorOwnedValue: String?,
        gradingEnabled: Bool
    ) -> String? {
        guard gradingEnabled else {
            return postWriteValue == priorOwnedValue ? priorOwnedValue : nil
        }
        if let write,
            write.action == .write || write.action == .overwrite,
            postWriteValue == write.plannedValue
        {
            return write.plannedValue
        }
        if let priorOwnedValue, postWriteValue == priorOwnedValue {
            return priorOwnedValue
        }
        return nil
    }

    private func stampSemanticallyMatches(
        _ lhs: RawSidecarExportStamp.Contents,
        _ rhs: RawSidecarExportStamp.Contents
    ) -> Bool {
        lhs.targetXMPPath == rhs.targetXMPPath
            && lhs.xmpSHA256 == rhs.xmpSHA256
            && lhs.writerRecipeVersion == rhs.writerRecipeVersion
            && lhs.engineVersion == rhs.engineVersion
            && lhs.rating == rhs.rating
            && lhs.label == rhs.label
            && lhs.urgency == rhs.urgency
            && lhs.pick == rhs.pick
            && lhs.good == rhs.good
            && lhs.qualityTier == rhs.qualityTier
    }
}

private struct PriorStampOwnership {
    var rating: String?
    var label: String?
    var urgency: String?
    var pick: String?
    var good: String?
    var qualityTier: QualityTier?

    init(
        rating: String? = nil,
        label: String? = nil,
        urgency: String? = nil,
        pick: String? = nil,
        good: String? = nil,
        qualityTier: QualityTier? = nil
    ) {
        self.rating = rating
        self.label = label
        self.urgency = urgency
        self.pick = pick
        self.good = good
        self.qualityTier = qualityTier
    }
}
