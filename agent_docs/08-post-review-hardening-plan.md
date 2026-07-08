# Post-Review Hardening Plan — Beta Blockers and Correctness Debt

Version: 1.0
Date: 2026-07-07
Depends on: `agent_docs/phase-4-gui-implementation-plan.md` (B0 complete except B0-5/signing/tag), `agent_docs/invariants.md` (all rules apply)
Audience: junior engineer or Sonnet-level coding agent. Each work item is self-contained: finding, exact location, fix approach, acceptance criteria, and required tests.

## 0. Where this plan comes from

A full-codebase review (2026-07-07, five parallel deep reviews over Core, CLI/ModelRuntime/Rendering, Metadata/Normalization, the GUI, and the docs) at the completion of B0. Baseline: `swift test` green — 398 tests, 0 failures. The docs review has already been applied (README, AGENTS.md, invariants 1/13/17 updated + 18–20 added, architecture-map GUI section, testing guide, packaging plan status pass).

Overall verdict: the safety core is genuinely strong — the XMP write chain (preview → backup → apply → temp-file validation → post-write fingerprint compare → restore-on-failure), atomic-write discipline, deterministic ordering, config precedence, and the GPS guard *plumbing* all verified sound. The defects cluster in three bands:

1. **GUI navigation/state edges** a beta tester will plausibly hit (two ship-blockers).
2. **Process boundaries** in the CLI: exit codes, signals, task cancellation, HTTP retry classification.
3. **Matching semantics** in normalization: vocabulary ambiguity, session-context policy inversion, GPS regex coverage.

## 1. Milestone sequence

| Milestone | Gate | Contents |
|---|---|---|
| **R1 — Beta ship-blockers** | must land **before** the `v0.1.0-beta.1` tag | 7 items: GUI dead states, silent failures a tester will hit, one Core crash bug |
| *(B0-5 + signing + tag)* | manual, per phase-4 plan | LR/C1 round trip, Developer ID sign/notarize, tag |
| **R2 — GUI hardening round 2** | first post-beta code milestone | remaining GUI mediums/lows |
| **R3 — CLI process-boundary hardening** | after R2 (independent, can swap) | exit codes, cancellation, retries, scan robustness |
| **R4 — Normalization/XMP semantic fixes** | after R3 (independent, can swap) | vocabulary ambiguity, session-context policy, GPS regex, session hardening |
| M9–M11 | unchanged | per `phase-4-gui-implementation-plan.md` |

Rules for every item: one work item at a time (invariant 17); each item independently committable with `swift test` green; behavior changes ship with focused unit tests (invariant 16); commit at each passing breakpoint, docs and code in separate commits.

### 1.1 Execution order at a glance

Work strictly top to bottom. Within a milestone, work items in their numbered order unless an item's text says otherwise.

1. **R1-1 → R1-7, in order.** These gate the beta tag; nothing else comes first. R1-1, R1-2, R1-4, R1-5 all touch `WizardShellView.swift` — doing them in order avoids merge churn. R1-3 (Core, `JSONLWriter`) is independent and may be done at any point inside R1.
2. **R1 exit gate** (end of §2): full `swift test`, manual GUI pass over all four flows plus kill-relaunch-restore-export.
3. **B0-5 + release (manual, Ron):** LR/C1 round-trip evidence per `agent_docs/release-evidence/`, Phase 1 M9 calibration evidence or explicit deferral note, Developer ID signing → notarization → stapling → `spctl --assess` pass, tag `v0.1.0-beta.1`, DMG handout. (Per the phase-4 plan B0 section.)
4. **R2-1 → R2-7, in order.** First post-beta code milestone.
5. **R3-1 → R3-11, in order.** R3 and R4 are independent of each other and may swap wholesale if priorities change, but do not interleave them. R3-11's sub-items are each one small commit and may be reordered or individually deferred.
6. **R4-1 → R4-6, in order.** R4-6 must be coordinated with efficiency-plan P2/P3 (one manifest redesign, not two).
7. **M9 → M10 (a/b/c) → M11**, unchanged, per `agent_docs/phase-4-gui-implementation-plan.md`.
8. **After M11:** feature work per `agent_docs/09-post-m11-feature-roadmap.md`.

---

## 2. R1 — Beta ship-blockers

### R1-1 — Wizard "Back" from Step 5 lands on a dead Working screen (HIGH)

**Finding.** `Sources/CupricAspectApp/Shells/WizardShellView.swift:341` enables Back on Step 5 (`backEnabled = step > 1 && step != 4`); Back decrements to Step 4 (`:429-430`), which renders `Step4WorkingView` unconditionally (`:247-248`). Step 4 is only exited by `onChange(of: runModel.phase)` transitions that have already fired. On arrival, `runModel.phase` is `.finished` (or `.idle` on the recovery path), so: Cancel no-ops (`AnalysisRunModel.cancel()` guards `phase == .running`), the primary button is disabled, and Back is disabled on Step 4. The only escape is relaunching the app; unsaved review verdicts since the last autosave are lost. Every completed flow exposes this.

**Fix.** In `WizardShellView`, make Back from Step 5 skip the Working step: when `step == 5` and `runModel.phase != .running`, Back goes to Step 3 (options), not Step 4. Equivalently: Step 4 is only a valid destination while a run is in flight — encode that in the back-navigation logic, not in the render switch.

**Acceptance.** From a completed analyze, write, and normalize flow: press Back on Step 5 → land on Step 3 with options intact and the primary button enabled; complete the flow again from there. No reachable state renders Step 4 without a live run.

**Tests.** Wizard step-navigation logic is in the view today; extract the `backTarget(from:phase:)` decision into a small testable function (in the shell file or a `WizardNavigation` helper) and unit-test: `(step 5, .finished) → 3`, `(step 5, .idle) → 3`, `(step 3, *) → 2`, Step-4 in-flight unchanged.

### R1-2 — Recovery launch can't export and its primary action deletes the recovery (HIGH)

**Finding.** `WizardShellView.swift:64-68`: after an interrupted review, launch jumps to Step 5 with `selectedAction = .analyze` and **no imported folder**. Verified consequences: `step5WriteAvailable` is false for `.analyze` (`:355-363`) so no Write button exists; `startExport` silently no-ops without `importModel.sourceFolder` (`:280-293`); the user cannot navigate back (R1-1); and the prominent "Done" primary calls `completeCleanly()` (`:411-421`), which deletes `review-recovery.json` and all verdicts, with only a 12-pt footer hint as warning. The FR4-046a recovery promise is effectively broken.

**Fix.** Two required changes, one optional:
1. The recovery file already references the session's source context — restore the folder/action alongside the verdicts: on recovery restore, set `importModel` source (reuse the reopen-last-folder path from B0-6, `FolderImportModel`) and `selectedAction = .write` (or the action recorded in the recovery session), so `step5WriteAvailable` and `startExport` work.
2. "Done" must confirm before discarding a restored-but-unsaved review: a confirmation dialog ("Discard the restored review? N decisions will be lost. Save session first?") with Save Session / Discard / Cancel.
3. (Optional, if 1 is awkward) At minimum, replace the dead Step 5 recovery landing with a dedicated recovery screen offering Restore → review → Save/Write, or Discard with confirmation.

**Acceptance.** Kill the app mid-review (the `m8-kill-relaunch-check.sh` pattern, or manually) → relaunch → restore → the review is visible **and** "Write XMP" is available and works end-to-end. Pressing Done with unsaved restored verdicts asks before deleting. `FolderImportReopenTests`-style unit tests cover the restored source/action; a `ReviewModel`/shell test covers the confirm-before-discard decision.

### R1-3 — Progress-log append crashes the process on I/O failure (HIGH, Core)

**Finding.** `Sources/AISidecarCore/Reporting/JSONLWriter.swift:37-38` uses the legacy exception-raising `FileHandle.write(_:)` (twice: record + newline). On disk-full or an ejected volume this raises an uncatchable ObjC exception → `aisidecar` hard-crashes mid-batch and the GUI host process dies too. All three progress logs route through this. The surrounding `do/catch` covers only `encoder.encode` and `synchronize()`.

**Fix.** Replace both calls with `try fileHandle.write(contentsOf:)` and let the existing catch path produce the structured `.writeFailed` handling. Audit `JSONLWriter` for any other legacy FileHandle API (`seekToEndOfFile` etc.) and move to the throwing equivalents.

**Acceptance/tests.** Unit test with a `FileHandle` over a closed/invalid descriptor (or a full pipe) asserting a thrown error, not a crash; existing progress-log tests stay green.

### R1-4 — Normalize-stage failure is invisible; user bounces in a silent loop (MEDIUM)

**Finding.** `WizardShellView.swift:112-123` returns to Step 3 when `NormalizationModel.phase = .failed(message:)`, but no view renders that phase — Step 3's banners check only `runModel.phase` and `exportModel.phase` (`:228-246`). A normalization failure (unwritable artifact dir, sidecars removed between stages, malformed vocabulary) silently returns the user to options; retrying loops.

**Fix.** Add `normalizationModel.phase` to the Step 3 failure banner logic, showing the failure message with the same styling as run failures (and the log-file pointer per B0-4).

**Acceptance/tests.** Force `NormalizationModel.run` to throw (nonexistent vocabulary path is easiest) → Step 3 shows the message. Unit-test the banner-selection logic if it's extracted; otherwise a model-level test asserting `.failed(message:)` carries the thrown error text.

### R1-5 — Export success banner lies when targets failed (MEDIUM)

**Finding.** `WizardShellView.swift:257-258, 295-312`: `ExportModel` sets `phase = .written` whenever the pipeline returns, and `writtenBanner(targets:)` counts **all** `targetReports`. `XMPExportPipeline` records per-target `.failed` statuses without throwing, so on a read-only/full output volume every target can fail while the headline reads "N XMP sidecars written · backups saved · validated".

**Fix.** Count only `.written`/`.created` statuses; when failures exist, use a warning tone: "M of N written — K failed; see the report below."

**Acceptance/tests.** Unit test on the banner-composition function with mixed target statuses; manual check against a read-only output dir.

### R1-6 — "Save session only" can silently write nothing (MEDIUM)

**Finding.** `ReviewModel.swift:192-195` and `NormalizationModel.swift:172-175` `guard let session else { return }` — while the session is still building, after a build failure, or pre-restore, the user completes a full save panel and no file is written, no error raised. The buttons are unconditionally enabled (`Step5ReviewView.swift:96-97`, `NormalizationInspectorView.swift:64-66`). Same pattern: `WizardShellView.startExport()` silently returns when `sourceFolder`/`session` is nil. This is the surviving silent failure in exactly the flow B0-4 targeted.

**Fix.** Disable the save/import/apply buttons when `session == nil` (bind to the model), and turn the guard-return into `reportFileError`/assertion so any future unguarded path surfaces instead of no-oping.

**Acceptance/tests.** Unit tests: button-enable state derives from session presence; `save` with nil session reports an error rather than returning silently.

### R1-7 — "Edit everywhere" resurrects engine-withheld decisions and misses non-flat chips (MEDIUM)

**Finding.** `ReviewModel.swift:247-259` (`editEverywhere`): (a) iterates all `perAssetDecisions` without filtering by status/verdict, so it sets `.approved` on machine-withheld decisions that were never shown in the UI — `SessionReview.applying` then flips them to `.accepted` and they get **exported** (most likely via "Import session…" of a real normalize session, where withheld decisions are common); (b) it matches only `decision.flatKeyword`, while chips display `edits ?? flatKeyword ?? canonicalPath ?? sourceText` (`:84`), so for fallback-labeled chips it applies to zero decisions; (c) the returned count is discarded by `Step5ReviewView.swift:63-66`, so the user gets no feedback either way.

**Fix.** Filter to decisions that are visible/eligible (same predicate as `assetRows`/`acceptAll`: accepted status or existing user verdict); match on the same display-keyword derivation the chips use; surface the returned count in the UI ("Applied to N photos").

**Acceptance/tests.** Extend `ReviewModelTests`: a session containing a withheld decision with the same keyword — `editEverywhere` must not change it; a decision whose chip label comes from `canonicalPath` — the edit must apply; count is returned and correct. `testApplySessionWritesOnlyApprovedKeywords` stays green.

**R1 exit gate:** all seven items landed, `swift test` green, one manual GUI pass over analyze/write/normalize/apply + kill-relaunch-restore-export. Then proceed to B0-5 evidence, signing, and the `v0.1.0-beta.1` tag per the phase-4 plan.

---

## 3. R2 — GUI hardening round 2 (post-beta)

### R2-1 — Options silently reset on re-entering Step 3
`Step3OptionsView.swift:44-46`: `onAppear` re-runs `loadResolvedDefaults()`, discarding user-set mode/gps/existing/concurrency on every return to Step 3 (including the automatic failed-run bounce — e.g. "Existing: Redo" reverts to "Skip", making retries no-op). Fix: load defaults once per import (or only when options are unset); keep user edits across navigation within a session. Test: set option → navigate away/back → option persists.

### R2-2 — No terminate-time autosave
`CupricAspectApp.swift:34-36`: ⌘Q/window-close terminates with no final autosave; up to 24 verdicts (or 5 minutes) lost. Fix: `applicationShouldTerminate`-equivalent hook calling `reviewModel.autosaveNow()`. Test: model-level `autosaveNow` writes pending changes.

### R2-3 — Overlapping rescans race
`FolderImportModel.swift:119-169`: `chooseSource`/`chooseOutput`/`toggleRecursive` spawn uncancelled rescans; a stale scan can publish last, and `try? inventory` collapses scan errors into a generic message. Fix: generation token (increment per scan; publish only if current), surface `inventory` errors distinctly. Test: two interleaved fake scans — stale result dropped.

### R2-4 — Progress >100% when the folder changed after import
`AnalysisRunModel.swift:126-131` + `Step4WorkingView.swift:73`: `total` is the stale import count; the pipeline rescans. Fix: clamp fraction to 1.0 and reconcile `total` from the run's own planned count when the first progress record arrives. Test: progress math clamp.

### R2-5 — Decode/IO polish batch
- `ThumbnailStore` negative cache for undecodable files (`ThumbnailStore.swift:36-57`).
- `AssetPreviewDetails.load` (`AssetPreview.swift:35-38`): surface "sidecar unreadable" instead of `try?`-silent missing facts.
- `AssetQueue.hasXMPExportBlock` (`AssetQueue.swift:104-111`): stop full-decoding every `.ai.json` on rescan — read only the `xmp_export` key (partial decode struct). Measure at 5k assets (ties into M11).
- `FileLogSink.write` (`GUILog.swift:52-55`): don't reset `currentSize` when rotation's `moveItem` failed.

### R2-6 — Delete or gate `NormalizationModel.writeNormalizedXMP`
Production-dead (only tests call it) and it bypasses the FR4-029 dry-run gate; its `.written` phase makes `WizardShellView.swift:115-117` unreachable. Delete it (retarget its tests at `ExportModel`'s path) or route it through `ExportModel`.

### R2-7 — Known-issues note: concurrent instances
Two app instances (or GUI + CLI) share the recovery file path, log path, and config read-modify-write; all writers are atomic so nothing corrupts, but last-writer-wins losses are possible. Document as a beta known issue (README Troubleshooting); a single-instance lock or file coordination is M11-scope if it ever bites.

---

## 4. R3 — CLI process-boundary hardening

### R3-1 — Nonzero exit codes for failed/interrupted batches
`AnalyzeCommand.swift:68` discards the pipeline result; `WriteXMPCommand.swift:246-252`, `NormalizeCommand.swift:333-339`, `ApplySessionCommand.swift:194-200` print failure counts but exit 0 — while `CleanupCommand.swift:30-37` throws on failures (inconsistent). Scripted use (`analyze && write-xmp`) proceeds after 100%-failure runs. Fix: exit nonzero when any per-file failure or an interruption occurred; define the policy once (e.g. exit 1 = some failures, exit 130 = interrupted) in `SharedOptions` or a small `BatchExitPolicy`, apply to all batch commands, and document it in `--help` and the README. This changes observable behavior — add it to the README Troubleshooting notes and keep error codes stable (invariant 7 governs `E_*` strings, not exit codes, but treat exit codes as stable once shipped).

### R3-2 — Make Ctrl+C responsive: check interruption between roles/attempts and cancel in-flight requests
`InterruptionMonitor.swift:30-53` + `AnalyzePipeline.swift:294-338, 697-716`: the interruption flag is only checked between files; in-flight model calls (up to 2 roles × 3 attempts × 180 s per file) are never cancelled, and SIGINT is `SIG_IGN`'d so repeated Ctrl+C can't escalate. Fix: (a) check the monitor between roles and between retry attempts; (b) pass a cancellation signal into `OllamaVisionRunner` so `URLSession` requests are cancelled on interruption (store the in-flight `Task`/use `withTaskCancellationHandler`); (c) on a second SIGINT, restore default disposition so the third genuinely kills. Files stay fail-closed at boundaries (existing behavior). Tests: mock-runner test asserting a between-attempts interruption stops the loop; transport-level cancellation test with a hanging mock.

### R3-3 — Retry classification + Ollama error bodies
`OllamaVisionRunner.swift:337-369`: non-2xx → `.unreachable` → blanket retry; HTTP 400/404 are retried three times with multi-MB payloads, and Ollama's `{"error": "..."}` body (e.g. "model requires more memory") is discarded. Fix: parse and include the error body in the thrown error message; retry only timeouts, transport errors, and 5xx; fail fast on 4xx. Add the missing test pinning non-retry of 4xx (the existing test name `testAnalyzeRetriesTimeoutsAndTransportErrorsOnly` promises this). Also `requestJSON`/`decodeChatResponse` (`:284-291, 371-382`): a malformed 200 body should be a decode-class error (retry once — proxies truncate), not `modelEndpointUnreachable`. Error-code note: introduce an additive code (e.g. `E_MODEL_RESPONSE_INVALID`) rather than repurposing existing raw values (invariant 7).

### R3-4 — Respect task cancellation in the model runtime
`OllamaHTTPTransport.swift:66-72` + `OllamaVisionRunner.swift:345-357`: `CancellationError`/`URLError(.cancelled)` currently → `.unreachable` → retried from a cancelled task → a **permanent failure sidecar** claiming the endpoint was unreachable (pollutes `--existing skip` reruns; the GUI cancel path is the realistic trigger). Fix: check `Task.isCancelled` in the retry loop; rethrow cancellation without writing a failure sidecar (the pipeline's interruption path already handles clean stop-at-boundary). Test: mock transport throwing `CancellationError` — no sidecar written, run records interruption.

### R3-5 — Configurable model timeout/retry
`AnalyzePipeline.swift:725-727` hard-codes `ModelRunOptions.default` (180 s, retryLimit 2) with only keep-alive plumbed. On slower Macs the 26B default model exceeds 180 s cold. Fix: add `model_timeout_seconds` (and optionally `model_retry_limit`) through the full chain — `AppConfig` (+ example JSONC), `AISIDECAR_*` env, `--model-timeout` flag, `ResolvedRunConfiguration`, GUI Settings (M8a write-through pattern). Follow the keep-alive plumbing as the template. Tests: resolver precedence tests per the existing pattern.

### R3-6 — Recursive scans must record unreadable subdirectories
`ImageScanner.swift:133-137` and `RawJSONSidecarInputResolver.swift:240-244`: `enumerator(at:...)` without an `errorHandler` silently skips permission-denied subtrees; the run reports success with a coverage gap. Fix: pass an `errorHandler` that records a `ScanErrorRecord` (scanner) / input-failure record (resolver) per failed directory and continues. Also R3-6b: `ImageScanner.swift:153-157` non-recursive unreadable-folder throw should wrap in a `SidecarError` (`validationError`) like the recursive branch. Tests: fixture dir with a chmod-000 subdir (skip under CI-root if needed; `#if !os(...)` not required — macOS-only).

### R3-7 — Stop the pipeline's own artifacts from poisoning reruns
`ImageScanner.swift:280-299` `shouldIgnore` skips only dot-files/`.ai.json`/`.xmp`, so `batch-progress-*.jsonl`, `batch-summary-*.json`, report/summary artifacts written into the scan root become `E_UNSUPPORTED_FORMAT` **failed** records on every rerun — summaries permanently show failures and `clearDerivativeCacheAfterSuccess` (`AnalyzePipeline.swift:206-208`) can never fire again. Fix: teach `shouldIgnore` to recognize owned artifact name patterns via `ArtifactNames`/`ArtifactCleanup.classify` (they already encode the patterns). Tests: scan a folder containing each owned artifact type → no failure records.

### R3-8 — Filesystem-portable artifact timestamps
`Timestamp.swift:11-15`: artifact filenames embed `:` (ISO-8601), which cannot be created on exFAT/FAT32/SMB — analyzing a folder on an SD card with no `--output-dir` aborts the whole run at `JSONLWriter.init`. Fix: switch artifact-filename timestamps to a filesystem-safe form (`2026-07-07T180000Z` or `20260707-180000`) **for new files only** — readers must keep recognizing old names (`ArtifactNames` patterns and `ArtifactCleanup.classify` accept both; invariant 7 treats artifact-name patterns as load-bearing, so this is an additive pattern change: update `ArtifactNames`, `ArtifactCleanup`, golden tests deliberately). Also fixes same-second collisions partially; R3-8b: include a short random suffix or sequence number to fully de-collide same-second runs (`AnalyzePipeline.swift:106-113`).

### R3-9 — Source-hash recheck must not vanish on before-hash failure
`XMPExportPipeline.swift:407-417`: `hashes[path] = try? compute(...)` removes the key on failure, so that target silently gets **no** invariant-4 recheck and no `XMPSourceHashCheck` record. Fix: record a check entry with a nil `beforeSHA256` and the error (the type already models nil-before), and treat it as a failed verification for reporting. Test: unreadable source at export start → report contains a failed check record; write outcome per policy (fail the target — conservative default, NFR "prefer safety").

### R3-10 — Crash-hardening `Dictionary(uniqueKeysWithValues:)` on user-editable inputs
`ApplySessionPipeline.swift:248-251`, `XMPChangePlan.swift:286`, `CandidateObservation.swift:202-208`: hand-edited/corrupt session JSON with duplicate keys → `fatalError`. Fix: `Dictionary(_:uniquingKeysWith:)` + explicit duplicate detection throwing `validationFailed`/`sessionStale` with the offending key named. Tests: malformed session fixtures for each site.

### R3-11 — Batch: remaining lows (one commit each, optional within R3)
- `AnalyzeAndXMPPipeline.swift:51-53, 171-178` (+ mirror in `AnalyzeAndNormalizePipeline`): `try?` on the pre-scan means a scan failure → empty preexisting set → `removeNewRawSidecars` can delete a pre-existing user `.ai.json` under `--existing overwrite`. Make the pre-scan failure abort the "remove new sidecars" cleanup (fail toward keeping files), and log deletion failures.
- Symlink consistency (`ImageScanner.swift:181, 301-303` vs `110-122`): folder-scan symlink skip should emit a recoverable record; direct-file input should stat the target, not the link (affects `fast` identity digest).
- Unicode-normalization collision folding (`SidecarNaming.swift:90`, `ModelInputExportPipeline.swift:762`): fold NFC in collision keys.
- `ConfigFileEditor.swift:22`: distinguish unreadable-vs-absent config (fail safely instead of writing a config containing only the changed keys); wrap parse errors in `E_CONFIG_INVALID`.
- `installedVisionTags` (`OllamaVisionRunner.swift:262-276`): distinguish probe errors from "not vision-capable" in the `modelTagNotFound` diagnostic.
- Orphaned atomic-writer temps: teach `ArtifactCleanup.classify` to recognize `.name.UUID.ext` temp patterns (age-gated, e.g. >1 day) so `cleanup`/cache `purge` can remove them; never remove young ones (in-flight).

---

## 5. R4 — Normalization/XMP semantic fixes

### R4-1 — File-list entries outside the list directory collapse into one XMP group (MEDIUM)
`NormalizationInputResolver.swift:532-542` (`relativePath(for:root:)` falls back to `lastPathComponent`) feeding `groupKey(for:)` (`:412-418`): two same-base-name images from **different directories** in an absolute-path file list group as one RAW+JPEG pair — keywords union into a single `.xmp` beside whichever asset sorts first; the other image gets nothing. Fix: group key must use the resolved absolute parent directory when the entry is outside the root (never the empty-string directory). Tests: `FileListInputResolverTests` gains an out-of-root absolute-path case asserting two separate groups/targets.

### R4-2 — `user_only`/`withhold` session context blocked exactly where the model agreed (MEDIUM)
`BatchConsensusEngine.swift:270` (`applySessionContext`) skips adding the user-context decision when **any** decision with the same `(assetID, canonicalPath)` exists, regardless of status. A direct model observation of a `user_only` entry produces a *withheld* decision, which then blocks the accepted user-context decision — so `--session-event "Migration"` fails to apply precisely on assets where the model also said "migration". Fix: only skip when the existing decision is `accepted` (or user-decided); a withheld/skipped machine decision must be superseded by the user-context decision (replace or add-accepted per the session-context policy record). Tests: `SessionContextPolicyTests` gains a case with a pre-existing withheld direct decision — context still applies; determinism record updated if policy text changes.

### R4-3 — GPS coordinate-term guard: broaden the regex set (MEDIUM, invariant 3)
`CandidateExtractor.swift:669-686` (`isCoordinateLikeTerm`) misses (verified by running the regexes): DMS `40°26'46"N 79°58'56"W`, cardinal-prefix `N 40.446 W 79.982`, integer pairs `40, -79`, UTM `UTM 17T 589500 4477000`. In observed-tags mode there is no vocabulary backstop, so a model echoing coordinates can reach `dc:subject`. Fix: extend the pattern set for DMS (degree/quote/double-quote symbols incl. Unicode primes), cardinal-prefixed decimal, bare signed numeric pairs, and UTM; keep patterns conservative (require two coordinate-ish tokens or explicit N/S/E/W context — don't block "35mm" or "Route 66"). Tests: table-driven cases for each caught format plus non-coordinate negatives ("50mm f/1.8", "Apollo 11", "Room 404").

### R4-4 — Vocabulary validation: duplicate/ambiguous flat keywords (MEDIUM, invariant 10 seam)
`VocabularyValidator.swift:49-72` never cross-checks flat keywords; `VocabularyIndex.swift:117-125` `insertLookup` silently first-wins. Two entries sharing a folded `flat_keyword` (or a synonym of A equal to B's flat keyword) resolve to the lexicographically-first canonical path — the wrong `lr:hierarchicalSubject` with no warning, while the separator-fold map *is* ambiguity-guarded. Fix: (a) validator reports duplicate folded flat keywords and synonym↔flat collisions as errors (or warnings + ambiguity-guard, decide with maintainer: erroring may break existing vocabularies — prefer validation **error** for new/edited vocabularies and an ambiguity-guarded lookup like `insertSeparatorLookup` at runtime for robustness); (b) `insertLookup` gains the same ambiguity-set mechanism as separator lookups. Tests: mirror `testSeparatorInsensitiveFallbackDoesNotResolveAmbiguousAliases` for exact-fold.

### R4-5 — Session/edit hardening lows
- **Pipe in user edits** (`SessionReview.swift:36-47`; GUI `ReviewModel.swift:237-243`): edited keywords bypass the `containsHierarchySeparator` guard — a literal `|` keyword exports. Reject/strip `|` in `SessionReview.applying` (Core-level, so CLI session edits are covered too) and surface the rejection in the GUI.
- **Forward-compat decode** (`NormalizationSessionDocument.swift:752-765`): 1.x acceptance + strict enum decoding = future minor versions fail wholesale. Make additive enums decode-tolerant (unknown-case rawValue preservation or explicit `unknown` case that fails only the affected decision, not the document) — respects invariant 8's spirit both directions.
- **Stamp path by construction** (`NormalizedXMPChangePlanner.swift:217` → `XMPExportPipeline.stampSourceSidecars:598`): `sourceSidecarPath` falls back to the source-image path when no `.ai.json` exists; only `RawSidecarExportStamp`'s JSON-object guard (whose error is `try?`-swallowed) protects invariant 2. Emit nil instead of a non-`.ai.json` path and skip stamping; log the skip.
- **Merge-target selection** (`XMPDocumentParser.swift:162-181`): prefer `rdf:about=""` or about matching the source over `descriptions.first` when no managed fields exist.
- **Export-stamp serialization drift** (`RawSidecarExportStamp.swift:44-65`): `JSONSerialization` re-encodes the whole sidecar (escaped slashes, float drift like `0.08 → 0.080000000000000002`) diverging from deterministic `JSONCoding` output. Route the rewrite through the merge-preserving `JSONCoding` path used by schema-evolution rewrites.

### R4-6 — Derivative-cache cross-process safety (shared with efficiency plan P2/P3)
`DerivativeCache.swift:24` protects the manifest with an in-process `NSLock` only; GUI + CLI share `~/Library/Caches/aisidecar/derivatives` and interleave load-modify-save (lost entries → orphaned artifacts that escape the byte-cap accounting, FR1-018a silently unenforced). Fix options (pick with maintainer): an `flock`-based file lock around manifest read-modify-write (simple, sufficient), or per-entry manifest files. Coordinate with efficiency-plan P2/P3 (manifest churn) — one redesign, not two. Also R4-6b (low): `evictIfNeeded` (`:256-272`) protects only the just-stored artifact; with `stage_concurrency > 1` and a small user-set cache cap, prepared-ahead derivatives can be evicted before the model loop reads them — protect the current batch's planned artifacts or floor the cap at the working-set size.

---

## 6. Explicitly deferred (recorded, not scheduled)

- **Two-instance file coordination** beyond the R2-7 known-issues note (single-instance lock) — M11 if ever needed.
- **fsync-before-rename** in `AtomicFileWriter` (power-loss window) — measure cost first; sidecars are regenerable, XMP writes already validate post-write.
- **Backup/restore TOCTOU vs. concurrent Lightroom edits** (`XMPExportPipeline.swift:328-404`) — inherent without file locking; single-user tool; revisit only with real-world reports.
- **Benchmark harness nits** (median bias, `failed_sidecar_count` missing from the markdown table, child-exit-code not flagged) — fold into the next benchmarking milestone if M9 calibration work reopens.
- **EXIF orientation 0 strictness** (`RenderRecipe.swift:46-54`) — deliberate; revisit if real-world images hit it.
- **Per-file `startedAt` at plan time** inflating `durationMs` (`AnalyzePipeline.swift:402-403`) — reporting-quality only.
- **`RawJSONSidecar.swift:126` `try?` on `subject_isolation`** — verified no data loss on rewrite.

## 7. Verification

Every R-milestone ends with: `swift test` green; `swift run aisidecar --help`; `swift build --product CupricAspect`; the R1 gate additionally requires the manual GUI pass listed there. R3-8 (artifact names) and R3-1 (exit codes) change observable behavior: update `agent_docs/testing-and-verification.md`, the README, and golden tests deliberately, and say so in the commits. New config keys (R3-5) go into `aisidecar.config.example.jsonc` + the Settings sheet per the M8a pattern.

## 8. Traceability

| Review finding | Work item |
|---|---|
| GUI H1 (Back dead state) | R1-1 |
| GUI H2 (recovery flow) | R1-2 |
| Core #1 (JSONL crash) | R1-3 |
| GUI M1 (normalize failure invisible) | R1-4 |
| GUI M2 (banner counts failures) | R1-5 |
| GUI M4 (silent save no-op) | R1-6 |
| GUI M3 (editEverywhere) | R1-7 |
| GUI M5/M6/L1/L2/L5/L6 | R2-1…R2-6 |
| GUI L3 (two instances) | R2-7 |
| CLI #1 (exit codes) | R3-1 |
| CLI #2 (Ctrl+C) | R3-2 |
| CLI #3 (retry classification), #12 (error taxonomy) | R3-3 |
| CLI #4 (cancellation) | R3-4 |
| CLI #5 (timeout config) | R3-5 |
| Core #2 (scan error handler), #11 | R3-6 |
| Core #3 (artifact poisoning) | R3-7 |
| Core #4 (exFAT names), #14 (same-second) | R3-8 |
| Core #5 / XMP L1 (source-hash swallow) | R3-9 |
| Core #6 / XMP L7 (uniqueKeys crashes) | R3-10 |
| Core #7, #8, #9, #13; CLI #10, #11 | R3-11 |
| XMP M1 (file-list grouping) | R4-1 |
| XMP M2 (user_only inversion) | R4-2 |
| XMP M3 (GPS regex) | R4-3 |
| XMP M4 (vocab ambiguity) | R4-4 |
| XMP L2/L3/L4/L6 + Core #17 (stamp serialization) | R4-5 |
| CLI #6/#7 (cache cross-process, eviction) | R4-6 |
