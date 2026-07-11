# Efficiency Improvement Plan

Version: 1.0
Date: 2026-07-06
Scope: `Sources/AISidecarCore`, `Sources/AISidecarCLI`
Audience: junior engineer or Sonnet-level coding agent executing one work item at a time.

This plan covers two tracks: **performance** (P items — remove wasted runtime work) and **reusability** (R items — eliminate duplicated code). Every item is self-contained: files, exact problem, exact change, acceptance criteria.

**Scheduling:** this plan runs in its slot in `agent_docs/08-post-review-hardening-plan.md` §1.1 (after R4, before M9) — it is not a parallel active track. Two items are pinned there: P2/P3 execute *as part of* plan-08 R4-6 (one `DerivativeCache` manifest redesign, not two), and P4 must wait until plan-08 R1-3 has landed (it rewrites the same `JSONLWriter` lines). File/line anchors below were captured 2026-07-06; expect line drift after plan-08 items touch `JSONLWriter.swift` and `AnalyzePipeline.swift` — the file + symbol references remain authoritative.

## Ground Rules (read first)

1. Read `AGENTS.md` before starting. The invariants there are binding — especially: stable raw string values for public enums and error codes, the analyze/no-XMP invariant, and config precedence.
2. **One work item per branch/PR.** Do not combine items.
3. Run `swift test` before and after every item. All tests must pass. If XCTest is missing, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
4. Error messages, artifact JSON field names, and schema identifier strings must remain byte-identical unless the item explicitly says otherwise. Golden fixture tests (`GoldenSidecarTests`, report/summary tests) enforce much of this; treat any golden-test diff as a stop-and-review signal.
5. Add or update focused unit tests with each behavior change (AGENTS.md requirement).
6. Context that must not be re-litigated:
   - Commits `679c76a`, `db57b2d`, `9ec1b5a` already consolidated JSON coding, timestamps, progress logs, config precedence, atomic writes, artifact names, and invocation validators, and de-quadraticized the affinity graph. Do not redo or unwind that work.
   - Commit `a1366b6` deliberately **reverted** parallel Ollama capability preflight back to serial. Do not re-parallelize the preflight.
   - `JSONLWriter` reuses one `JSONEncoder` per log (no per-record encoder allocation) — already efficient.

## Verification Baseline

Before starting any P item, capture a baseline so improvements are measurable:

```bash
swift run -c release aisidecar benchmark --self-test
swift run -c release aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir /tmp/aisidecar-bench
# End-to-end (needs Ollama + a test image folder of ~50-100 images):
time swift run -c release aisidecar analyze <folder> --recursive --mode both --output-dir /tmp/aisidecar-baseline
```

Record wall-clock time and, if available, `fs_usage` sync counts. Repeat after the change on the same inputs. Model inference dominates wall clock; evaluate P items by the non-model portion (render, hash, write, log).

---

## Tier 1 — Performance: per-image costs in the batch loop

### P1. Eliminate the double sidecar write per image

- **Priority:** HIGH · **Effort:** Small · **Risk:** Medium (artifact semantics)
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:597-609`

**Problem.** Every successfully analyzed image writes its `.ai.json` sidecar **twice**: once to disk, then again with `existingPolicy: .overwrite` solely to patch `timing.writeMs` and `timing.pipelineElapsedMs` into the document. That doubles JSON encoding, temp-file creation, and renames for every image in a batch (verified at lines 599-608).

**Change (Option A, recommended).** Write once. Set `timing.pipelineElapsedMs` immediately before the single write, and record the measured write duration in the per-image `ProgressRecord`/logs rather than inside the sidecar. Set `timing.writeMs` to `0` in the sidecar (the field stays for schema stability).

**Prerequisite check.** Grep `agent_docs/01-cli-raw-json-sidecar-requirements.md` and `agent_docs/archive/phase-1-cli-implementation-plan.md` for `writeMs` / timing requirements. If a requirement mandates an accurate in-sidecar `writeMs`, use **Option B** instead: keep the second write but gate it behind a new resolved-config flag (e.g. `precise_write_timing`, default `false`), following the existing config precedence chain. Option B touches `RunConfiguration`/`ConfigurationResolver` and needs config tests.

**Steps (Option A).**
1. In `AnalyzePipeline` (the `.prepared` case around line 569): set `pipelineElapsedMs` just before the write; delete the `if outcome.status == .written` re-write block.
2. Keep measuring `writeMs` locally and thread it into the log record for the image (see `logRecord(for:)` usage) if a natural slot exists; otherwise drop the measurement.
3. Update golden fixtures/tests that assert non-zero `writeMs`.
4. Check the failure-path writer (`writeFailureSidecar`) for the same pattern and apply the same treatment if present.

**Acceptance criteria.**
- Exactly one `writer.write` call per image on the success path (add/adjust a unit test with a counting mock writer — `AnalyzePipelineTests` already uses seams).
- `swift test` passes; golden sidecar tests updated deliberately, not silently.
- Benchmark shows reduced per-image write time.

### P2. Stop holding the derivative-cache manifest lock during image encode, and stop re-reading files to hash them

> **Scheduling:** execute as part of plan-08 R4-6 (one `DerivativeCache` manifest redesign covering P2 + P3 + R4-6 together).
>
> **Implementation status (2026-07-11):** complete in R4-6; the 50–100-image live before/after
> timing evidence remains open in plan 10's R4-6 acceptance ledger.

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Medium
- **Files:** `Sources/AISidecarCore/Rendering/DerivativeCache.swift:106-147` (`store`), `DerivativeCache.swift` `sha256(of:)` (~line 226), lock at ~line 24, `loadManifest`/`saveManifest`

**Problem (two parts, fix together).**
1. `store()` takes the global `manifestLock` **before** calling `AtomicFileWriter.writeFile(to:writer:)` (line 110-114). The `writer` closure performs the JPEG encode + disk write of the derivative. With `stage_concurrency > 1`, all render workers serialize on image encoding — the lock only needs to protect the manifest JSON, not the encode.
2. After writing the derivative, `sha256(of: url)` (line 117) re-reads the entire just-written file from disk purely to hash it.

**Change.**
1. Restructure `store()`: perform `AtomicFileWriter.writeFile` and the attribute read **outside** the lock; take the lock only around `loadManifest()` → mutate → `saveManifest()` → `evictIfNeeded()`.
2. Add a `sha256(of data: Data)` overload (CryptoKit `SHA256`) and have the whole-image/subject render paths hash the encoded bytes they already hold in memory where feasible. Where the encoder writes straight to a URL and bytes are never in memory, hashing the temp file once is acceptable — but do not read the file a second time after rename.
3. Concurrency note: two workers storing the *same* derivative file concurrently was previously prevented by the wide lock. After narrowing, the atomic temp+rename contract makes the race benign (last rename wins, manifest updated under lock), but document this in a comment and keep eviction (`evictIfNeeded`) under the lock.

**Acceptance criteria.**
- `DerivativeCacheTests` pass; add a test that concurrent `store()` calls for distinct derivatives succeed and the manifest contains both entries.
- No behavioral change to manifest contents, eviction order, or `DerivativeRecord` fields.
- With `--stage-concurrency 4` on a batch, render stage wall time drops (baseline vs. after).

### P3. Reduce derivative-cache manifest disk churn

> **Scheduling:** execute as part of plan-08 R4-6 (one `DerivativeCache` manifest redesign covering P2 + P3 + R4-6 together).
>
> **Implementation status (2026-07-11):** complete in R4-6, including cross-process invalidation,
> write-through caching, a shared analyze cache instance, and focused read-count coverage.

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium (multi-instance assumptions)
- **Files:** `Sources/AISidecarCore/Rendering/DerivativeCache.swift` (`loadManifest`/`saveManifest` call sites), `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift:465-470`

**Problem.** Every cache read/write loads the manifest JSON from disk and writes it back. Additionally, `AnalyzePipeline.prepare()` constructs a *separate* `DerivativeCache` instance per worker (line 465-470), so nothing amortizes.

**Change.** Two independent sub-steps; do them in order and stop after 1 if measurements say it's enough:
1. Share **one** `DerivativeCache` instance across workers: hoist construction out of the per-worker `prepare()` and pass it in. The class is already lock-guarded (verify `Sendable` conformance compiles under strict concurrency; wrap in a final class + lock or actor if needed).
2. Keep the parsed manifest in memory (instance state), re-reading from disk only on first access, and write-through on mutation. **Constraint:** `aisidecar purge` and concurrent CLI processes may touch the same manifest directory; keep write-through (do not batch writes), so cross-process behavior stays what it is today — the win is eliminating repeated *reads*.

**Acceptance criteria.**
- `DerivativeCacheTests` and `ArtifactCleanupTests` pass; purge still works against a cache written by an analyze run.
- Add a test: repeated `cachedRecord()` hits do not re-read the manifest file (inject a counting FileManager seam or verify via a stubbed loader).

### P4. Progress-log fsync cadence (guarded design change)

> **Scheduling:** do this only after plan-08 R1-3 has landed — R1-3 replaces the legacy `FileHandle.write(_:)` calls in the same lines this item rewrites. Expect the line numbers below to have drifted.

- **Priority:** MEDIUM · **Effort:** Small · **Risk:** Medium (weakens durability guarantee)
- **Files:** `Sources/AISidecarCore/Reporting/JSONLWriter.swift:34-50`

**Problem.** `JSONLWriter.append` calls `fileHandle.synchronize()` (a full fsync) after **every** record — one fsync per image per log. The doc comment says this backs interruption recovery.

**Constraint to preserve.** Recovery after process interruption (SIGINT/SIGTERM/crash of *this process*) must still see every completed record. Note: an unsynchronized `write(2)` already survives process death — fsync only protects against kernel panic/power loss.

**Change.** Replace per-record `synchronize()` with: sync every N records (N = 25), plus sync in `close()`, plus expose `flush()` and call it from the interruption paths (`InterruptionMonitor` handlers — trace who closes the logs on SIGINT and make sure a sync happens there).

**Acceptance criteria.**
- `ProgressLogTests` pass; add a test that `close()` syncs pending records.
- Document the durability tradeoff in the `JSONLWriter` doc comment (process-crash-safe always; power-loss-safe every N records).
- `fs_usage`-observed fsync count during a 100-image batch drops from ~100 to ~4 per log.

### P5. Memoize vocabulary text folding and vocabulary lookups in normalization

- **Priority:** MEDIUM · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Normalization/VocabularyTextFolder.swift:4-13`, `Sources/AISidecarCore/Normalization/CandidateCanonicalizer.swift` (fold call sites ~45, 563, 588, 738, 821; `vocabulary.index.entry(matching:)` call sites ~173, 281, 584)

**Problem.** `VocabularyTextFolder.fold()` (NFC + case fold + whitespace rejoin) and `vocabulary.index.entry(matching:)` run repeatedly for the same strings across a batch — common terms recur across hundreds of images.

**Change.** Inside `CandidateCanonicalizer` (scoped to one normalization run, so no cross-run leakage):
- a `[String: String]` fold cache wrapping `VocabularyTextFolder.fold`;
- a `[String: VocabularyEntry?]` lookup cache wrapping `index.entry(matching:)` (cache misses too — `nil` is a valid cached result).
Keep `VocabularyTextFolder.fold` itself pure/static; the caches live in the canonicalizer instance.

**Acceptance criteria.**
- All `CandidateCanonicalizerTests`, `VocabularyIndexTests`, `VocabularyTextFolderTests` pass unchanged (memoization must be observationally transparent).
- No new global mutable state; caches are instance-scoped.

### P6. Single-pass affinity edge pruning/sorting

- **Priority:** LOW · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Normalization/AssetAffinityGraph.swift` (~lines 190-191, 263-271)

**Problem.** `prune()` sorts each node's incident edges, then the full edge list is sorted again globally at line ~191.

**Change.** In `prune()`, select top-K neighbors per node with `prefix` on a partially sorted structure or keep the per-node sort but drop redundant comparisons; keep exactly **one** global sort as the final ordering authority. Determinism of output ordering must be preserved (tests depend on stable ordering).

**Acceptance criteria.** `AssetAffinityGraphTests`, `AffinityNeighborCandidateTests` pass byte-identically; no ordering change in serialized session documents.

### P7. Debug-derivative copy on cache hit: copy once

- **Priority:** LOW · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Rendering/ImageRenderer.swift:96-106`, `DerivativeCache.copyDebugArtifact` (~line 150)

**Problem.** With `--debug-derivatives`, every cache hit re-copies the cached derivative to the debug path beside the source, even when an identical debug copy already exists.

**Change.** In `copyDebugArtifact`, skip the copy when the destination exists with matching byte count (or matching sha256 if cheap — byte count + mtime is sufficient for a debug artifact); still return the record with `debugPath` set.

**Acceptance criteria.** `ImageRendererTests`/`DerivativeCacheTests` pass; add a test that a second call with an existing identical destination does not rewrite it.

### P8. Pre-fold case-insensitive comparisons in species fallback sort

- **Priority:** LOW · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Normalization/CandidateCanonicalizer.swift` (~line 860)

**Problem.** `preferredSpeciesFallbackDisplayTerm()` lowercases both operands inside a sort comparator — O(n log n) re-lowercasing.

**Change.** Schwartzian transform: map to `(term, term.lowercased())` pairs, sort by the precomputed key, unwrap. Preserve the exact existing tie-break order.

**Acceptance criteria.** Existing canonicalizer tests pass unchanged.

---

## Tier 2 — Reusability: eliminate duplicated code

### R1. Extract shared raw-sidecar batch helpers from the two analyze-adapter pipelines

- **Priority:** HIGH · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzeAndXMPPipeline.swift:90-189`, `Sources/AISidecarCore/Pipeline/AnalyzeAndNormalizePipeline.swift:136-258`

**Problem.** ~92 lines duplicated across the two adapters: `rawInputBatch(from:)`, `plannedRawSidecarPaths(inputPath:configuration:)`, `removeNewRawSidecars(from:preexistingRawSidecars:)`, `analyzeSucceeded(_:)`, `exportSucceeded(_:)`, and near-identical `rawInputFailure(from:)` (differs only in the message suffix, "for XMP export" vs "for normalization").

**Change.** New file `Sources/AISidecarCore/Pipeline/RawSidecarBatchHelpers.swift` with an internal `enum RawSidecarBatchHelpers` hosting the five identical functions as statics. Parameterize `rawInputFailure` with the context string so both existing error messages stay **byte-identical**. Update both adapters to call the helpers; delete the private copies.

**Acceptance criteria.**
- `AnalyzeAndXMPPipelineTests` and `AnalyzeAndNormalizePipelineTests` pass unchanged.
- `grep -n "rawInputBatch" Sources/` shows exactly one definition.
- Error message strings unchanged (grep both old messages, confirm still produced).

### R2. Extract shared CLI output helpers

- **Priority:** HIGH · **Effort:** Small · **Risk:** Low
- **Files:** `Sources/AISidecarCLI/WriteXMPCommand.swift:229-252`, `Sources/AISidecarCLI/NormalizeCommand.swift:316-339`, `Sources/AISidecarCLI/ApplySessionCommand.swift:177-200`

**Problem.** Three commands each privately define identical `pairedFlag(positive:negative:)` (9 lines) and `writeChangePlan(_:)` (6 lines), plus per-command `writeEssentialSummary(_:)` variants that differ only in report type and completion-message prefix.

**Change.** New file `Sources/AISidecarCLI/CommandOutputHelpers.swift` (CLI target — this is presentation, per AGENTS.md it stays out of Core) with `pairedFlag`, `writeChangePlan`, and a summary helper parameterized by prefix string. Stdout text must remain byte-identical for all three commands.

**Acceptance criteria.**
- `swift run aisidecar <cmd> --help` works for all commands; CLI invocation tests pass.
- Manual smoke: `normalize --dry-run` and `write-xmp --dry-run` outputs unchanged vs. `main` (diff captured output).

### R3. Consolidate report-writer error wrapping

- **Priority:** MEDIUM · **Effort:** Small-Medium · **Risk:** Medium (error message fidelity)
- **Files:** `Sources/AISidecarCore/Reporting/BatchSummary.swift:110-124`, `NormalizationSummary.swift:48-63`, `XMPExportSummary.swift:43-57`, `XMPExportReport.swift:155-170`, `NormalizationReport.swift:198-215`

**Problem.** Five writers repeat the same 15-line pattern: encode → `AtomicFileWriter.write` → rethrow `SidecarError` → wrap other errors as `.writeFailed` with a message differing only in the artifact type name.

**Change.** Add to `Sources/AISidecarCore/Support/` a `WriterSupport.writeAndWrap<T: Encodable>(_ value: T, to path: String, encoder: JSONEncoder, typeName: String, fileManager: FileManager)` helper implementing the pattern once. Before migrating, **transcribe every existing message string exactly** into a table in the PR description; the `typeName` parameter must reproduce each one byte-for-byte (watch for wording differences like "Unable to write batch summary" vs "Unable to write normalization report").

**Acceptance criteria.**
- All report/summary tests and golden tests pass byte-identically.
- Each migrated writer body is ≤ 3 lines.
- Deliberately trigger a write failure in a unit test (unwritable path) per writer and assert the message equals the pre-refactor string.

### R4. Audit and resolve `AnalyzeShellPipeline` (dead-code candidate)

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Medium
- **Files:** `Sources/AISidecarCore/Pipeline/AnalyzeShellPipeline.swift` (479 lines), `Tests/AISidecarCoreTests/AnalyzeShellPipelineTests.swift`, `Tests/AISidecarCoreTests/NoXMPRegressionTests.swift`

**Problem.** `AnalyzeShellPipeline` has **no production call sites** — only tests reference it. It appears to be the pre-model-execution pipeline seam superseded by `AnalyzePipeline`.

**Change (audit first, then act).**
1. `git log --follow --oneline Sources/AISidecarCore/Pipeline/AnalyzeShellPipeline.swift` to confirm intent (expect: early-milestone shell superseded at "full analyze pipeline model execution").
2. Enumerate what `AnalyzeShellPipelineTests` and the `NoXMPRegressionTests` usage actually assert. For each assertion, decide: already covered by `AnalyzePipelineTests` (drop) or unique (port to `AnalyzePipeline` with mock runners — the mock-runner seams already exist in `ModelRuntime`).
3. Delete `AnalyzeShellPipeline.swift` and its test file; keep the no-XMP regression guarantee by pointing that test at `AnalyzePipeline`.
4. If the audit finds a genuine unmet need for the shell seam, stop and write up the finding instead of deleting.

**Acceptance criteria.**
- The no-XMP invariant regression test still exists and still fails if analyze writes XMP (temporarily sabotage to verify, then revert).
- `swift test` passes; net −400+ lines.
- AGENTS.md's layout description no longer mentions the shell pipeline (update the line).

### R5 (deferred). File-integrity helper consolidation

Small repeated file-existence/sha256/backup snippets exist across `Metadata/XMPBackupManager.swift`, `Pipeline/XMPExportPipeline.swift`, and reporting. Consolidating into a `Support/FileIntegrity.swift` is legitimate but low ROI; do it opportunistically **only** when touching those files for other reasons. Not a standalone work item.

---

## Explicit Non-Goals (do not "improve" these)

- **Do not** merge `NormalizationSchemaIdentifiers` and `XMPExportSchemaIdentifiers` — intentional domain partition, 7 lines total.
- **Do not** build a generic Markdown-summary abstraction over `NormalizationSummary`/`XMPExportSummary` — the abstraction would cost more than the ~90 partially-overlapping lines it saves.
- **Do not** consolidate the per-command invocation-request builders — commit `9ec1b5a` already extracted the shared validation (`InvocationRules`); the remaining builders are clear, command-specific wiring.
- **Do not** re-parallelize the Ollama capability preflight (reverted deliberately in `a1366b6`).
- **Do not** change base64 image transport to Ollama — protocol requirement; cost is small vs. inference.
- **Do not** batch/buffer manifest or report *writes* across process boundaries — cross-process consumers (`purge`, `cleanup`) rely on on-disk state.

## Suggested Execution Order

| Order | Item | Why this order |
|---|---|---|
| 1 | R1, R2 | Zero-risk warmups; shrink the surface later items touch |
| 2 | P1 | Highest per-image win; isolated |
| 3 | P2 | Highest concurrency win; do before P3 (same file) |
| 4 | P3 | Builds on P2's restructured `store()` |
| 5 | P5, P7, P8 | Independent low-risk wins, any order |
| 6 | P4 | Needs the durability discussion in review |
| 7 | R3 | Mechanical but message-sensitive |
| 8 | R4 | Largest single cleanup; needs audit judgment |
| 9 | P6 | Only if normalization profiling shows it matters |

After items 1-4 land, rerun the Verification Baseline and record before/after numbers in the PR descriptions.
