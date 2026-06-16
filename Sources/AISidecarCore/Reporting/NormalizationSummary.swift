import Foundation

/// Markdown summary writer for human-readable Phase 3 normalization review.
public struct NormalizationSummaryWriter {
    private let fileManager: FileManager

    /// Create a Markdown writer for human review of normalization sessions.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Render a deterministic Markdown summary from a machine-readable report.
    public func markdown(for report: NormalizationReport) -> String {
        var lines: [String] = []
        lines.append("# Normalization Summary")
        lines.append("")
        lines.append("- Schema: \(report.schemaVersion)")
        lines.append("- Input: \(report.inputPath)")
        lines.append("- Workflow: \(report.workflow.rawValue)")
        lines.append("- Mode: \(report.configuration.normalizationMode.rawValue)")
        lines.append("- Vocabulary SHA-256: \(report.vocabulary.sha256)")
        lines.append("- XMP writer: \(report.xmpWriter.engineName) \(report.xmpWriter.engineVersion)")
        lines.append("- Writer recipe: \(report.xmpWriter.writerRecipeVersion)")
        lines.append("- Source assets: \(report.inputSummary.sourceAssetCount)")
        lines.append("- Same-base-name groups: \(report.inputSummary.sameBaseNameGroupCount)")
        lines.append("- Candidate observations: \(report.inputSummary.candidateObservationCount)")
        lines.append("- Candidate skips: \(report.inputSummary.candidateSkipCount)")
        lines.append("- Accepted decisions: \(report.decisionSummary.acceptedCount)")
        lines.append("- Withheld decisions: \(report.decisionSummary.withheldCount)")
        lines.append("- XMP write plans: \(report.inputSummary.xmpWritePlanCount)")
        lines.append("")
        appendAffinity(&lines, report: report)
        appendDecisions(&lines, report: report)
        appendSkippedCandidates(&lines, report: report)
        appendTargets(&lines, report: report)
        appendErrors(&lines, title: "Warnings", errors: report.warnings)
        appendErrors(&lines, title: "Errors", errors: report.errors)
        lines.append("## Post-Export Application Instructions")
        for instruction in report.applicationInstructions {
            lines.append("- \(instruction)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Atomically write the Markdown summary artifact.
    public func write(_ report: NormalizationReport, to path: String) throws {
        do {
            let data = Data(markdown(for: report).utf8)
            try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path), fileManager: fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to write normalization summary \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }

    private func appendAffinity(_ lines: inout [String], report: NormalizationReport) {
        lines.append("## Affinity")
        lines.append("- Mode: \(report.affinity.mode.rawValue)")
        lines.append("- Profile: \(report.affinity.profile.rawValue)")
        lines.append("- Nodes: \(report.affinity.nodes.count)")
        lines.append("- Stored edges: \(report.affinity.edges.count)")
        for edge in report.affinity.edges.prefix(10) {
            let basis = edge.components.basisSignals.joined(separator: ", ")
            lines.append("- \(edge.scoreBand): \(edge.fromNodeID) -> \(edge.toNodeID), score \(edge.affinity), basis \(basis)")
        }
        lines.append("")
    }

    private func appendDecisions(_ lines: inout [String], report: NormalizationReport) {
        lines.append("## Decisions")
        let grouped = Dictionary(grouping: report.perAssetDecisions, by: \.stage)
        for stage in NormalizationDecisionStage.allCasesForSummary {
            let decisions = grouped[stage, default: []]
            guard !decisions.isEmpty else {
                continue
            }
            lines.append("- \(stage.rawValue): \(decisions.count)")
        }
        for decision in report.perAssetDecisions.prefix(20) {
            let term = decision.hierarchicalKeyword ?? decision.flatKeyword ?? decision.canonicalPath ?? decision.sourceText ?? "unknown"
            var detail = "- \(decision.status.rawValue): \(decision.assetID) \(term) via \(decision.stage.rawValue)"
            if let rule = decision.governingRule {
                detail += " (\(rule))"
            }
            if let consensus = decision.localConsensus {
                let agreement = consensus.localWeightedAgreement.map { String($0) } ?? "n/a"
                detail += "; agreement \(agreement), support \(consensus.supportMass)/\(consensus.eligibleMass), neighbors \(consensus.supportingNeighborCount)"
            }
            lines.append(detail)
        }
        lines.append("")
    }

    private func appendSkippedCandidates(_ lines: inout [String], report: NormalizationReport) {
        lines.append("## Skips And Blocks")
        if report.candidateSkips.isEmpty {
            lines.append("- None")
        } else {
            let counts = Dictionary(grouping: report.candidateSkips, by: \.reason)
                .mapValues(\.count)
            for reason in counts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                lines.append("- \(reason.rawValue): \(counts[reason, default: 0])")
            }
        }
        lines.append("")
    }

    private func appendTargets(_ lines: inout [String], report: NormalizationReport) {
        lines.append("## XMP Plans")
        if report.xmpWritePlans.isEmpty {
            lines.append("- No XMP plans emitted for this invocation.")
        } else {
            for writePlan in report.xmpWritePlans {
                let plan = writePlan.xmpChangePlan
                lines.append("- \(plan.status.rawValue): \(plan.targetRelativePath)")
                lines.append("  - Flat: \(plan.flatKeywordsToAdd.map(\.term).joined(separator: ", "))")
                lines.append("  - Hierarchical: \(plan.hierarchicalKeywordsToAdd.map(\.term).joined(separator: ", "))")
                if !plan.failures.isEmpty {
                    lines.append("  - Failures: \(plan.failures.map(\.code.rawValue).joined(separator: ", "))")
                }
            }
        }
        lines.append("")
    }

    private func appendErrors(_ lines: inout [String], title: String, errors: [SidecarError]) {
        guard !errors.isEmpty else {
            return
        }
        lines.append("## \(title)")
        for error in errors {
            lines.append("- \(error.code.rawValue): \(error.message)")
        }
        lines.append("")
    }
}

private extension NormalizationDecisionStage {
    static let allCasesForSummary: [NormalizationDecisionStage] = [
        .directModelObservation,
        .userSessionContext,
        .localAffinityPropagation,
        .globalBackstopPropagation,
        .phase2Fallback
    ]
}
