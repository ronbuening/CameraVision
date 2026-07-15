import AISidecarCore
import ArgumentParser
import Foundation

/// CLI-1 (Phase 4 plan): read-only decision traces over a normalization
/// session file. All rollup and wording comes from Core's
/// `NormalizationDecisionExplainer` (FR4-055), shared with the GUI's
/// Normalization Inspector — this command is presentation only.
struct ExplainSessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain-session",
        abstract: "Explain the decisions recorded in a normalization session file."
    )

    @Argument(help: "Path to a normalization-session-*.json file.")
    var sessionPath: String

    @Option(help: "Explain one keyword (canonical path, keyword, or source term).")
    var keyword: String?

    @Flag(help: "Show only keywords needing attention (requires review, conflicts, unmatched vocabulary).")
    var needsAttention = false

    @Flag(help: "Include per-asset decision lines.")
    var verbose = false

    func run() throws {
        let session = try NormalizationSessionReader().read(from: sessionPath)

        let summaries: [KeywordDecisionSummary]
        if let keyword {
            guard let summary = NormalizationDecisionExplainer.summary(for: keyword, in: session) else {
                throw ValidationError("No decisions found for keyword: \(keyword)")
            }
            summaries = [summary]
        } else if needsAttention {
            summaries = NormalizationDecisionExplainer.needsAttention(in: session)
        } else {
            summaries = NormalizationDecisionExplainer.summaries(for: session)
        }

        if summaries.isEmpty {
            print(needsAttention ? "No keywords need attention." : "The session records no keyword decisions.")
            return
        }

        var first = true
        for summary in summaries {
            if !first { print("") }
            first = false
            for line in NormalizationDecisionExplainer.renderLines(summary, verbose: verbose || keyword != nil) {
                print(line)
            }
        }
    }
}
