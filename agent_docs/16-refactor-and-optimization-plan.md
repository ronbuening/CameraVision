# Refactor, Optimization, and Vision-Backend Abstraction Plan

Version: 1.0
Date: 2026-07-21
Scope: `Sources/AISidecarCore`, `Sources/AISidecarCLI`, `Sources/CupricAspectApp`
Audience: junior engineer or Sonnet-level coding agent executing one work item at a time.

**Scheduling authority.** This plan is the next scheduled code plan. It **absorbs the remaining items of `agent_docs/05-efficiency-improvement-plan.md`** as its Tranche A (by reference — plan 05's item text stays authoritative for those items) and supersedes plan 05's slot in `agent_docs/08-post-review-hardening-plan.md` §1.1 step 7. Order: Tranche A → B → C → D, then M9–M11 per the phase-4 plan. Do not interleave with M9 work.

**Provenance.** Findings come from the 2026-07-21 full-codebase review (five parallel deep reviews: model-runtime coupling, Core pipelines, Normalization/Metadata, GUI, docs) on branch `ronbuening/RefactorAndOptimize` at `379b63e`. File/line anchors were captured that day; expect drift as items land — **file + symbol references remain authoritative** over line numbers. If cited code no longer matches, stop and re-derive from the item's Problem statement; do not force the change in.

## Ground rules (read first)

1. Read `AGENTS.md` and `agent_docs/invariants.md` before starting. All invariants bind every item; the ones this plan trips over most: 1 (analyze never touches XMP), 7 (stable raw strings), 8 (additive schemas), 9 (config precedence; purge independence), 10 (exact-first vocabulary matching), 11 (macOS 15 minimum, macOS-only), 12 (tests deterministic/offline), 13 (Core/CLI/GUI split), 15 (serial Ollama preflight), 21 (derivative-cache protocol), 22 (sequential quality scans never perturb tagging).
2. **One work item per branch/PR.** `swift test` green before and after every item; commit at each passing breakpoint, docs and code in separate commits. If XCTest is missing, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
3. Error messages, artifact JSON field names, schema identifiers, and stdout text must remain byte-identical unless the item explicitly says otherwise. Treat any golden-fixture diff (`GoldenSidecarTests`, report/summary tests, session round-trips) as a stop-and-review signal.
4. Refactors in Tranches B/C must be **observationally transparent**: same bytes on disk, same ordering, same messages. Performance items prove their win against the baseline below.
5. Behavior changes ship with focused unit tests (`AISidecarCoreTests` / `CupricAspectAppTests`); follow `agent_docs/commenting_guide.md` for substantive comments.
6. Plan 05's "Explicit Non-Goals" section still binds (no schema-identifier merges, no Markdown-summary abstraction, no re-parallelized preflight, no cross-process write batching).

## Verification baseline (before Tranche B)

```bash
swift run -c release aisidecar benchmark --self-test
# End-to-end (needs Ollama + a ~50-100 image folder):
time swift run -c release aisidecar analyze <folder> --recursive --mode both --output-dir /tmp/aisidecar-baseline
# Normalization-heavy baseline (exercises B2):
time swift run -c release aisidecar normalize <folder> --recursive --mode both --dry-run
```

Record wall clock for the non-model portions (scan, render, consensus, write, XMP export). Re-run after each B item and record before/after in the PR description.

---

## 1. Execution order at a glance

Work strictly top to bottom inside each tranche. Tranche A first (it shrinks the surfaces B/C touch). Within B and C, items marked ⚡ are independent and may be reordered if a conflict arises; dependency notes are binding.

| Order | Item | Summary |
|---|---|---|
| A1–A10 | Plan-05 remainder | R1, R2, P1, P5, P7, P8, P4, R3, R4, P6 — see Tranche A |
| B1 | CIContext sharing | One renderer/isolation service per analyze batch |
| B2 | Consensus indexing | Kill O(n²) scans in `BatchConsensusEngine` |
| B3 | XMP parse reuse | Stop re-parsing the same sidecar 5–6× per export target |
| B4 | Sidecar handoff | Adapters reuse in-memory sidecars (needs A3/P1) |
| B5 | Parallel scan hashing | Bounded-concurrent `SourceIdentity` at scan time |
| B6 | Review rows cache | Stop recomputing `assetRows` per interaction |
| C1–C5 | Core dedup | Path utils; enum bridge; plan assembler; quality extractor; canonicalizer filter |
| C6–C12 | Core structure | Tolerant-enum helper; resolver/pipeline/file splits; small factories |
| C13–C16 | GUI structure | Core-boundary fixes; flow model; view splits; shared vision-tags model |
| D1–D8 | Backend abstraction | Config, factory, descriptors, GUI, Apple stub, provenance, docs |

---

## Tranche A — absorbed efficiency-plan items (execute from plan 05)

Execute these in plan 05's remaining-work order, using plan 05's item text as the spec. One addition is noted inline. P2/P3 are complete inside R4-6 — do not reschedule them.

| # | Plan-05 item | Note |
|---|---|---|
| A1 | R1 — shared raw-sidecar batch helpers | **Addition:** the two adapters also share a byte-identical `logCleanupWarning(_:error:)` (`AnalyzeAndXMPPipeline.swift` ~:217, `AnalyzeAndNormalizePipeline.swift` ~:265). Fold it into the same `RawSidecarBatchHelpers` extraction. |
| A2 | R2 — shared CLI output helpers | As written. |
| A3 | P1 — eliminate double sidecar write | As written. **Prerequisite for B4.** |
| A4 | P5 — vocabulary fold/lookup memoization | As written. Lands in `CandidateCanonicalizer` — coordinate with C5 (do A4 first; C5 preserves the caches). |
| A5 | P7 — debug-derivative copy once | As written. |
| A6 | P8 — pre-fold species sort | As written. C1 later moves the extracted helper; keep the Schwartzian form. |
| A7 | P4 — progress-log fsync cadence | As written (R1-3 landed long ago; the gate is satisfied). |
| A8 | R3 — report-writer error wrapping | As written. |
| A9 | R4 — `AnalyzeShellPipeline` audit/deletion | As written. Also delete its private subject-isolation copies (see C11) and update `architecture-map.md`. |
| A10 | P6 — affinity edge pruning | Only if profiling after B2 shows the builder still matters. |

---

## Tranche B — performance (new findings)

### B1. Build the renderer and subject-isolation service once per analyze batch

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift` (`prepare`, ~:571-572; `processPendingWork` / `processPendingWorkSequentially`), `Sources/AISidecarCore/Rendering/ImageRenderer.swift` (init ~:55-65), `Sources/AISidecarCore/SubjectIsolation/SubjectIsolationService.swift` (init ~:13-24)

**Problem.** The static per-image `prepare` step constructs a fresh `ImageRenderer(cache:)` and `SubjectIsolationService(cache:maskProvider:)` for **every image**. Each init creates a `CIContext` (Metal/GPU-backed state plus sRGB color-space setup) — ~200 constructions on a 100-image batch, multiplied under `stage_concurrency > 1`. `ModelInputExportPipeline` (~:318-319) already builds both once before its loop, proving there is no design constraint requiring per-image construction.

**Change.** Construct one `ImageRenderer` and one `SubjectIsolationService` in `processPendingWork`/`processPendingWorkSequentially` (they already own the shared `DerivativeCache`) and pass them into `prepare`. Both are structs over a thread-safe `CIContext` + the shared cache; mark them `Sendable` and share across workers. `CIContext` is documented thread-safe for rendering.

**Acceptance.**
- Instruments or a counting seam shows exactly one `CIContext` per pipeline run (a unit test can count `ImageRenderer` constructions via a factory seam if simpler).
- Derivative bytes unchanged (existing golden/derivative tests pass untouched).
- Render-stage wall time drops vs. baseline with `--stage-concurrency 4`; record numbers.

### B2. Index the consensus hot loop in `BatchConsensusEngine`

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Medium (ordering determinism)
- **Files:** `Sources/AISidecarCore/Normalization/BatchConsensusEngine.swift` (`DirectSupportIndex` ~:824-843, `consensusSupportingAssets` ~:726-732, `localPropagationDecisions` ~:466-509), `Sources/AISidecarCore/Normalization/AssetAffinityGraph.swift` (`neighbors(of:minimumAffinity:)` ~:132-145)

**Problem.** The batch-consensus hot loop is O(N·P·(E + nodes)) in practice:
- `DirectSupportIndex.assetsSupporting(_:)` scans every asset's path-set for every supported canonical path;
- `node(_:supports:graph:)`, `exactPathsForNode(_:graph:)`, and `consensusSupportingAssets` each do a linear `graph.nodes.first { $0.nodeID == … }` **inside** the per-target × per-candidate loops;
- `AssetAffinityGraph.neighbors(of:)` re-`compactMap`s the entire edge list on every call, called per target and again per accepted decision;
- `DirectSupportIndex` is rebuilt from scratch four times per run (~:74, :102, :119, :145).

This is the dominant non-model cost of large `normalize` batches. (Plan-05 P6 touches only the graph *builder*; this is the consumption side.)

**Change.** Lookup structures only — no ordering changes:
1. Add `nodeByID: [String: …]` and a precomputed adjacency map (`neighborsByNodeID`) to `AssetAffinityGraph`, built once at init.
2. Invert `assetsSupporting` into a `supportingAssetsByPath: [String: [AssetID]]` map built once in `DirectSupportIndex.init`.
3. Build `DirectSupportIndex` once and reuse (or rebuild incrementally) across the four call sites.

**Acceptance.**
- `AssetAffinityGraphTests`, `AffinityNeighborCandidateTests`, `BatchConsensusEngineTests`, and session golden tests pass **byte-identically** — serialized session documents, decision ordering (`compareDecisions`, `compareLocalConsensus`), and edge ordering unchanged.
- Normalization dry-run baseline on the benchmark folder shows measurable wall-time reduction; record before/after.

### B3. Reuse pre-write XMP parses within one engine invocation

- **Priority:** MEDIUM-HIGH · **Effort:** Medium · **Risk:** Medium (invariant 4)
- **Files:** `Sources/AISidecarCore/Metadata/OwnedXMPSidecarEngine.swift` (`preview` ~:39-41, `apply` ~:81-84, post-write validation ~:132), `Sources/AISidecarCore/Pipeline/XMPExportPipeline.swift` (`previewedChangePlan` ~:303, `executeTarget` ~:347/:399), `Sources/AISidecarCore/Normalization/NormalizedXMPChangePlanner.swift` (`snapshotReader` ~:70)

**Problem.** One written target parses the same `.xmp` with `XMLDocument(…, .nodePreserveAll)` 5–6 times: planner snapshot (grading on), `preview` (twice: snapshot + document-for-write), then `apply` (snapshot + document-for-write), then the post-write validation re-read. The pre-write parses are redundant.

**Change.** Cache the parsed pre-write document/snapshot keyed by `(path, inode, mtime, size)` **within a single engine invocation chain** (plan → preview → apply). Invalidate on write. The post-write validation re-read and the source-hash rechecks stay against fresh on-disk bytes — those are the invariant-4 guard and must not be cached. Do not cache across process or run boundaries.

**Acceptance.**
- `OwnedXMPSidecarEngineTests`, merge-validator round-trips, and all golden change-plan/report tests pass byte-identically.
- Add a counting-parser seam test: a plan+preview+apply sequence on one target parses the pre-write document once; post-write validation still performs a fresh read (assert the count).
- A target mutated externally between preview and apply is still detected (existing hash-recheck tests keep passing; add one if missing).

### B4. Hand written sidecars to the analyze adapters in memory

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (byte-equivalence) · **Depends:** A3 (P1)
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift` (`AnalyzeResult` ~:5-27, `finishPrepared` ~:690), `Sources/AISidecarCore/Pipeline/AnalyzeAndXMPPipeline.swift` (`rawInputBatch` ~:110-162), `Sources/AISidecarCore/Pipeline/AnalyzeAndNormalizePipeline.swift` (`rawInputBatch` ~:158-210) — after A1, the shared helper from `RawSidecarBatchHelpers`

**Problem.** The combined pipelines re-read and re-decode from disk every sidecar `AnalyzePipeline` just wrote — `AnalyzeResult` discards the in-memory document and carries only `ProgressRecord`s. N extra file reads + JSON decodes per combined run.

**Change.** Add an optional `[sidecarPath: RawJSONSidecarDocument]` side channel to `AnalyzeResult`. The shared `rawInputBatch` helper consults it first and falls back to `RawJSONSidecarReader.read` for `skippedExisting` and any missing entry. The in-memory document must be exactly what was written (safe at this stage: the `xmp_export` stamp is added later by Phase 2).

**Acceptance.**
- Add a test asserting the adapter performs zero sidecar file reads for freshly-written entries (counting reader seam) and still reads skipped/pre-existing ones.
- `AnalyzeAndXMPPipelineTests` / `AnalyzeAndNormalizePipelineTests` pass unchanged; downstream XMP/normalization output byte-identical.

### B5. Parallelize scan-time source-identity hashing

- **Priority:** MEDIUM · **Effort:** Small-Medium · **Risk:** Low
- **Files:** `Sources/AISidecarCore/FileScanning/ImageScanner.swift` (`scan` ~:34-59, `sortedScan` ~:61)

**Problem.** `scan` computes SHA-256 (`SourceIdentityCalculator.compute`, default `.sha256` policy) serially, one file at a time, before any concurrent pipeline work starts. Results are sorted afterwards, so ordering is already recomputed — hashing is order-independent.

**Change.** Bounded `TaskGroup` (bound to the existing stage-concurrency setting or `ProcessInfo.activeProcessorCount`, pick one and document it) computing identities concurrently; preserve the per-file `autoreleasepool` memory discipline inside each task; keep error records and the final sorted order identical. `inventory()` stays hash-free (CORE-5).

**Acceptance.**
- `ImageScannerTests` pass; scan output ordering and error records byte-identical.
- Wall-time drop on a large-folder scan recorded before/after.

### B6. Cache derived review rows in the GUI

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Low
- **Files:** `Sources/CupricAspectApp/Features/Review/ReviewModel.swift` (`assetRows` ~:110-164), `Sources/CupricAspectApp/Features/Review/Step5ReviewView.swift` (`LazyVStack` ~:59-64)

**Problem.** `assetRows` is a computed property that rebuilds a dictionary over all `perAssetDecisions`, constructs every `Chip`, and string-sorts — re-executed on **every** verdict toggle because the body observes `verdicts`. O(all decisions) per interaction; fine at the B0-6 1,500-asset measurement, will not hold at the M11 5,000-asset target.

**Change.** Materialize the rows once per session build (keyed by session identity) and apply verdict changes as an overlay (per-row update or a revision-counter-keyed memo). Only the touched row's chip state should be recomputed on a verdict change.

**Acceptance.**
- Existing `ReviewModelTests` pass; add a test that a verdict change does not rebuild unrelated rows (observable via a build-counter seam).
- Manual check per `agent_docs/testing-and-verification.md` GUI smoke: large-session chip toggling stays fluid.

---

## Tranche C — structure and duplication (new findings)

### C1. `Support/PathUtilities` + shared micro-helpers ⚡

- **Priority:** HIGH (breadth) · **Effort:** Small per step · **Risk:** Low
- **Files:** new `Sources/AISidecarCore/Support/PathUtilities.swift`; `Support/Timestamp.swift`; the duplicate definitions below

**Problem.** Identical private utilities are copied across Core:
- `comparePaths(_:_:)` — 8 copies (`XMPExportPipeline` ~:1045, `RawJSONSidecarInputResolver` ~:559, `ImageScanner` ~:405, `NormalizationInputResolver` ~:635, `NormalizedXMPChangePlanner` ~:687, `QualityGradingPlanApplier` ~:412, `SameBaseNameGroupResolver` ~:253, `XMPChangePlan` ~:573)
- `absoluteURL(for:)` — ~11 copies (one real variant: `ArtifactCleanup` ~:298 passes `isDirectory: true`)
- `durationMs(from:to:)` — 6 copies (fold into `Timestamp`)
- `isRegularFile`/`isDirectory` — 6+ copies across two implementations (`fileExists(atPath:isDirectory:)` vs `resourceValues`) — pick one deliberately
- `stableUnique` (3×), frequency-count `reduce(into:)` (2×+), `assignDecisionIDs` (2×: `CandidateCanonicalizer` ~:854, `BatchConsensusEngine` ~:774)
- the `@unchecked Sendable` enumerator-callback accumulator box (`SynchronousScanErrorAccumulator` in `ImageScanner` ~:397, `SynchronousInputFailureAccumulator` in `RawJSONSidecarInputResolver` ~:551) — one generic `Support` type
- display-term ranking duplicates: `ObservedTagVocabulary.preferredDisplayTerm`/`titleCaseWordCount` (~:117-151) vs `CandidateCanonicalizer.preferredSpeciesFallbackDisplayTerm`/`titleCaseWordCount` (~:875-934), and `observedKey` vs `speciesFallbackKey` — move into `VocabularyTextFolder` or a `DisplayTermRanking` helper, carrying A6's Schwartzian form

**Change.** Incremental consolidation, several small PRs, one helper family each. The consolidated `comparePaths` must preserve the exact case-insensitive-then-literal tie-break; goldens pin ordering.

**Acceptance.** Per step: `grep -n` shows exactly one definition; all tests pass byte-identically; tie-break orders unchanged.

### C2. Bridge the skip-reason enums by raw value ⚡

- **Priority:** MEDIUM-HIGH · **Effort:** Small · **Risk:** Low (with the parity test)
- **Files:** `Sources/AISidecarCore/Normalization/CandidateCanonicalizer.swift` (`convert(reason:)` ~:936-993), `Sources/AISidecarCore/Normalization/NormalizedXMPChangePlanner.swift` (`SkippedCandidateReason.init(normalizationReason:)` ~:562-621)

**Problem.** Two hand-maintained 28-case inverse `switch` mappings (~110 lines) between `NormalizationCandidateSkipReason` and `SkippedCandidateReason`, whose cases carry byte-identical raw strings. A one-sided addition is a silent bug.

**Change.** Replace both with `rawValue` bridging behind one shared helper. Add a `CaseIterable` parity unit test asserting every case of each enum round-trips to the other (this replaces the compile-time exhaustiveness the switches provided — the test is mandatory, not optional). Leave `NormalizationDecisionExplainer.text(for:)` alone (legitimate human text).

**Acceptance.** Parity test in place; all normalization/planner tests pass; raw strings untouched (invariant 7).

### C3. Shared `XMPChangePlanAssembler` for the two planners ⚡

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (golden plans)
- **Files:** `Sources/AISidecarCore/Normalization/NormalizedXMPChangePlanner.swift`, `Sources/AISidecarCore/Metadata/XMPChangePlan.swift` (`XMPChangePlanner` ~:349-571)

**Problem.** Phase 2 and Phase 3 plan construction duplicate the `XMPChangePlan` scaffold: `BackupPlan`, `ValidationPlan.phase2Default`, `sourceMemberPlan`, `skipReason(pairScope:)` (~:483-492 vs ~:525-534), `distinctQualitySidecarPath` (~:360-368 vs ~:536-543), per-bag keyword merge, and the identical `QualityGradingPlanApplier().apply(to:&plan,…)` wiring. They drift independently; the grading wiring is copied verbatim.

**Change.** Extract a Core `XMPChangePlanAssembler` owning the shared scaffold + grading wiring; share the small statics. Both planners call it; plan assembly only — the owned-engine write chain (invariant 4) is untouched.

**Acceptance.** Emitted change-plan JSON byte-identical for both phases (golden change-plan tests); D-QN1 ("one grading implementation") is strengthened, not forked.

### C4. Quality-extraction batch entry point + audit-trail fixes ⚡

- **Priority:** MEDIUM · **Effort:** Small-Medium · **Risk:** Low-Medium (golden explanations)
- **Files:** `Sources/AISidecarCore/Metadata/QualityGradingPlanApplier.swift` (`qualityAssessments` ~:148-194), `Sources/AISidecarCore/Metadata/QualityAssessmentExtractor.swift` (`extract` ~:117-167, `requiresAssessment` gate ~:136)

**Problem.** Three related defects introduced by the fast quality rollout:
1. The applier re-implements the extractor's newest-by-role selection, synthesizing a throwaway `ResolvedRawSidecarInput` per contributor to call `extract` at the wrong granularity — two copies of the createdAt/path tie-break that must agree.
2. Overlapping primary/quality documents can contribute the same malformed-block issue **twice** (issues are not deduped).
3. A *present-but-malformed* `quality_assessment` block in a tagging-profile sidecar is silently dropped (no `malformedBlock` issue) because of the `requiresAssessment` gate.

**Change.** Give `QualityAssessmentExtractor` a batch entry point taking all contributor documents and returning merged `recordsByRole` + **deduped** issues (`QualityExtractionIssue` is `Equatable`); the applier calls it directly. Rework the gate so an *absent* block under the tagging profile stays silent (invariant 22 — no new bytes for plain tagging runs) but a *present-and-malformed* block is always flagged.

**Acceptance.**
- One implementation of newest-by-role (grep proves it); tie-break identical; `quality_explanation` golden strings unchanged for well-formed inputs.
- New tests: duplicated malformed block reports one issue; malformed block under tagging profile reports an issue; plain tagging run without a block byte-identical to before.

### C5. Unify the candidate-filter loop in `CandidateCanonicalizer` ⚡

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (invariant 10, golden skips) · **Depends:** A4
- **Files:** `Sources/AISidecarCore/Normalization/CandidateCanonicalizer.swift` (`observedTagsResult` ~:150-240, `vocabularyResult` ~:242-405)

**Problem.** The two result methods share an almost identical ~90-line inner loop (assetID guard → observation guard → `emptyAfterNormalization` → hierarchy-separator check → confidence threshold → blocking-reason skip → `entry(matching:)` → accumulator/duplicate handling); `vocabularyResult` adds only the species-fallback branch (~:300-338).

**Change.** Extract one shared candidate-filter pipeline (function or small struct) both methods call, with the species-fallback branch as the single divergence point. Preserve A4's fold/lookup caches. Fold the double `entry(matching:)` lookup in the static `preflightSessionContext` (~:82/:93) into one while here.

**Acceptance.** `CandidateCanonicalizerTests` pass unchanged (observationally identical, including skip ordering and invariant-10 exact-first semantics); the filter sequence exists exactly once.

### C6. Promote the schema-evolution tolerant-enum machinery ⚡

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (invariant 8 fail-closed semantics)
- **Files:** `Sources/AISidecarCore/Normalization/NormalizationSessionDocument.swift` (`TolerantStringEnum` ~:384-415; six per-field decode/encode blocks ~:561-777), new `Sources/AISidecarCore/Support/ForwardCompatEnum.swift`

**Problem.** Six fields each repeat ~30 lines of tolerant decode → known/unknown split → `forwardCompatUnknownX` storage → subtle fail-closed re-encode (~:690-700, :755-774). This is the project's schema-evolution primitive, living as a private one-off; every future tolerant field copies the pattern by hand.

**Change.** Promote to an internal `Support` type (property wrapper or `ForwardCompatEnum<Value>` box) owning the known/unknown split and original-raw preservation, collapsing each field to one declaration. Both directions of invariant 8 must hold: unknown raw JSON round-trips byte-identically, unknown decisions stay failed-closed, and `forwardCompatOriginalSkipReasonOrder` ordering is preserved.

**Acceptance.** `NormalizationSessionDocumentTests` and golden session round-trip tests pass byte-identically, including the unknown-enum fixtures; a new focused test covers the helper directly. While here, optionally split the ~15 Codable model structs from the reader/writer for navigability (mechanical, separate commit).

### C7. Split `ConfigurationResolver.swift` (1,316 lines) by config domain ⚡

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Low-Medium (message strings)
- **Files:** `Sources/AISidecarCore/Configuration/ConfigurationResolver.swift` → new `ConfigFileLoader.swift`, `ConfigValueParsing.swift`, and one `…+Resolve.swift` per domain (run, XMP export, normalization, apply-session, quality grading)

**Problem.** Five separable responsibilities in one file: config-file loading (two near-identical loaders ~:195-251), scalar parsing (~:581-647), per-domain env extractors (~:253-579), per-domain builders (~:682-1197), `withoutConfigPath()` extensions (~:1199-1316).

**Change.** Mechanical relocation: one generic `loadConfigFile<T: Decodable>`, shared scalar parsing, then one file per domain hosting that domain's extractor + builder + `withoutConfigPath`. **Move, don't reword:** all `configInvalid` message strings are test-asserted. `resolveDerivativeCache`'s independence (invariant 9 / purge) keeps its own path.

**Acceptance.** All configuration tests pass unchanged; `swift test` green; no public API change; each new file ≤ ~300 lines.

### C8. Extract the export-stamp synchronizer and source-hash verifier from `XMPExportPipeline` ⚡

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (stamp semantics)
- **Files:** `Sources/AISidecarCore/Pipeline/XMPExportPipeline.swift` (~190 lines: `stampSourceSidecars` ~:729, `selectedContributorSidecarPaths` ~:825, `trustedPriorStampOwnership` ~:836, `commonOptionalValue` ~:872, `ownedStampedScalar` ~:879, `stampSemanticallyMatches` ~:900, `PriorStampOwnership` ~:1020-1043; hash unit: `sourceHashesBeforeWrite` ~:466, `sourceHashChecks` ~:479, `selectedSourcePaths` ~:545)

**Problem.** The write-orchestration core is buried under two separable concerns: the FR4-049 stamp synchronizer and the source-hash integrity checks.

**Change.** Extract `RawSidecarExportStampSynchronizer` (Sidecars/ or Metadata/ — beside `RawSidecarExportStamp`) and a hash-verification helper beside `SourceIdentityCalculator`. The pipeline calls one method each. Message strings and stamp equality/ownership semantics byte-identical.

**Acceptance.** Stamp and export golden tests pass unchanged; both units gain focused direct tests; `XMPExportPipeline.swift` drops below ~700 lines.

### C9. Split `ModelInputExportPipeline.swift` models/naming ⚡

- **Priority:** LOW-MEDIUM · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Pipeline/ModelInputExportPipeline.swift` → `ModelInputExportModels.swift` (~:22-252 Codable types), `ModelInputExportNaming.swift` (~:721-860)

Pure mechanical move; `"ai-sidecar-model-input-export/1.0"` and all `CodingKeys` stay put; diagnostic-only invariant 5 unaffected. Also fold the duplicated `DerivativeFormat.fileExtension` (`DerivativeCache` ~:620 vs `ModelInputExportPipeline` ~:863) into one internal extension in `Rendering/`.

### C10. Relocate sidecar kind/pairing logic into `SidecarNaming` ⚡

- **Priority:** LOW-MEDIUM · **Effort:** Small-Medium · **Risk:** Low-Medium (invariant 7 artifact names)
- **Files:** `Sources/AISidecarCore/Sidecars/RawJSONSidecarInputResolver.swift` (`sidecarKind` ~:493, `siblingSidecarURL` ~:426, `siblingSourceURL` ~:421, `sidecarBaseFileName` ~:479, `sidecarPairingKey` ~:473), `Sources/AISidecarCore/Sidecars/SidecarNaming.swift`

These functions cohere with `SidecarNaming`'s suffix constants, not the resolver. Relocation also removes the reach-through where adapters instantiate a whole resolver to call `groupedSidecarInputs`. Suffix/pairing behavior byte-identical; resolver tests pass unchanged. **Do before C13** (the Core queue-state deriver reuses these).

### C11. Shared subject-isolation factories ⚡

- **Priority:** LOW · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift` (`failedSubjectIsolationRecord` ~:992, `subjectIsolationError` ~:968, `PipelineUnavailableForegroundMaskProvider` ~:1068), `Sources/AISidecarCore/Pipeline/ModelInputExportPipeline.swift` (~:628-640, `ExportUnavailableForegroundMaskProvider` ~:873), `Sources/AISidecarCore/SubjectIsolation/`

One `ForegroundMaskProvider.makeDefault()` factory + one failed-record factory in the SubjectIsolation domain replaces the per-pipeline copies and both throwaway provider structs. Error strings (`"Apple Vision foreground masking requires macOS 15 or newer."`, `"Unable to isolate subject: …"`) byte-identical. Sequence after A9 (which deletes the third copy).

### C12. `ResolvedXMPExportConfiguration` translators ⚡

- **Priority:** LOW · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzeAndNormalizePipeline.swift` ~:286, `ApplySessionPipeline.swift` ~:554, `NormalizePipeline.swift` ~:441, `NormalizeAndWritePipeline.swift` ~:102

Four hand-assembled ≈15-field constructions. Add named translator inits (`init(from: ResolvedNormalizationConfiguration…)`, `init(from: ResolvedApplySessionConfiguration…)`) so a new export field is mapped in one place. Field values identical; pipeline tests unchanged.

### C13. Move GUI-resident sidecar interpretation into Core (invariant 13)

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Low-Medium · **Depends:** C10
- **Files:** `Sources/CupricAspectApp/Features/Import/AssetQueue.swift` (`AssetQueueDerivation` ~:67-145: `rawSidecarPath`, `xmpTargetPath`, `replacingExtensionWithXMP`, `hasXMPExportBlock` + `XMPExportProbe` ~:104-123), `Sources/CupricAspectApp/Features/Preview/AssetPreview.swift` (`AssetPreviewDetails.load` ~:26-73), `Sources/CupricAspectApp/Features/Review/ReviewModel.swift` (nonisolated statics `loadQualityExtraction` ~:379-402, `qualityPresentation` ~:289-335), new Core files under `Sidecars/`/`Metadata/`

**Problem.** The GUI reimplements Core naming rules and hand-decodes sidecar/`xmp_export` structure — the comment in `AssetQueue` literally says "Mirrors Core's naming rules." Invariant 13 reserves interpretation for Core; any Core naming/schema change silently drifts the GUI derivation. M10's database mode would otherwise re-derive these states a third way. The probe also reads whole files to answer one key.

**Change.** Three Core additions the GUI calls instead:
1. `QueueStateDeriver` (Core) returning a `Sendable` queue state per (source, outputDir) using `SidecarNaming`/`XMPNaming` and a targeted `xmp_export` probe (decode only the stamp block, not the whole document).
2. A Core presentation loader for preview details (wraps `RawJSONSidecarReader` + interprets `modelRuns`/`subjectIsolation`/`derivatives`/`errors` into a `Sendable` presentation struct).
3. `ReviewQualityLoader` (Core) absorbing the resolver/extractor orchestration the `ReviewModel` statics do today.

**Acceptance.** GUI targets contain no direct `RawJSONSidecar` decoding and no sidecar-path construction (grep proves it); `FolderImportModel.rescan` uses the targeted probe; existing GUI model tests pass with the new seams; new Core unit tests cover the three loaders.

### C14. Extract a shell-agnostic wizard flow coordinator (pre-M9 requirement)

- **Priority:** HIGH · **Effort:** Medium-Large · **Risk:** Medium
- **Files:** `Sources/CupricAspectApp/Shells/WizardShellView.swift` (686 lines) → new `Shells/WizardFlowModel.swift` (or `Features/` if more natural)

**Problem.** The Wizard shell owns 7 feature models plus the entire inter-model state machine: the three `onChange` phase routers (~:85-148), `startExport` action routing (~:350-378), `reportStartExportError`, `rehydrateImportContextFromReviewSession`, `effectiveQualityGradingOverrides`, `startRun`/`finishCleanly`/`requestFinish` (~:570-615). AGENTS.md says shells are chrome only and both shells must embed the same feature state (FR4-041) — as-is, M9's Studio shell must duplicate or diverge from this logic.

**Change.** Extract a shell-agnostic `@Observable` flow coordinator owning the model set, phase-transition routing, and the run/export entry points; `WizardShellView` becomes chrome that renders steps and forwards intents. Symbols to move are exactly the list above. Also fix the stale `showAbout` naming (~:22 — it presents Settings).

**Acceptance.** All existing GUI model tests pass; new `WizardFlowModelTests` cover the phase-routing transitions previously untestable inside the view; `WizardShellView` drops to chrome (< ~350 lines); no behavior change in the manual wizard smoke pass.

### C15. GUI view-file splits ⚡

- **Priority:** MEDIUM · **Effort:** Small-Medium each · **Risk:** Low
- **Files/symbols:**
  - `SettingsSheet.swift` (737) → `SettingsModelSection`, `SettingsConfigurationSection` (~:245-434), `SettingsQualityGradingSection` (~:436-520), `SettingsAppearanceSection`/`SettingsAboutSection` (~:533-661), shared `SettingsControls` (card/sectionLabel/settingRow/settingsStepButton ~:70-84, :663-736)
  - `Step3OptionsView.swift` (582) → `RunModelPickerCard` (~:138-343), `AdvancedOptionsCard` (~:346-455), `QualityGradingOptionsCard` (~:165-214); move the `ScalarConflictPolicy.wizardLabel`/`QualityScanMode.wizardLabel` extensions (~:563-582) to a shared labels file
  - `Step5ReviewView.swift` (480) → `FlowLayout` (~:441-480) into `DesignSystem/`, `RowThumbnail` (~:406-438) into `Features/Preview/`, `ReviewQualityPanel` (~:255-311)
  - `ChangePlanSheet.swift` (445) → `ExportReportView` (from ~:327) into its own file; deduplicate the two `qualityBadge` helpers
  - `AnalysisRunModel.swift` → `AnalysisOptions` into its own file (four types currently share the file)

Mechanical; no behavior change; do after C14 and D4 to avoid churn (they edit the same files).

### C16. One shared vision-tags model (prereq for Tranche D GUI work)

- **Priority:** MEDIUM-HIGH · **Effort:** Small-Medium · **Risk:** Low
- **Files:** `Sources/CupricAspectApp/Features/Settings/SettingsModel.swift` (`refreshVisionTags` ~:172-187, `VisionTagLoader` ~:13-17), `Features/Run/Step3OptionsView.swift` (own `@State visionTags`/`refreshVisionTags` ~:19-20, :534-557), `Features/Run/RuntimeGuidanceModel.swift` (`check` ~:59-88)

**Problem.** The "list tags → map to state" logic exists three times with three endpoint round-trips at launch and two copies of the enum mapping.

**Change.** One shared `@Observable` model owning discovery state (loading/loaded/error), consumed by Settings, Step 3, and runtime guidance. This is deliberately the seam D4 makes backend-aware — build it Ollama-only first, identical behavior.

**Acceptance.** One implementation (grep); Settings and Step 3 show consistent state; `RuntimeGuidanceModelTests`/`SettingsModelTests` pass with the injected loader seam preserved.

---

## Tranche D — vision-backend abstraction and Apple FoundationModels readiness

**Goal.** Introduce first-class *model backend* selection so a second `VisionModelRunner` — Apple's on-device FoundationModels — can slot in beside Ollama, selected per run, with Ollama as the fallback for older macOS and for anything the Apple model can't do. This tranche lands the full abstraction plus a compile-gated Apple adapter skeleton that reports **unavailable** until a vision-capable FoundationModels API exists (anticipated macOS 27). No live Apple inference is implemented in this plan.

**Hard facts this design is built on (verified 2026-07-21).**
- The `VisionModelRunner` protocol (`ModelRuntime/VisionModelRunner.swift`) and the provenance types (`ModelRunRecord`, `RawJSONSidecar`) are backend-neutral; `PromptRegistry`, `ResponseSchemas`, `JSONSchemaValidator`, `ModelInputContext`, and `ModelTaskProfile` are reusable as-is. `OllamaWireSchema` is Ollama-private.
- FoundationModels (macOS 26) has **no public image-input API**; `SystemLanguageModel` sessions are text-only. A vision adapter therefore cannot be functional today.
- CI pins Xcode 26.3 (macOS 26 SDK): `#if canImport(FoundationModels)` + `#available(macOS 26, *)` code compiles in CI. The maintainer's dev machine runs macOS 15.6: Apple-path code can be compiled and mock-tested but **not executed live** — every D-stage test must be offline and availability-independent (invariant 12).
- macOS 15 stays the minimum (invariant 11). Availability-gating newer-macOS code inside the macOS-only target does not broaden platform support and does not violate invariant 11.
- Golden fixtures pin `"runtime":"ollama"`, `"model_digest":"sha256:…"`, and the exact `run_configuration` bytes — all backend additions must be **additive and default-elided** (the invariant-22 `quality_scan_mode` pattern).

### Design decisions (record deviations in the ledger)

- **DD-1 — One new config axis: `model_backend`.** Values `"ollama"` (default) | `"apple"` | `"auto"`. Config key `model_backend`, env `AISIDECAR_MODEL_BACKEND`, CLI `--model-backend` on exactly the commands that accept `--model` (analyze, assess-quality, the analyze shapes of write-xmp/normalize, benchmark — see DD-8). Standard precedence chain (invariant 9). `purge` never resolves it.
- **DD-2 — Per-run selection, never per-image.** A backend preflight resolves the backend **once per run**: `apple` and `ollama` pins fail closed with a clear error when unavailable; `auto` prefers Apple when its descriptor reports available-and-vision-capable, else Ollama. No mid-batch mixing — one `runtime` string per batch keeps sidecar provenance, consensus inputs, and benchmark aggregation uniform. Fallback happens between runs (auto), not inside one.
- **DD-3 — Provenance is additive and default-elided.** `ResolvedRunConfiguration` gains optional `model_backend`, encoded **only when ≠ `"ollama"`** so every existing sidecar byte-pattern is preserved (mirror of invariant 22's encoding rule). The Apple runner records `runtime: "apple-foundation-models"`, `runtimeVersion:` the macOS product version, `model: "system-language-model"`, and `modelDigest: "system:<os build string>"` (no `sha256:` prefix — the prefix stays an Ollama-ism; `modelDigest` is already a free-form string in the schema). These raw strings become load-bearing the day they first ship — choose once, never rename (invariant 7).
- **DD-4 — Backend descriptors are the GUI/CLI-facing abstraction.** New Core protocol (working name `VisionBackendDescriptor`): `id`, `displayName`, `availability() async -> BackendAvailability` (`.available` | `.unavailable(reason: String, guidance: BackendGuidance)`), `discoverModels(configuration:) async throws -> [BackendModelChoice]`, `makeRunner() -> any VisionModelRunner`, `supportedTuningKnobs: Set<ModelTuningKnob>` (`contextWindow`, `keepAlive`, `maxResponseTokens`, `temperature`, `timeout`, `retryLimit`). `BackendGuidance` carries the remediation copy the GUI shows today as hardcoded Ollama strings (download URL, serve/pull commands) — Ollama's descriptor returns exactly the current strings; Apple's returns availability-based copy. A tiny registry (`VisionBackendRegistry`) lists compiled-in backends in deterministic order.
- **DD-5 — Runner selection is a Core factory.** `VisionModelRunnerFactory.make(for: ResolvedRunConfiguration) throws -> any VisionModelRunner` (+ `resolveBackend` for auto). The `= OllamaVisionRunner()` default parameters on the four pipelines are **removed** (pipelines keep the injected-runner parameter, non-defaulted, so tests keep their seams); CLI commands and the GUI call the factory. The Ollama capability preflight inside `prepare` stays serial (invariant 15).
- **DD-6 — `ModelRunOptions` stays one struct.** Backend-inapplicable knobs (e.g. `keepAlive`, `contextWindow` for Apple) are documented as ignored by that backend and recorded in provenance exactly as resolved today — no schema fork. The descriptor's `supportedTuningKnobs` drives which controls the GUI shows; CLI flags for inapplicable knobs are accepted and ignored with a logged notice (not an error), preserving script compatibility.
- **DD-7 — Structured output stays authoritative-schema-validated.** Whatever constrained-decoding bridge the Apple API eventually offers, the adapter must satisfy `JSONSchemaValidator.validate` against the bundled authoritative schemas, exactly as Ollama responses do. `OllamaWireSchema` remains inside the Ollama runner. The repair-prompt loop is runner-internal; the Apple adapter may reuse or replace it when implemented.
- **DD-8 — Additive error codes; benchmark guard.** New `SidecarError` codes: `E_MODEL_BACKEND_UNAVAILABLE` (pinned/auto-resolved backend not usable; message carries the descriptor's reason) and, reserved for the live adapter, `E_MODEL_BACKEND_CAPABILITY` (backend cannot satisfy the requested task profile). Existing codes untouched. `benchmark` accepts `--model-backend` but errors cleanly on anything except `ollama` for now (its axes — keep_alive, `ollama --version` metadata — are Ollama-shaped; extending it is future work, DD-noted, not silent).
- **DD-9 — GUI shows backends honestly.** Settings gains a backend picker listing every registered descriptor with availability annotation ("Apple on-device — unavailable: requires a vision-capable Apple Intelligence model (expected in a future macOS release)"). Runtime guidance, preflight badges, and Step-3 model UI render from descriptor data instead of hardcoded Ollama strings. Copy that is genuinely Ollama-specific moves into the Ollama descriptor; neutral surfaces (e.g. Step 1's "Everything runs locally through Ollama") become backend-neutral ("Everything runs locally on your Mac").
- **DD-10 — The Apple adapter ships dark.** `AppleFoundationModelsDescriptor` always compiles (so the picker can show it, and so the registry/factory paths are exercised in CI); the parts referencing the framework sit behind `#if canImport(FoundationModels)` + `#available(macOS 26, *)`. Its `availability()` returns `.unavailable` with the vision-capability reason on **every** current OS — including macOS 26 — because the text-only API cannot run this workload. Lighting it up later means: implement `analyze` against the future image-input API, flip the availability probe to interrogate the real model, add the live-gated smoke test. Nothing else in the codebase should need to change — that is this tranche's acceptance bar.

### D1. Config plumbing for `model_backend`

- **Files:** `Configuration/RunConfiguration.swift` (+`Overrides`), `Configuration/ResolvedRunConfiguration` (additive optional field, default-elided encoding per DD-3), `Configuration/AppConfig.swift`, `Configuration/ConfigurationResolver.swift` (after C7: the run-domain resolve file), `AISidecarCLI/SharedOptions.swift` + `NormalizeCommand` model-option group, `aisidecar.config.example.jsonc`
- **Change:** the key, env var, CLI flag, precedence, validation (`ollama`|`apple`|`auto` only; anything else → `configInvalid` with the standard message shape). No consumer yet — resolved value is carried but unused.
- **Acceptance:** config precedence tests for the new key at every level; **golden sidecar fixtures pass untouched** (proves default elision); `--help` snapshot updated deliberately.

### D2. `VisionBackendRegistry` + descriptor protocol + Ollama descriptor

- **Files:** new `ModelRuntime/VisionBackendDescriptor.swift`, `ModelRuntime/VisionBackendRegistry.swift`, `ModelRuntime/OllamaBackendDescriptor.swift` (wraps `OllamaVisionRunner.listInstalledVisionTags`, existing endpoint semantics, and the current guidance strings verbatim)
- **Acceptance:** descriptor unit tests (availability mapping from transport errors, model discovery passthrough, tuning-knob set matches today's exposed controls); no call-site changes yet.

### D3. `VisionModelRunnerFactory` + remove hardcoded runner defaults

- **Files:** new `ModelRuntime/VisionModelRunnerFactory.swift`; `Pipeline/AnalyzePipeline.swift`, `QualityAssessPipeline.swift`, `AnalyzeAndXMPPipeline.swift`, `AnalyzeAndNormalizePipeline.swift` (drop `= OllamaVisionRunner()` defaults); `AISidecarCLI/AnalyzeCommand.swift` ~:89, `AssessQualityCommand.swift` ~:22 (call the factory); GUI `AnalysisRunModel` ~:202/:248 (factory + descriptor)
- **Change:** factory resolves DD-2 semantics: pin → that descriptor (unavailable ⇒ `E_MODEL_BACKEND_UNAVAILABLE` before any model work); auto → first available-and-capable in registry order (Apple, then Ollama), which today always resolves Ollama.
- **Acceptance:** selection-matrix unit tests (pin-available, pin-unavailable, auto-with/without-apple via fake descriptors); every `OllamaVisionRunner()` literal outside the Ollama descriptor/factory and its own tests is gone (grep); behavior with defaults (`model_backend` absent) byte-identical end to end.

### D4. Backend-aware GUI

- **Depends:** C16 (shared vision-tags model), D2/D3
- **Files:** `Features/Settings/SettingsModel.swift`/`SettingsSheet.swift` (backend picker + write-through of `model_backend`; model-discovery section renders per selected descriptor), `Features/Run/RuntimeGuidanceModel.swift`/`RuntimeGuidanceBanner.swift` (guidance from `BackendGuidance`), `Features/Run/AnalysisRunModel.swift` (`PreflightState` carries backend id + display name; `guidance(for:)` routes through the descriptor), `Features/Run/Step3OptionsView.swift` (tuning controls filtered by `supportedTuningKnobs`), `Features/Import/Step1PhotosView.swift` (neutral copy), `Support/ModelTuning.swift` (knob metadata annotated per DD-6)
- **Acceptance:** with only Ollama available the GUI is behavior-identical (strings included, except the two copy changes DD-9 names — list them in the PR); a fake second descriptor in tests drives the picker, availability badge, guidance switching, and knob filtering; `RuntimeGuidanceModelTests`/`SettingsModelTests` extended accordingly.

### D5. Apple FoundationModels adapter skeleton (dark)

- **Files:** new `ModelRuntime/AppleFoundationModels/AppleFoundationModelsDescriptor.swift` (+ a stub `AppleFoundationModelsRunner` that fails `prepare` with `E_MODEL_BACKEND_UNAVAILABLE` — it is unreachable through the factory while unavailable, but must be safe anyway)
- **Change:** per DD-10. The descriptor's availability text states the real constraint: requires a vision-capable Apple on-device model; not provided by current macOS/FoundationModels; expected in a future macOS release. Provenance constants per DD-3 live here from day one.
- **Acceptance:** compiles on CI (Xcode 26.3) **and** under a macOS-15-SDK-only toolchain (the `canImport` guard covers it — verify with the release build script); registry lists it; picker shows it unavailable; `auto` never selects it; all tests offline (invariant 12) and passing on macOS 15.

### D6. Provenance goldens for a second backend

- **Files:** `Tests/AISidecarCoreTests/Fixtures/golden-sidecars/` (+ one new fixture generated through `RecordedFixtureRunner` with `runtime: "apple-foundation-models"`, `model_backend: "apple"`), `GoldenSidecarTests.swift`
- **Change:** pin the additive encoding now, before any live adapter exists: the new fixture proves `model_backend` encodes exactly when non-default and that a non-Ollama `ModelRunRecord` round-trips; existing fixtures prove old bytes never change.
- **Acceptance:** both golden suites green; a deliberate-sabotage check (temporarily set default encoding on, observe old-fixture failure, revert) is performed and noted in the PR.

### D7. Backend documentation pass

- **Files:** `AGENTS.md` (Project Context + architecture rules sentence on backends), `agent_docs/architecture-map.md` (ModelRuntime row: registry/factory/descriptors; GUI rows), `agent_docs/cli-implementation-notes.md` (backend selection semantics, DD ledger pointer), `agent_docs/01-cli-raw-json-sidecar-requirements.md` (additive provenance note), `README.md` (a short "Model backends" section: Ollama today, Apple on-device planned, auto semantics), `aisidecar.config.example.jsonc`
- **Acceptance:** docs match shipped behavior; no doc promises live Apple inference.

### D8. (Deferred — explicitly out of scope) Live Apple adapter

Implementing `analyze` against a vision-capable FoundationModels API, the schema→guided-generation bridge (DD-7), capability probing of the real model, benchmark support, and live smoke evidence are a **future plan**, unblocked only when the API exists and a macOS-26+/27 test machine is available. Record the trigger in the ledger when known. Do not start it from this plan.

---

## Non-goals

- No live Apple model inference, no speculative use of private/undocumented API, no macOS-minimum bump, no third executable, no new XMP write path.
- Plan 05's non-goals all still stand.
- No GUI feature work here — that is plan 17 (`agent_docs/17-gui-improvements-plan.md`).
- Do not extend `benchmark` beyond the DD-8 guard in this plan.

## Plan-level acceptance criteria

- **AC16-1** Every tranche-A/B/C item leaves all artifact bytes, message strings, orderings, and schema identifiers unchanged unless its text says otherwise; `swift test` green throughout.
- **AC16-2** After Tranche B, the recorded baselines show measurable non-model wall-time reductions for: analyze render stage (B1), normalize consensus (B2), XMP export per-target (B3), combined-run sidecar handling (B4), scan (B5).
- **AC16-3** After Tranche C, the GUI contains no sidecar-schema interpretation or artifact-path construction (C13), and the wizard flow logic is shell-agnostic and unit-tested (C14).
- **AC16-4** After Tranche D, `model_backend` absent ⇒ byte-identical behavior everywhere; a fake second backend can be selected, preflighted, refused, and surfaced in the GUI purely through the descriptor seam; the Apple descriptor ships dark; goldens pin the additive provenance.
- **AC16-5** Lighting up a real Apple adapter later requires touching only `ModelRuntime/AppleFoundationModels/` (+ its tests/evidence) — verified by a written walkthrough in the D7 docs pass.

## Stage ledger (update as items land; record deviations here)

| Item | State | Date | Notes |
|---|---|---|---|
| A1 | complete | 2026-07-21 | Shared raw-sidecar batch helpers, including cleanup-warning logging; focused and full suites green. |
| A2 | complete | 2026-07-21 | Shared CLI flag/output helpers; dry-run stdout byte-identical; focused and full suites green. |
| A3–A9 | pending | | plan-05 text authoritative |
| A10 | deferred | 2026-07-21 | Maintainer direction: defer until the explicit post-B2 profiling gate can be evaluated. |
| B1–B6 | pending | | |
| C1–C16 | pending | | |
| D1–D7 | pending | | |
| D8 | blocked | | awaits vision-capable FoundationModels API + test hardware |
