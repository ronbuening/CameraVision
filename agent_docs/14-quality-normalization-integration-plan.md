# Quality × Normalization Integration — Staged Implementation Plan

Version: 1.0
Date: 2026-07-17
Status: ready for execution (no code started)
Authorities: `agent_docs/12-image-quality-assessment-plan.md` (quality design), `agent_docs/13-image-quality-implementation-stages.md` (phase-4 execution record, §0 work rules apply here verbatim), `agent_docs/invariants.md` (all of it).
Audience: implementing agents (junior engineer / Sonnet-level) and reviewing agents. Each stage is written to be executed **unaided** by an agent that has read only: this document's §0–§2, the stage itself, and the source files the stage lists.

---

## 0. How to work a stage

Doc 13 §0's eight rules apply verbatim (one stage at a time in ledger order; read invariants and every listed file fully first; shipped version files immutable; tests deterministic and offline; every stage ends green with `swift test` then `Scripts/format.sh` then one commit; reality-disagrees → ledger note and stop; scope discipline; comments per the commenting guide). Two additions specific to this plan:

9. **No behavior change without a flag.** Every stage must leave a default-off (or refactor-identical) footprint: a `normalize` run without the new flags produces byte-identical sidecars, sessions, reports, and XMP to today. Assert this with existing untouched tests plus the explicit identity tests each stage lists.
10. **The GUI is out of scope for code.** Stages prepare and document the Core seams the app will bind to (QN7); no file under `Sources/CupricAspectApp` may change in this plan. GUI wiring gets its own pass later, like doc 13's deferred IQ-M6.

## 1. Stage ledger

Update Status (`pending` / `in progress` / `done` / `blocked`) and Notes as stages complete. This table is the single source of truth for execution state.

| Stage | Title | Depends on | Size | Status | Notes |
|---|---|---|---|---|---|
| QN1 | Grading block on the normalization configuration | — | S | done | Actual config path: `Configuration/NormalizationConfiguration.swift`. Reality note: Sources has three normalization→XMP execution converters, not two; `AnalyzeAndNormalizePipeline` was added to scope with `NormalizeAndWritePipeline` and `ApplySessionPipeline` so none drops grading. The other two constructors are non-execution adapters: `NormalizationInputResolver` configures raw-sidecar resolution (grading is unused), while `NormalizePipeline` configures candidate extraction and is deferred to QN3's grading seam. Default grading is omitted from encoded resolved normalization config to preserve flag-absent session/report bytes; legacy absence decodes to defaults. `swift test` passed (716 tests, 2 skipped); `Scripts/format.sh` completed on 2026-07-17. |
| QN2 | Extract the shared grading plan applier | — | M | done | Pure move into the internal `QualityGradingPlanApplier`, whose smallest reusable API accepts selected `[ResolvedRawSidecarInput]` values so both primary and quality-sibling documents remain available without widening planner internals. `XMPChangePlanner` keeps its public API and delegates once; the grading helpers no longer remain in that planner. A pre-QN2 grading-enabled public-plan fixture pins encoded bytes across the refactor. `swift test` passed (717 tests, 2 skipped); `Scripts/format.sh` completed on 2026-07-17. |
| QN3 | Grading in the normalized write path | QN1, QN2 | L | done | `NormalizationResolvedInputBatch.rawSidecarInputs` already retained quality siblings, so no input-type extension was needed. The normalized planner maps selected asset IDs back to primary inputs, delegates once to the QN2 applier after vocabulary/consensus output is final, keeps quality keywords out of normalization provenance, and records selected quality siblings for dual stamping. Write/dry-run planning reads current XMP through an injected snapshot seam; session-only previews intentionally retain tier, explanation, and quality keywords without reading XMP or claiming unresolved scalar rows. Normalization progress gained additive optional grading rows, and legacy decoding is pinned. A deterministic QN2 baseline now pins byte identity for the default-off session, report, progress, summary, stamped raw sidecar, and final XMP, in addition to the direct plan fixture. `swift test` passed (729 tests, 2 skipped); focused adversarial review passed (12 tests); `git diff --check` passed; `Scripts/format.sh` completed on 2026-07-17. |
| QN4 | `--assess-quality` on normalize's analyze mode | — | M | done | `NormalizeCommand` owns the flag with `analyze`'s help text verbatim and projects it as the optional `RunConfigurationOverrides.qualityAssessment` override; no `AnalyzePipeline` change was needed because `AnalyzeAndNormalizePipeline` already passes the resolved task profile through. Positional mode accepts the flag, while `--from-json` and `--file-list` reject it before I/O. Tests resolve the absent/true quality-assessment override and pin `tagging` + v1.5.0 versus `tagging_with_quality` + v1.6.0 prompt/schema provenance in the written raw sidecar. `swift test` passed (731 tests, 2 skipped); focused tests passed (18 tests); CLI help and both rejection paths were smoke-checked; `git diff --check` passed; `Scripts/format.sh` completed on 2026-07-17. |
| QN5 | Shared `QualityGradingOptions` CLI group | QN1 | M | done | `QualityGradingOptions` is now the sole declaration and overrides-projection site for the grading master switch, conflict/confidence options, and all five existing positive/negative channel pairs (rating, label, urgency, flag, and quality keywords; the stage text's “four” count was stale). `write-xmp` and `normalize` both adopt the flattened option group; normalize carries the fields through invocation validation and the QN1 configuration override. `write-xmp --help` remained byte-identical from `OVERVIEW` onward, normalize exposes every grading option exactly once, and manual smoke checks confirmed all five conflicting pairs fail with established messages. `swift test` passed (732 tests, 2 skipped); focused invocation tests passed (19 tests); declaration-site grep and `git diff --check` passed; `Scripts/format.sh` completed on 2026-07-17. |
| QN6 | Grading at apply-session time | QN3, QN5 | M | pending | |
| QN7 | GUI enablement seam (Core-side only) | QN3, QN4, QN5 | S | pending | |
| QN8 | Documentation pass | QN1–QN7 | S | pending | |

## 2. Design overview

### Problem

Quality assessment/grading (phase 4 + S4.10) and keyword normalization are separate pipelines today. Composing them takes three commands, and the grading-only `write-xmp` pass must disable the flat/hierarchical keyword channels to avoid diluting normalized keywords — which also suppresses the deterministic `AI Quality|<tier>` quality keywords, because they ride the same channel gates. `normalize` knows nothing about quality: no `--assess-quality` in its analyze mode, no grading in its write path.

### Target behavior

One command does everything:

```bash
aisidecar normalize /path/to/photos --recursive --mode both \
  --assess-quality --quality-grading
```

- The analyze phase runs the combined v1.6.0 contract (`tagging_with_quality`).
- Vocabulary/consensus normalization operates **only** on model keyword candidates, exactly as today. Quality keywords are never candidates (pinned since S3.1) and are **never normalized**: the write path appends them verbatim (post `KeywordSafetyPolicy`) after the normalized lists are final.
- The normalized XMP write carries the full grading output: quality keywords, labels, urgency, pick flags, and (opt-in) ratings, under the same `preserve`/`refresh`/`overwrite` conflict policies, stamps, and guard chain as `write-xmp --quality-grading`.
- Existing `AI Quality` keywords already present in a target XMP are preserved untouched (additive merge — assert, don't assume).

### Architecture decisions (record deviations in the ledger, per §0 rule 6)

- **D-QN1 — One grading implementation.** The grading section of `XMPChangePlanner.plan` (assessment extraction → tier derivation → scalar-write resolution incl. the pick/good pair → quality-keyword merge → explanation/ungraded reporting) is extracted into a shared component both planners call (QN2). No fork of the conflict-policy or pair-coupling logic may exist.
- **D-QN2 — Grading is computed wherever plans are built, never frozen as authority.** `NormalizePipeline` grades when it builds write plans; `ApplySessionPipeline` re-grades when it rebuilds plans from frozen decisions (it already re-reads current XMP — grading follows the same rule). Plans stored inside session documents may carry grading rows as a *preview*; the apply-time rebuild is authoritative. Sessions gain no new required fields; old sessions must keep decoding (additive-optional only).
- **D-QN3 — Same configuration keys everywhere.** `normalize` and `apply-session` honor the existing `xmp_quality_*` config keys and `AISIDECAR_XMP_QUALITY_*` environment forms. No new key names are introduced; the keys simply gain a second consumer. The grading master switch stays default-off.
- **D-QN4 — One CLI flag surface.** The grading flags become a shared ArgumentParser `@OptionGroup` (`QualityGradingOptions`) so `write-xmp`, `normalize`, and `apply-session` present identical help text and identical conflict rules, and the GUI has one overrides shape to construct.
- **D-QN5 — GUI binds to overrides, not flags.** The app's models (`NormalizationModel`, `ExportModel`, `ReviewModel`) already construct Core override structs and call resolvers. GUI enablement therefore means: the override/resolved-config types those models touch carry the quality fields after QN1/QN4, and QN7 documents the exact binding points. No GUI code in this plan.

---

## 3. Stages

### QN1 — Grading block on the normalization configuration

**Goal.** `ResolvedNormalizationConfiguration` carries a `qualityGrading: ResolvedQualityGradingConfiguration`, resolved through the standard chain, and the normalization→export converters pass it through instead of dropping it.

**Files.**
- Modify: `Sources/AISidecarCore/Configuration/NormalizationConfiguration.swift` (or wherever `ResolvedNormalizationConfiguration` and `NormalizationConfigurationOverrides` live — locate by searching the type names; record the actual path in the ledger), `ConfigurationResolver.swift` (`resolveNormalization` + `NormalizationConfigurationBuilder` reuse the existing `QualityGradingConfigurationBuilder`), `Pipeline/NormalizeAndWritePipeline.swift` (`xmpConfiguration(from:)` gains `qualityGrading: configuration.qualityGrading`), and the equivalent converter in `Pipeline/ApplySessionPipeline.swift` (find it: search `ResolvedXMPExportConfiguration(` in that file).
- Read first: `ConfigurationResolver.resolveXMPExport` end to end (the grading builder wiring is the model to mirror), `XMPExportConfiguration.swift` §`ResolvedQualityGradingConfiguration`.

**Do.**
1. Add `qualityGrading: ResolvedQualityGradingConfiguration` to the resolved type with `builtInDefaults` = `.builtInDefaults` and Codable defaulting for legacy JSON (`decodeIfPresent … ?? .builtInDefaults`) — recorded sessions/configs without the block must keep decoding.
2. Add `qualityGrading: QualityGradingConfigurationOverrides` to the normalization overrides struct (defaulted empty initializer, like `XMPExportConfigurationOverrides`).
3. In `resolveNormalization`, run the shared `QualityGradingConfigurationBuilder` over the same `AppConfig` fields, environment keys, and overrides used by `resolveXMPExport` — dormant validation included (an invalid policy fails resolution even while grading is off, matching S4.7).
4. Both converters pass the block through so an enabled grading block reaches `XMPExportPipeline` unchanged.

**Tests.** Extend `ConfigResolutionTests`: normalize-resolution defaults equal `.builtInDefaults`; file/env/override precedence for at least `enabled`, `writeFlag`, and one map; dormant-invalid-policy rejection through `resolveNormalization`; legacy resolved-configuration JSON without the block decodes. Converter test: a resolved normalization configuration with grading enabled produces an export configuration whose `qualityGrading` compares equal.

**Review checklist.** No new key strings anywhere (D-QN3); both converters updated (a missed one silently drops grading — grep every `ResolvedXMPExportConfiguration(` construction in `Sources/` and account for each in the ledger note); default-off identity untouched.

**Commit.** `Carry the quality-grading block through normalization configuration (QN1)`

### QN2 — Extract the shared grading plan applier

**Goal.** The grading logic used by `XMPChangePlanner` becomes a reusable component with zero behavior change.

**Files.**
- Create: `Sources/AISidecarCore/Metadata/QualityGradingPlanApplier.swift`
- Modify: `Metadata/XMPChangePlan.swift` (the planner's grading section, currently the `configuration.qualityGrading.enabled` guard through the `pickWrite`/`goodWrite` block plus the private helpers `qualityAssessments`, `qualityExplanation`, `trustedStampedScalars`, `trustedTiedValue`, `scalarWrite`, `projectedValue`, `hierarchicalQualityKeywords`, `flatQualityKeywords`, `normalizedSafeKeywords`, `mergingQualityKeywords`, `qualityPlanningError`)
- Read first: `XMPChangePlan.swift` planner region end to end; `XMPQualityConflictMatrixTests.swift` and `XMPQualityExportIntegrationTests.swift` (the behavior being preserved).

**Do.** Move the grading application into the new type with an API shaped like:

```swift
struct QualityGradingPlanApplier {
    func apply(
        to plan: inout XMPChangePlan,
        contributors: [QualityDocumentContributor],
        grading: ResolvedQualityGradingConfiguration,
        writeFlatKeywords: Bool,
        writeHierarchicalKeywords: Bool,
        snapshotReader: ((String) throws -> XMPMetadataSnapshot)?
    )
}
```

(Exact shape may follow the code — e.g. `QualityDocumentContributor` may need to become internal-visible to the new file, or the applier may accept the resolver's member type; choose the smallest diff and record it.) `XMPChangePlanner` delegates to it; every behavior — ungraded reporting, keyword forms and safety, the 16-row conflict matrix semantics, urgency/label and pick/good coupling, stamp trust, snapshot-failure plan failure — must be reachable only through this component.

**Tests.** No new behavior: the existing grading suites (`XMPQualityConflictMatrixTests`, `XMPQualityExportIntegrationTests`, `XMPChangePlanTests`) pass unmodified. Add one refactor pin: a grading-enabled plan built before/after through the public planner API encodes byte-identically (fixture-driven, mirroring `testDisabledGradingKeepsPlanBytesStableAndNeverReadsXMP`'s technique).

**Review checklist.** Pure move — no logic edits mixed in; no public API change to `XMPChangePlanner`; grep confirms the moved helpers no longer exist in the planner.

**Commit.** `Extract QualityGradingPlanApplier from the XMP change planner (QN2)`

### QN3 — Grading in the normalized write path

**Goal.** `normalize` (write mode) grades: normalized keywords + verbatim quality keywords + guarded scalar/flag writes, end to end.

**Files.**
- Modify: `Sources/AISidecarCore/Normalization/NormalizedXMPChangePlanner.swift`, `Pipeline/NormalizePipeline.swift` (thread a snapshot reader / engine seam into plan building, mirroring how `XMPExportPipeline.runFromJSON` passes `{ try metadataEngine.readSnapshot(at: $0) }`), `Pipeline/NormalizeAndWritePipeline.swift` and `Pipeline/AnalyzeAndNormalizePipeline.swift` as needed for the seam.
- Read first: `NormalizedXMPChangePlanner.swift` end to end (how `NormalizationResolvedInputBatch` maps assets to raw documents — **verify quality siblings are visible**: normalization input resolution builds on the raw-sidecar resolver, which has carried `qualityDocument` since S2.4; if the normalization input type drops it, extending that type additively is in scope and must be ledger-noted), `NormalizePipeline.swift` around the `includeXMPPlans` block, doc 13 rows S2.4/S4.8.

**Do.**
1. After a target's normalized keyword lists are final, invoke `QualityGradingPlanApplier.apply` with the target's contributing documents (tagging + quality siblings), the configuration's grading block, the channel toggles, and the snapshot reader. Quality keywords are therefore appended **after** vocabulary/consensus and are never inputs to it.
2. `--session-only` runs (no write) still record the graded plans in the session as previews (D-QN2); a missing snapshot reader in a non-writing context degrades to plans without scalar resolution — pick the smallest coherent behavior, document it in a comment, and note it in the ledger.
3. Dry-run and report surfaces inherit the scalar rows automatically via the shared plan type; verify the normalization report/session encoders tolerate them (additive-optional; old sessions decode — pin with a legacy-session fixture test).

**Tests** (new `NormalizedQualityGradingTests.swift` or extension of the existing normalize suites; all offline, temp dirs):
- End-to-end normalize-with-write, grading enabled, fixture assessments → written XMP contains normalized keywords **and** `AI Quality|<tier>` **and** label/urgency/pick pair; stamps carry the scalar ownership; progress/report artifacts show the rows.
- **Normalization independence:** a controlled vocabulary that would rename or reject the literal terms `AI Quality good` / `AI Quality|good` leaves the written quality keywords byte-identical, and the vocabulary decision log shows no entry for them.
- **Existing-keyword preservation:** a target XMP already containing `AI Quality|good` plus foreign keywords is re-normalized; the pre-existing quality keywords survive unchanged.
- Default-off identity: a grading-disabled normalize run produces byte-identical session/report/XMP to a pre-stage fixture run.
- Ungraded (below-confidence) targets report the reason through the normalize report path, never silently.

**Review checklist.** No second grading implementation (all grading flows through the QN2 applier — grep); no change to consensus/vocabulary code paths beyond the append point; invariant 4 (writes still only through the owned engine chain via `XMPExportPipeline.runChangePlan`).

**Commit.** `Grade assessments in the normalized XMP write path (QN3)`

### QN4 — `--assess-quality` on normalize's analyze mode

**Goal.** `normalize <images> --assess-quality` runs the combined v1.6.0 contract during its analyze phase; existing-input modes reject the flag.

**Files.**
- Modify: `Sources/AISidecarCLI/NormalizeCommand.swift` (flag + run-overrides mapping, mirroring `AnalyzeCommand`'s post-S4.10 shape: own `@Flag`, merged into overrides), the normalization invocation validator (find it: search `NormalizationInvocationMode` / the from-json rejection list — `--assess-quality` joins the analyze-mode-only options exactly like `write-xmp`'s validator treats it), `Pipeline/AnalyzeAndNormalizePipeline.swift` only if the run configuration doesn't already flow through (read first — the pipeline holds an `AnalyzePipeline` and passes a resolved run configuration; `taskProfile` should ride along untouched).
- Read first: `AnalyzeCommand.swift`, `NormalizeCommand.swift` end to end, `XMPExportConfiguration.swift` invocation-validator region (the write-xmp precedent).

**Do.** Declare the flag with the same help text as `analyze`; map `qualityAssessment: assessQuality ? true : nil`; reject in `--from-json`/file-list modes with the established `configInvalid` phrasing; verify provenance (`run_configuration.task_profile == "tagging_with_quality"`) lands in the sidecars the analyze phase writes.

**Tests.** Recording-runner test through the analyze-and-normalize path asserting the v1.6.0 prompt/schema versions when enabled and 1.5.0 when not; sidecar provenance assertion; invocation rejection tests for both existing-input modes; `NoXMPRegressionTests` extension if the suite's pattern calls for it.

**Review checklist.** Flag lives on the command, not `SharedOptions` (assess-quality's command must not regrow it); default-off identity; no `AnalyzePipeline` changes.

**Commit.** `Add --assess-quality to normalize's analyze mode (QN4)`

### QN5 — Shared `QualityGradingOptions` CLI group

**Goal.** One declaration of the grading flag surface, presented identically by `write-xmp` and `normalize` (and `apply-session` in QN6), with one overrides projection for the GUI.

**Files.**
- Create: `Sources/AISidecarCLI/QualityGradingOptions.swift` — a `ParsableArguments` struct holding `--quality-grading`, the four paired channel flags plus `--write-rating`/`--no-write-rating`, `--write-flag`/`--no-write-flag`, `--quality-conflicts`, `--quality-min-confidence`, and a computed `overrides: QualityGradingConfigurationOverrides` (including the exhaustive confidence bridge — move it here from `WriteXMPCommand`).
- Modify: `WriteXMPCommand.swift` (replace the inline declarations with `@OptionGroup`; the invocation-request construction reads from the group — help text must stay byte-identical), `NormalizeCommand.swift` (adopt the group; map into the QN1 overrides), the normalization invocation validator (conflicting-pair rejections for the new pairs, mirroring `XMPExportInvocationValidator.rejectConflictingBooleanPairs`).
- Read first: `WriteXMPCommand.swift` fully; ArgumentParser `@OptionGroup` composition in `AssessQualityCommand`.

**Tests.** Existing `XMPExportInvocationTests` stay green (write-xmp behavior unchanged); new normalize-side conflict-rejection tests; a help-surface check is manual (§0 rule 5 verification: `write-xmp --help` diff-clean against the pre-stage output except ordering ArgumentParser forces; `normalize --help` lists the group).

**Review checklist.** No flag renamed, no help text reworded (the S4.9-documented smoke commands must keep parsing); the group is the only declaration site — grep for `customLong("write-flag")` etc. finds exactly one.

**Commit.** `Share the quality-grading flag surface across write-xmp and normalize (QN5)`

### QN6 — Grading at apply-session time

**Goal.** `apply-session` re-grades from **current** sidecar assessments and current XMP when grading is enabled, per D-QN2 — so the GUI's review-then-apply flow can carry quality without a separate pass.

**Files.**
- Modify: `Sources/AISidecarCLI/ApplySessionCommand.swift` (adopt `QualityGradingOptions` + config resolution), `Pipeline/ApplySessionPipeline.swift` (thread the grading block + snapshot reader into its `NormalizedXMPChangePlanner` rebuild; contributor documents must be re-resolved from disk, not from the session).
- Read first: `ApplySessionPipeline.swift` end to end (how it rebuilds plans and what inputs it re-reads), QN3's ledger notes.

**Do.** Reuse the QN1 block and QN2 applier; grading state stored in the session (preview rows from QN3) is ignored in favor of the rebuild. A session whose sidecars have since lost their assessments grades as ungraded-with-reason, never from stale session data.

**Tests.** End-to-end: normalize `--session-only` with grading on → apply-session with grading on writes the full graded output; mutate a quality sidecar between the two steps and assert apply-time values win; sessions created before this plan (fixture) apply cleanly with grading off and on; default-off identity for apply-session.

**Review checklist.** No grading data flows out of the session document into writes; conflict-policy behavior identical to the QN3 path (shared applier only).

**Commit.** `Re-grade at apply-session time from current sidecars (QN6)`

### QN7 — GUI enablement seam (Core-side only)

**Goal.** Everything the app needs is reachable through override structs and config keys, and the binding points are written down so the GUI pass is mechanical.

**Files.**
- Modify: `agent_docs/cli-implementation-notes.md` (a "GUI binding points" subsection) — documentation only, plus any **additive** override-struct gap QN1/QN4 left on the entry points the app calls (`ConfigurationResolver.resolveNormalization(cli:)`, `resolveXMPExport(cli:)`, `resolve(cli:)`); no `Sources/CupricAspectApp` changes (§0 addition 10).
- Read first: `Sources/CupricAspectApp/Features/Normalize/NormalizationModel.swift`, `Features/Export/ExportModel.swift`, `Features/Review/ReviewModel.swift`, `Features/Settings/SettingsModel.swift` — read-only, to verify and document which overrides each constructs.

**Do.** Document, for the future GUI pass: (a) the assess toggle = `RunConfigurationOverrides.qualityAssessment` from the Options step; (b) the grading toggle + channel switches = `QualityGradingConfigurationOverrides` on the normalization/export overrides the models already build; (c) Settings defaults = the existing `xmp_quality_*` keys the Settings sheet writes through `config.json`; (d) result surfaces the Review step can show = plan scalar rows, `quality_explanation`, `wrote_*` progress fields. Verify each claim against the model code and cite file/symbol. If an entry point the app uses cannot accept the overrides, close that gap additively and ledger-note it.

**Commit.** `Document the GUI binding points for quality normalization (QN7 docs)`

### QN8 — Documentation pass

Update: `README.md` (the experimental section's three-step composition and its quality-keyword limitation are replaced by the one-command `normalize --assess-quality --quality-grading` flow; keep the experimental framing), `agent_docs/cli-implementation-notes.md` (normalize/apply-session grading + shared option group), `architecture-map.md` (normalize pipeline row), `testing-and-verification.md` (smoke: a dry-run graded normalize; help checks for the new flags), `aisidecar.config.example.jsonc` (note that `xmp_quality_*` keys now also govern `normalize`/`apply-session`). Docs-only commit: `Document quality-aware normalization (QN8 docs)`.

---

## 4. Acceptance criteria (plan-level)

- **AC-QN-1** `normalize <images> --assess-quality --quality-grading` produces, in one invocation: combined-contract raw sidecars, normalized keyword XMP, verbatim quality keywords, and the full guarded scalar/flag output — verified end to end on temp files.
- **AC-QN-2** A vocabulary/consensus configuration can never rename, drop, or emit a decision about a quality keyword; existing `AI Quality` keywords in targets survive normalization byte-identically.
- **AC-QN-3** With every new flag absent, `normalize`, `apply-session`, and `write-xmp` are byte-identical to pre-plan behavior (sessions, reports, XMP, sidecars).
- **AC-QN-4** Grading semantics (conflict matrix, pair coupling, stamps, preconditions) are provably shared: one implementation, exercised by both planners' test suites.
- **AC-QN-5** Apply-session grading reflects apply-time sidecar/XMP state, never frozen session state.
- **AC-QN-6** The GUI pass that follows needs only: three toggles bound to existing override fields, Settings keys that already exist, and read-only display of plan/report fields — all documented with file/symbol citations.
