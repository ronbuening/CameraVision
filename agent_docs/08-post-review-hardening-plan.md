# Post-Review Hardening Plan — Beta Blockers and Correctness Debt

Version: 1.0
Date: 2026-07-07
Depends on: `agent_docs/phase-4-gui-implementation-plan.md` (B0 complete except B0-5/signing/tag), `agent_docs/invariants.md` (all rules apply)
Audience: junior engineer or Sonnet-level coding agent. Each work item is self-contained: finding, exact location, fix approach, acceptance criteria, and required tests.
Execution detail: `agent_docs/archive/10-hardening-implementation-plan.md` carries the as-built code-level companion for every R1–R4 item (verified current-code excerpts, proposed code, test skeletons, per-item commits, and the manual release-step runbook). It is archived now that R1–R4 are complete; this document stays the source of truth for findings, scope, and order, and the still-open manual release step's runbook lives in `agent_docs/release-checklist.md` plus plan 06 §4.

## 0. Where this plan comes from

A full-codebase review (2026-07-07, five parallel deep reviews over Core, CLI/ModelRuntime/Rendering, Metadata/Normalization, the GUI, and the docs) at the completion of B0. Baseline: `swift test` green — 398 tests, 0 failures. The docs review has already been applied (README, AGENTS.md, invariants 1/13/17 updated + 18–20 added, architecture-map GUI section, testing guide, packaging plan status pass).

Overall verdict: the safety core is genuinely strong — the XMP write chain (preview → backup → apply → temp-file validation → post-write fingerprint compare → restore-on-failure), atomic-write discipline, deterministic ordering, config precedence, and the GPS guard *plumbing* all verified sound. The defects cluster in three bands:

1. **GUI navigation/state edges** a beta tester will plausibly hit (two ship-blockers).
2. **Process boundaries** in the CLI: exit codes, signals, task cancellation, HTTP retry classification.
3. **Matching semantics** in normalization: vocabulary ambiguity, session-context policy inversion, GPS regex coverage.

## 1. Milestone sequence

| Milestone | Gate | Contents |
|---|---|---|
| **R1 — Beta ship-blockers** | must land **before** the `v0.1.0-beta.1` tag | 14 items: GUI dead states, silent failures a tester will hit, one Core crash bug, three Options/write alpha fixes (per-run model override, visible XMP conflict policy, opt-in post-write cleanup), plus four further alpha fixes (Settings default for concurrency, Settings default for XMP treatment, relabel the program's `.ai.json` sidecar control so it doesn't read as XMP, and the seconds-per-image rate that misreads on a skip-heavy re-run) |
| *(B0-5 + signing + tag)* | manual, per phase-4 plan | LR/C1 round trip, Developer ID sign/notarize, tag |
| **R2 — GUI hardening round 2** | first post-beta code milestone | remaining GUI mediums/lows |
| **R3 — CLI process-boundary hardening** | after R2 (independent, can swap) | exit codes, cancellation, retries, scan robustness |
| **R4 — Normalization/XMP semantic fixes** | after R3 (independent, can swap) | vocabulary ambiguity, session-context policy, GPS regex, session hardening |
| M9–M11 | unchanged | per `phase-4-gui-implementation-plan.md` |

**Implementation status (2026-07-10):** R3-1 through R3-11 are implemented and committed. The automated R3 exit
gate is green; environment-dependent Ctrl+C, live-model timeout, and exFAT checks remain manual release evidence as
recorded in the companion plan. A post-implementation audit (2026-07-10, six parallel spec-versus-code reviews)
confirmed every item and landed two corrections: `normalize --dry-run` now exits nonzero when its printed change
plan contains failed targets, and scans ignore `.xmp.bak-*` backups so backup-and-merge no longer poisons reruns.
Details in the companion plan's R3-1/R3-7 audit-correction notes and R3 exit gate.

Rules for every item: one work item at a time (invariant 17); each item independently committable with `swift test` green; behavior changes ship with focused unit tests (invariant 16); commit at each passing breakpoint, docs and code in separate commits.

### 1.1 Execution order at a glance

Work strictly top to bottom. Within a milestone, work items in their numbered order unless an item's text says otherwise.

1. **R1-1 → R1-14, in order.** These gate the beta tag; nothing else comes first. R1-1, R1-2, R1-4, R1-5 all touch `WizardShellView.swift` — doing them in order avoids merge churn. R1-3 (Core, `JSONLWriter`) is independent and may be done at any point inside R1. R1-3 also edits the same lines as efficiency-plan P4 (fsync cadence) — R1-3 lands first; P4 waits for its slot in step 7. R1-8 and R1-9 both edit `Step3OptionsView.swift` (Options page); R1-8 also touches `AnalysisOptions`/`AnalysisRunModel` and R1-9 also touches `ExportModel` — do R1-8 then R1-9 to keep the Options-view edits in one line. R1-10 also touches `ExportModel` plus `ChangePlanSheet.swift`; do it right after R1-9 so the two `ExportModel` edits (XMP policy, cleanup flag) land together. **R1-11 and R1-12** both add a control to the Settings `CONFIGURATION` section (`SettingsSheet.swift`) and a write-through to `SettingsModel.swift`; do R1-11 then R1-12 to keep the Settings-view edits in one line. R1-12 also adds one seeding line to `AnalysisOptions.loadResolvedDefaults` (`AnalysisRunModel.swift`). **R1-13** (label/caption changes) also edits `SettingsSheet.swift` (the existing-sidecar row) and `Step3OptionsView.swift`; do it right after R1-12 so the three `SettingsSheet.swift` edits land in one line. **R1-14** (rate math in `AnalysisRunModel.swift`) is independent and may land at any point inside R1.
2. **R1 exit gate** (end of §2): full `swift test`, manual GUI pass over all four flows plus kill-relaunch-restore-export.
3. **B0-5 + release (manual, Ron):** LR/C1 round-trip evidence per `agent_docs/release-evidence/`, Phase 1 M9 calibration evidence or explicit deferral note, Developer ID signing → notarization → stapling → `spctl --assess` pass, tag `v0.1.0-beta.1`, DMG handout. (Per the phase-4 plan B0 section.) While executing this step, write down the exact sequence as `agent_docs/release-checklist.md` (packaging-plan WI-7, pulled forward: the beta tag is the first real execution of that procedure; roadmap F4-R4 then extends the checklist rather than authoring it).
4. **R2-1 → R2-7, in order.** First post-beta code milestone.
5. **R3-1 → R3-11, in order.** R3 and R4 are independent of each other and may swap wholesale if priorities change, but do not interleave them. R3-11's sub-items are each one small commit and may be reordered or individually deferred.
6. **R4-1 → R4-6, in order.** R4-6 must be coordinated with efficiency-plan P2/P3 (one manifest redesign, not two): execute P2/P3 as part of R4-6, not as a separate later pass.
7. **Efficiency plan (`agent_docs/05-efficiency-improvement-plan.md`), in its own order table.** Runs after R4 and before M9. Exceptions already scheduled above: P2/P3 land inside R4-6; P4 requires R1-3 to have landed (same file). The efficiency plan is not an open invitation to interleave — items from it run in this slot unless Ron explicitly pulls one forward.
8. **M9 → M10 (a/b/c) → M11**, unchanged, per `agent_docs/phase-4-gui-implementation-plan.md`.
9. **After M11:** feature work per `agent_docs/09-post-m11-feature-roadmap.md`.

---

## 2. R1 — Beta ship-blockers

### R1-1 — Wizard "Back" from Step 5 lands on a dead Working screen; re-run silently discards analysis (HIGH)

**Finding.** `Sources/CupricAspectApp/Shells/WizardShellView.swift:341` enables Back on Step 5 (`backEnabled = step > 1 && step != 4`); Back decrements to Step 4 (`:429-430`), which renders `Step4WorkingView` unconditionally (`:247-248`). Step 4 is only exited by `onChange(of: runModel.phase)` transitions that have already fired. On arrival, `runModel.phase` is `.finished` (or `.idle` on the recovery path), so: Cancel no-ops (`AnalysisRunModel.cancel()` guards `phase == .running`), the primary button is disabled, and Back is disabled on Step 4. The only escape is relaunching the app; unsaved review verdicts since the last autosave are lost. Every completed flow exposes this. Second defect on the same path: once Back correctly lands on Step 3, the Step-3 primary re-runs the pipeline (`primaryAction()` `case 3` → `runModel.start(...)`, `:401-410`) with **no warning** that this discards the completed analysis and the review verdicts the user just made — a silent data loss the moment the fix opens the path.

**Fix.** Two parts, one behavior each:
1. **Skip the dead Working step.** In `WizardShellView`, make Back from Step 5 skip the Working step: when `step == 5` and `runModel.phase != .running`, Back goes to Step 3 (options), not Step 4. Equivalently: Step 4 is only a valid destination while a run is in flight — encode that in the back-navigation logic, not in the render switch. This is flow-agnostic (Step 5 → Step 3 for both the analyze/write flow and the normalize flow — the normalize Step 5 is the Inspector, same navigation).
2. **Confirm before a destructive re-run.** Returning to Options is itself non-destructive — the completed results and in-memory review verdicts survive the navigation. The loss happens only on re-run. Guard the Step-3 primary ("Start") so that, when a completed analysis/review or a built normalization session already exists, pressing it raises a confirmation — "Re-run the analysis? This discards the current results and N review decisions." — with **Re-run** (proceeds and discards) and **Cancel** (aborts, existing data untouched). Same guard on the normalize flow's re-run (discards the current normalization session and Inspector outcomes). A fresh Step 3 with no prior run must not prompt.

**Acceptance.** From a completed analyze, write, and normalize flow: press Back on Step 5 → land on Step 3 with options intact, the primary enabled, and the existing results/verdicts retained (navigating Step 5 → 3 → 5 without re-running shows the same review). Pressing Start again warns that re-running discards the current analysis and N review decisions; Cancel aborts and keeps the data, Re-run proceeds. A first-time Start (no prior run) does not prompt. No reachable state renders Step 4 without a live run.

**Tests.** Wizard step-navigation logic is in the view today; extract the `backTarget(from:phase:)` decision into a small testable function (in the shell file or a `WizardNavigation` helper) and unit-test: `(step 5, .finished) → 3`, `(step 5, .idle) → 3`, `(step 3, *) → 2`, Step-4 in-flight unchanged. Extract the re-run-guard decision the same way (e.g. `needsRerunConfirmation(action:phase:hasReview:)`) and unit-test: completed run with verdicts → prompt; normalization session present → prompt; fresh options, no prior run → no prompt.

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

### R1-8 — Options-page vision model is read-only; no per-run override (MEDIUM)

**Finding.** `Step3OptionsView.swift:102-122` (`modelCard`) renders the resolved model tag as static text (`options.resolvedModel`); the only way to change the model is Settings (`SettingsSheet.swift:171-215`), which writes through to the shared `config.json` (FR4-056) — a persistent config change, not a one-off. A tester who wants to try a different vision model for a single batch (e.g. compare a larger model on one folder) either has no path or must permanently mutate the CLI-shared default. The picker mechanics already exist in `SettingsModel`/`SettingsSheet` and the tag list already comes from `listInstalledVisionTags`.

**Fix.** Make the Step-3 "Vision model" card a dropdown (same menu-over-installed-vision-tags UI as Settings), but scoped as a **one-time override for this run only** — it does **not** write `config.json`. Add an optional `modelOverride` to `AnalysisOptions`, default nil (= use the resolved config model); when set, thread it as a CLI-equivalent override in `buildConfiguration` (the model override belongs on `RunConfigurationOverrides`, same precedence slot the CLI `--model` flag uses — GUI choices are CLI-equivalent overrides, invariant 13). Label it as a session override (e.g. a small "this run only" caption) so it reads as distinct from the Settings default. Reuse the installed-tag list and the unavailable-model flagging; do not re-implement the probe. The preflight badge continues to reflect the effective (override-or-resolved) model.

**Acceptance.** On Step 3, the model card opens a dropdown of installed vision-capable tags; picking one changes the model used for this run and the preflight re-checks against it; `config.json` is unchanged (verify the Settings default and the file are untouched). Leaving it alone uses the resolved config default exactly as today. The override does not persist across imports/relaunch.

**Tests.** Unit-test that `AnalysisOptions.buildConfiguration` carries `modelOverride` into the resolved configuration's model when set and falls back to the resolved config model when nil (resolver-precedence style, per the existing config tests). The tag-list/menu is presentation; cover the override→resolution mapping, not SwiftUI.

### R1-9 — XMP conflict policy is invisible in the GUI; Advanced must expose it with the merge default (MEDIUM)

**Finding.** The GUI never surfaces the XMP conflict policy: `ExportModel` (`ExportModel.swift:75-114`) writes with `ResolvedApplySessionConfiguration.builtInDefaults`, whose `xmpConflictPolicy` is `.backupAndMerge` (`NormalizationConfiguration.swift:414`) — correct and safe, but the user can't see or confirm it, and the Step-3 Advanced card (`Step3OptionsView.swift:170-234`) only exposes GPS / existing-sidecars / concurrency. Testers reasonably fear the tool overwrites their Lightroom/Capture One keywords; the always-on merge behavior is real but unstated at the point of decision. (Design-doc drift note: the design lists a RAW+JPEG PAIRING control in Advanced that the code does not render — reconcile in the same pass, see R2/design update.)

**Fix.** Add an **EXISTING XMP** control to the Step-3 Advanced disclosure, mapping one-to-one onto Core `XMPConflictPolicy` (`fail` / `merge` / `backup-and-merge`; invariant 13 / FR4-044 — no invented values), **defaulting to `backup-and-merge`** (the current Core built-in — merges new keywords into the existing `.xmp` after writing a timestamped backup; existing keywords are always preserved). Thread the selection through `ExportModel`'s configuration instead of hardcoding `builtInDefaults` (add an `xmpConflictPolicy` input resolved the same way the CLI resolves `--existing-xmp`). Add a one-line caption making the behavior explicit at the point of decision, e.g. "Merge preserves keywords already in your `.xmp`; Backup & Merge writes a `.xmp.bak` first." This is the GUI surfacing of the always-on merge behavior the phase-4 plan already verified end-to-end — it does not change the default, it makes it visible and adjustable.

**Acceptance.** Step-3 Advanced shows an EXISTING XMP control defaulting to Backup & Merge; the write path uses the selected policy (verify a `.xmp` with pre-existing foreign keywords is preserved under merge/backup-and-merge and a `.xmp.bak` is written under backup-and-merge). The default matches the CLI/Core built-in exactly — no divergence (invariant: GUI and CLI defaults never diverge, FR4-056 spirit).

**Tests.** Unit-test the export configuration carries the selected `XMPConflictPolicy` (default `.backupAndMerge`) into `ResolvedApplySessionConfiguration`; keep the existing merge-preservation Core tests green (they already assert foreign-keyword retention and backup creation).

### R1-10 — Offer post-write cleanup of intermediate sidecars and run artifacts (MEDIUM)

**Finding.** After a Write XMP / Write normalized XMP run, the folder is left with the `.ai.json` raw sidecars and the run's `batch-progress-*.jsonl` / `batch-summary-*.json` / `xmp-export-*` / `normalization-*` artifacts alongside the delivered `.xmp` files. The final artifact the user wants is the `.xmp`; the intermediates are clutter once the XMP is written. The CLI already has a hardened, deliberately-narrow `cleanup` (`Sources/AISidecarCore/Cleanup/ArtifactCleanup.swift` — removes owned raw sidecars + progress logs/reports/summaries; never touches source images, `.xmp`, `.xmp.bak` backups, the derivative cache, debug derivatives, or reusable normalization session JSON), but the GUI exposes no way to run it. Alpha testers have no one-click way to tidy a folder after export.

**Fix.** Add an opt-in **"Remove intermediate sidecars & run files after writing"** checkbox in the change-plan confirmation sheet (`ChangePlanSheet.swift`, beside the "Write N sidecars" button — the surface shared by both the review→write and normalize→write flows), **off by default**. When checked, and only after a **fully successful** write (no failed targets), run Core `ArtifactCleanup` over the run's artifact directory — the output directory when set, otherwise the source folder — honoring the import's recursive setting. GUI orchestration only: `ExportModel` gains a `cleanupAfterWrite` input and calls `ArtifactCleanup().run(rootPath:recursive:dryRun: false)`; no cleanup logic moves into the view (invariant 13). Cleanup must be reported (fold the removed count into the written banner: "… · N intermediate files removed") and must be non-fatal — a cleanup error after a successful write is a warning, never a rollback of the delivered XMP. A partial/failed write skips cleanup entirely (never drop provenance for images that didn't export). Add a caption stating the consequence: "Deletes the `.ai.json` sidecars and batch logs this run created — your photos, `.xmp` files, and backups are untouched. You'll need to re-analyze to review these images again." (`.ai.json` removal drops the FR4-049 `xmp_export` provenance and the audit trail — hence off by default and explicit.)

**Acceptance.** With the box checked, a successful write leaves the `.xmp` outputs (and any `.xmp.bak`) in place and removes the run's `.ai.json` sidecars and batch/report/summary artifacts from the artifact directory; the banner reports the count. The normalization **session JSON is preserved** (Apply Prior Session still works afterward). With the box unchecked, nothing is deleted (today's behavior). A write with any failed target performs no cleanup. Unchecking is the default on every new plan.

**Tests.** Model-level: a successful `ExportModel` write with `cleanupAfterWrite == true` invokes `ArtifactCleanup` over the correct root and surfaces the removed count; with a failed target, cleanup does not run; with the flag false, cleanup does not run. Reuse the existing `ArtifactCleanupTests` for the Core deletion semantics (owned-only, session-preserving) — do not duplicate them.

### R1-11 — Settings has no default for concurrency (MEDIUM)

**Finding.** The Settings `CONFIGURATION` section (`SettingsSheet.swift:242-317`) lets the user set persistent defaults for render mode, GPS context, and existing-sidecar policy, but exposes **no** control for `stage_concurrency`; `SettingsModel` (`SettingsModel.swift:31-44`, `reload()` `:57-77`) never reads or writes it. The config layer already supports the key end-to-end — `AppConfig.stageConcurrency` ⇄ `"stage_concurrency"` (`AppConfig.swift:25/78`), resolved default = the Apple-Silicon performance-core count (`RunConfiguration.swift:268-275`) — and the per-run Options stepper already seeds itself from the resolved value (`AnalysisOptions.loadResolvedDefaults`, `AnalysisRunModel.swift:34`). So a tester can override concurrency for one run but cannot set a persistent default the CLI and every GUI run share, unlike mode/gps/existing which all have Settings defaults. On a memory-constrained Mac a tester who wants a permanently lower concurrency has no path short of hand-editing `config.json`.

**Fix.** Add a `CONCURRENCY` control to the Settings `CONFIGURATION` section mapping onto `stage_concurrency` (a 1–8 stepper matching the Options-page control, styled to the section). Add a `stageConcurrency` property and a `setConcurrency` write-through to `SettingsModel` — `write("stage_concurrency", …)` via `ConfigFileEditor.merge`, the same pattern as `setMode`/`setExisting`. No Options-page change is needed: it already reads `resolved.stageConcurrency`, so the new default flows through automatically. Validate `> 0` before writing (the resolver rejects zero).

**Acceptance.** Setting a default concurrency in Settings writes `stage_concurrency` to `config.json` (hand-added keys preserved), a subsequent CLI resolve reflects it, and a fresh import's Options page shows that value as its concurrency default. Leaving it unset behaves exactly as today (resolver default = performance-core count).

**Tests.** A `SettingsModel` write-through test (writes the key, preserves unknown keys) mirroring the existing `setMode`/`setExisting` tests; a resolver round-trip asserting `stage_concurrency` survives the merge.

### R1-12 — Settings has no default for XMP treatment, and Options can't inherit one (MEDIUM)

**Finding.** The XMP conflict policy has no Settings default: `SettingsModel` has no `xmpConflictPolicy` property or writer and the `CONFIGURATION` section exposes no control, even though the config layer supports `xmp_conflict_policy` (`AppConfig.swift:35/86`; enum `XMPConflictPolicy` = `fail`/`merge`/`backup-and-merge`, `XMPExportConfiguration.swift:11-15`; built-in default `.backupAndMerge`). A compounding gap: the R1-9 per-run Options control does **not** seed from config — `AnalysisOptions.xmpConflictPolicy` is initialized to the hard-coded built-in (`AnalysisRunModel.swift:17`) and `loadResolvedDefaults()` never touches it (`:27-35`), unlike concurrency, which is seeded (`:34`). So even a hand-edited `xmp_conflict_policy` in `config.json` is ignored by the GUI today. A Settings default plus the seeding fix closes both gaps and keeps GUI and CLI from diverging (FR4-056 spirit).

**Fix.** Two parts.
1. Add an `EXISTING XMP` control to the Settings `CONFIGURATION` section over `XMPConflictPolicy.allCases` (Fail / Merge / Backup & Merge), defaulting to the Core built-in `.backupAndMerge`, with an `xmpConflictPolicy` property and a `setXMPConflictPolicy` write-through (`write("xmp_conflict_policy", …)`). Honor the cross-field constraint: `backup-and-merge` requires `backup_sidecars == true` (`ConfigurationResolver` validation `:818-819`). Since `backup_sidecars` defaults true and Settings does not expose it, all three policies remain valid — do not write a policy that would violate it.
2. Seed the Options control from config: add one line to `loadResolvedDefaults()` setting `xmpConflictPolicy` from the resolved configuration, so the Settings default (or a hand-edited config value) flows into the per-run Advanced control exactly as mode/gps/existing/concurrency already do. The R1-9 default-equality invariant still holds — with no config value the resolver returns the built-in, so `AnalysisOptions().xmpConflictPolicy == builtInDefaults.xmpConflictPolicy`.

**Acceptance.** Setting a default XMP treatment in Settings writes `xmp_conflict_policy` to `config.json` (unknown keys preserved), a CLI resolve reflects it, and a fresh import's Options → Advanced `EXISTING XMP` control shows that value. Leaving it unset shows Backup & Merge (the Core built-in) in both Settings and Options, matching the CLI. The R1-9 per-run override still overrides the default for a single run without changing `config.json`.

**Tests.** `SettingsModel` write-through for `xmp_conflict_policy`; a resolver-precedence test that `loadResolvedDefaults()` seeds `xmpConflictPolicy` from a config value and falls back to `.backupAndMerge` when absent; keep the R1-9 default-equality test green.

### R1-13 — "Existing sidecars" control reads as XMP handling; relabel it as the program's own sidecars (MEDIUM)

**Finding.** The Options → Advanced grid places `EXISTING SIDECARS` (`Step3OptionsView.swift:290`; `ExistingPolicy` skip/overwrite/fail, governing the program's own `.ai.json` raw sidecars) directly beside `EXISTING XMP` (`:299`; `XMPConflictPolicy`, governing the `.xmp`), and the disclosure hint lists both as "existing sidecars · existing xmp · concurrency" (`:269`). Settings mirrors the same bare "Existing sidecars" label (`SettingsSheet.swift:290`). Testers read "Existing sidecars" as XMP handling and fear the tool overwrites their Lightroom/Capture One keywords, when the control only decides whether analysis re-writes its own `.ai.json` intermediates. The word "sidecar" is overloaded in the GUI: it means `.ai.json` in Settings/Options but `.xmp` in the change-plan sheet (`ChangePlanSheet.swift:75/133/136/138`).

**Fix.** Relabel the `ExistingPolicy` control everywhere it surfaces so it unambiguously names the program's own analysis files, not XMP — recommended "Existing `.ai.json` sidecars" (or "Existing analysis sidecars (`.ai.json`)") on both the Options → Advanced control and the Settings row, and update the disclosure hint to "existing .ai.json · existing xmp · concurrency". Add a one-line caption distinguishing it from `EXISTING XMP` (e.g. "Governs the tool's own `.ai.json` analysis files, not your `.xmp`."). **Labels and caption only — no enum, CLI-mapping, or default change.** *(STOP: maintainer wording decision — the exact strings are Ron's call; the requirement is only that the control stop reading as XMP handling.)* Optional consistency pass, deferrable to R2 if it widens the diff: change the change-plan sheet's bare "sidecar" (which means `.xmp`) to "XMP sidecar" so the same word never denotes two things.

**Acceptance.** On both the Options → Advanced disclosure and the Settings `CONFIGURATION` section, the existing-`.ai.json` control names the file type explicitly and no longer reads as XMP handling; `EXISTING XMP` remains the only XMP-facing control. No functional change — the enum, CLI mapping (`--existing`), and defaults are untouched.

**Tests.** Presentation-only; no unit test asserts label strings. If a snapshot/label test exists, update it deliberately and say so; otherwise the R1 manual GUI pass covers it.

### R1-14 — Seconds-per-image reads wrong after switching model and re-running (MEDIUM)

**Finding.** The Working screen's "Rate" stat (`Step4WorkingView.swift:122`) shows `runModel.secondsPerImage`, computed as `elapsed / writtenCount` (`AnalysisRunModel.swift:110-114`), where `elapsed` is total wall-clock across **all** processed records but `writtenCount` counts only `.written` ones (`:151-154` increments `done` for every record, `writtenCount` only on `.written`). The natural way to try a non-default vision model (R1-8) is to re-run an already-analyzed folder; with the default `existing = .skip` policy, previously-analyzed images return `.skippedExisting`, so `done` climbs while `writtenCount` stays low or zero. Result: the rate reads wildly inflated, or "—" when every image is skipped — precisely the "seconds-per-image is wrong when I pick a different model" symptom. The estimate references no model variable at all (verified), so the model is not the cause; the skip-vs-written denominator is. (Design resolution 7 already committed this figure to a real, smoothed seconds-per-image; this makes it correct under skips.)

**Fix.** Make the rate reflect real per-image processing time — divide `elapsed` by the number of images the run actually spent time on (e.g. `done`, or `done` minus failures), or accumulate elapsed only across `.written` images, so skipped images (≈ no model time) don't distort it. The acceptance is behavioral: a re-run against a mostly-skipped folder shows a sane rate (or a clearly-labeled "—" only when nothing was processed), not an inflated figure. *(Secondary, note only: the Step 4 "Model" stat, `Step4WorkingView.swift:130-133`, reads the cached `preflight` state rather than the live run config, so before preflight resolves it can show "—"/a stale tag while the run uses the correct override — fold into R2 unless trivially fixed here.)*

**Acceptance.** Re-running a folder whose sidecars are all/mostly skipped shows a rate consistent with the real time spent per newly-written image (or "—" only when zero images were processed), for both the default and an overridden model. A fresh all-written run is unchanged.

**Tests.** Extract the rate math into a pure function (e.g. `secondsPerImage(elapsed:done:written:failed:)`) and unit-test: all-skipped → 0/"—", not a huge number; mixed skip+write → divides by the processed count; a fresh all-written run matches today's value.

**R1 exit gate:** all fourteen items landed, `swift test` green, one manual GUI pass over analyze/write/normalize/apply + kill-relaunch-restore-export. Then proceed to B0-5 evidence, signing, and the `v0.1.0-beta.1` tag per the phase-4 plan.

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

**Implementation status (2026-07-11, post-audit):** R4-1 through R4-6 are implemented and the expanded exit gate is green (176 focused tests; 581 full-suite tests with two opt-in skips; all CLI help routes; app build; benchmark self-test; purge smoke; clean diff check). An adversarial review found and corrected boundary gaps beyond the first 541-test gate: physical file-list identity, single-image/off-mode and factual session-context results, GPS safety outside extraction, terminal vocabulary ambiguity, fail-closed imported decisions, exact XMP description matching, and cross-process active-artifact cache safety. R4-6 also completes efficiency items P2/P3. Detailed verification is recorded in plan 10. The initial R4-6 implementation's controlled 46-image comparison measured a 14–17% aggregate render-timing reduction; this offline audit verified the subsequent lease hardening with deterministic concurrency tests but did not repeat the live-model timing run.

**Second audit (2026-07-14):** an independent verification pass re-reviewed every R4 item adversarially and corrected residual gaps; R4-2 and R4-4 re-verified with no defects. Corrections: coordinate pairs signed with typographic minus/en/em dashes, `Lat … Lon …` label forms, and spelled-out `degrees North/West` forms now fail closed (invariant 3); file-list identity is physical (symlink-resolved) for both duplicate detection and grouping; the session writer no longer resurrects decision fields a review edit cleared, and re-encoding a newer-minor session preserves the writer's known status/export flags (fail-closed coercion is in-memory only); an unchanged export rerun back-fills a missing raw-sidecar stamp; plain `rdf:about` values containing `%`/`#` match literally; a concurrent same-key cache store reuses a valid leased artifact instead of failing when its encoder bytes differ; cached-hit verification hashes outside the manifest flock under the shared inode lease; and the manifest lock revalidates its inode after acquisition. Gate after corrections: 193 focused tests; 589 full-suite tests with two opt-in skips. Accepted residuals are recorded in plan 10 §R4-6.

### R4-1 — File-list entries outside the list directory collapse into one XMP group (MEDIUM)
`NormalizationInputResolver.swift:532-542` (`relativePath(for:root:)` falls back to `lastPathComponent`) feeding `groupKey(for:)` (`:412-418`): two same-base-name images from **different directories** in an absolute-path file list group as one RAW+JPEG pair — keywords union into a single `.xmp` beside whichever asset sorts first; the other image gets nothing. Fix: group key must use the resolved absolute parent directory when the entry is outside the root (never the empty-string directory). Tests: `FileListInputResolverTests` gains an out-of-root absolute-path case asserting two separate groups/targets.

**Audited result.** Grouping uses the standardized physical parent for every resolved source, including the leading-slash absolute-versus-mirrored-relative adversary. Same-directory RAW/JPEG still pair. Only colliding staged target names receive a deterministic directory-identity suffix; beside-source naming is unchanged. *Second audit:* identity is now symlink-resolved — duplicate detection and group identity use the physical path, so linked and real spellings of one file are one asset and linked/real spellings of one directory are one group (display paths come from the group's first sorted member).

### R4-2 — `user_only`/`withhold` session context blocked exactly where the model agreed (MEDIUM)
`BatchConsensusEngine.swift:270` (`applySessionContext`) skips adding the user-context decision when **any** decision with the same `(assetID, canonicalPath)` exists, regardless of status. A direct model observation of a `user_only` entry produces a *withheld* decision, which then blocks the accepted user-context decision — so `--session-event "Migration"` fails to apply precisely on assets where the model also said "migration". Fix: only skip when the existing decision is `accepted` (or user-decided); a withheld/skipped machine decision must be superseded by the user-context decision (replace or add-accepted per the session-context policy record). Tests: `SessionContextPolicyTests` gains a case with a pre-existing withheld direct decision — context still applies; determinism record updated if policy text changes.

**Audited result.** The rule applies in single-image and conservative modes, uses set-backed accepted coverage, and honors `flat_only` export flags. Off mode ignores all session context as a Phase 2 baseline. Completed `export_result` values are factual and terminal: no policy-withheld or all-conflicted context claims `applied`.

### R4-3 — GPS coordinate-term guard: broaden the regex set (MEDIUM, invariant 3)
`CandidateExtractor.swift:669-686` (`isCoordinateLikeTerm`) misses (verified by running the regexes): DMS `40°26'46"N 79°58'56"W`, cardinal-prefix `N 40.446 W 79.982`, integer pairs `40, -79`, UTM `UTM 17T 589500 4477000`. In observed-tags mode there is no vocabulary backstop, so a model echoing coordinates can reach `dc:subject`. Fix: extend the pattern set for DMS (degree/quote/double-quote symbols incl. Unicode primes), cardinal-prefixed decimal, bare signed numeric pairs, and UTM; keep patterns conservative (require two coordinate-ish tokens or explicit N/S/E/W context — don't block "35mm" or "Route 66"). Tests: table-driven cases for each caught format plus non-coordinate negatives ("50mm f/1.8", "Apollo 11", "Room 404").

**Audited result.** Precompiled checks live in one `KeywordSafetyPolicy` used at extraction, session preflight, review, and final planning. Coordinate syntax and GPS metadata (`GPS fix`/reading/derived location) fail closed, while a visibly depicted GPS unit/receiver remains a legitimate object tag. Final planning creates an auditable skip for unsafe imported decisions. *Second audit:* signed pairs accept typographic minus and en/em dashes (which survive NFC normalization), and label-prefixed (`Lat 40.446 Lon -79.982`) and spelled-out (`40.446 degrees North, 79.982 degrees West`) forms are blocked. MGRS, plus codes, and geohash remain outside the specified format set.

### R4-4 — Vocabulary validation: duplicate/ambiguous flat keywords (MEDIUM, invariant 10 seam)
`VocabularyValidator.swift:49-72` never cross-checks flat keywords; `VocabularyIndex.swift:117-125` `insertLookup` silently first-wins. Two entries sharing a folded `flat_keyword` (or a synonym of A equal to B's flat keyword) resolve to the lexicographically-first canonical path — the wrong `lr:hierarchicalSubject` with no warning, while the separator-fold map *is* ambiguity-guarded. Fix: (a) validator reports duplicate folded flat keywords and synonym↔flat collisions as errors (or warnings + ambiguity-guard, decide with maintainer: erroring may break existing vocabularies — prefer validation **error** for new/edited vocabularies and an ambiguity-guarded lookup like `insertSeparatorLookup` at runtime for robustness); (b) `insertLookup` gains the same ambiguity-set mechanism as separator lookups. Tests: mirror `testSeparatorInsensitiveFallbackDoesNotResolveAmbiguousAliases` for exact-fold.

**Audited result.** A primary ambiguity is terminal and cannot fall through plural/punctuation matching. Separator fallback treats canonical, flat, and synonym owners equally; any multi-owner fallback key is ambiguous. Exact full canonical paths remain authoritative, and the bundled shared `Birds` label is pinned as ambiguous.

### R4-5 — Session/edit hardening lows
- **Pipe in user edits** (`SessionReview.swift:36-47`; GUI `ReviewModel.swift:237-243`): edited keywords bypass the `containsHierarchySeparator` guard — a literal `|` keyword exports. Reject/strip `|` in `SessionReview.applying` (Core-level, so CLI session edits are covered too) and surface the rejection in the GUI.
- **Forward-compat decode** (`NormalizationSessionDocument.swift:752-765`): 1.x acceptance + strict enum decoding = future minor versions fail wholesale. Make additive enums decode-tolerant (unknown-case rawValue preservation or explicit `unknown` case that fails only the affected decision, not the document) — respects invariant 8's spirit both directions.
- **Stamp path by construction** (`NormalizedXMPChangePlanner.swift:217` → `XMPExportPipeline.stampSourceSidecars:598`): `sourceSidecarPath` falls back to the source-image path when no `.ai.json` exists; only `RawSidecarExportStamp`'s JSON-object guard (whose error is `try?`-swallowed) protects invariant 2. Emit nil instead of a non-`.ai.json` path and skip stamping; log the skip.
- **Merge-target selection** (`XMPDocumentParser.swift:162-181`): prefer `rdf:about=""` or about matching the source over `descriptions.first` when no managed fields exist.
- **Export-stamp serialization drift** (`RawSidecarExportStamp.swift:44-65`): `JSONSerialization` re-encodes the whole sidecar (escaped slashes, float drift like `0.08 → 0.080000000000000002`) diverging from deterministic `JSONCoding` output. Route the rewrite through the merge-preserving `JSONCoding` path used by schema-evolution rewrites.

**Audited result.** Every enum directly on a per-asset decision tolerates/preserves unknown raw values and forces only that decision withheld; review and planning cannot re-enable it. Unknown JSON fields survive the designated session writer. Nested observation/provenance and audit-only enums remain a documented strict compatibility boundary. `rdf:about` matching now uses exact decoded terminal filenames (including percent-encoded URLs and Windows paths), never raw suffixes. *Second audit:* the writer's PW-012 merge treats schema-owned decision keys as writer-owned, so a review edit's cleared `canonical_path`/`hierarchical_keyword` stay cleared while unknown fields still survive; the fail-closed coercion of a newer minor version's known status/export flags is in-memory only and re-encodes the original values; an unchanged export rerun back-fills a missing raw-sidecar stamp (presence-checked, so stamped sidecars are not churned); and plain `rdf:about` values containing `%`/`#` match literally before URL decoding.

### R4-6 — Derivative-cache cross-process safety (shared with efficiency plan P2/P3)
`DerivativeCache.swift:24` protects the manifest with an in-process `NSLock` only; GUI + CLI share `~/Library/Caches/aisidecar/derivatives` and interleave load-modify-save (lost entries → orphaned artifacts that escape the byte-cap accounting, FR1-018a silently unenforced). Fix options (pick with maintainer): an `flock`-based file lock around manifest read-modify-write (simple, sufficient), or per-entry manifest files. Coordinate with efficiency-plan P2/P3 (manifest churn) — one redesign, not two. Also R4-6b (low): `evictIfNeeded` (`:256-272`) protects only the just-stored artifact; with `stage_concurrency > 1` and a small user-set cache cap, prepared-ahead derivatives can be evicted before the model loop reads them — protect the current batch's planned artifacts or floor the cap at the working-set size.

**Audited result.** Encode/hash is staged outside the flock; final rename and manifest mutation are one locked transaction. Shared locks lease active artifact inodes across processes, while replacement/eviction/purge require nonblocking exclusive locks. Lease counts release per consumer and all owning pipelines enforce the cap at teardown. Manifest cache invalidation includes inode, failed deletes remain accounted, and purge removes only aged project-owned temps. *Second audit:* a same-key store that finds a valid on-disk artifact reuses it (returning the on-disk provenance) even when its own encoder bytes differ, instead of failing against an active lease; cached-hit verification hashes outside the flock under the shared lease, so warm-path readers no longer serialize whole-file I/O; and the manifest lock revalidates its inode after acquisition. Accepted residuals (documented, not scheduled): a crash between artifact rename and manifest save leaves one manifest-untracked artifact invisible to the byte cap until the next purge or same-key store re-tracks it, and external deletion of the held lock file cannot be fully defended by advisory path locks.

---

## 6. Explicitly deferred (recorded, not scheduled)

- **Two-instance file coordination** beyond the R2-7 known-issues note (single-instance lock) — M11 if ever needed.
- **fsync-before-rename** in `AtomicFileWriter` (power-loss window) — measure cost first; sidecars are regenerable, XMP writes already validate post-write.
- **Backup/restore TOCTOU vs. concurrent Lightroom edits** (`XMPExportPipeline.swift:328-404`) — inherent without file locking; single-user tool; revisit only with real-world reports.
- **Benchmark harness nits** (median bias, `failed_sidecar_count` missing from the markdown table, child-exit-code not flagged) — fold into the next benchmarking milestone if M9 calibration work reopens.
- **EXIF orientation 0 strictness** (`RenderRecipe.swift:46-54`) — deliberate; revisit if real-world images hit it.
- **Per-file `startedAt` at plan time** inflating `durationMs` (`AnalyzePipeline.swift:402-403`) — reporting-quality only.
- **`RawJSONSidecar.swift:126` `try?` on `subject_isolation`** — verified no data loss on rewrite.
- **Same-major nested normalization enum tolerance** (R4 post-audit): direct per-asset decision policy enums now preserve unknown raw values and fail only that decision closed, but enum values nested in observations/provenance and audit-only records still reject the document. Full PW-012 coverage there requires lossless wrappers across shared Phase 2/3 record types and is deferred to a dedicated schema-adapter change; schema-major-1 writers must not emit new nested enum values until it lands.
- **Preflight interruption** (R3 audit, 2026-07-10): `runner.prepare` (`/api/tags`, `/api/show` probes, `/api/version`) runs before the first monitor check and holds no cancellation registration, so Ctrl+C/GUI cancel during preflight waits out the configured timeout per request (CLI escalation still applies; parent-task cancellation propagates). R3-2/R3-4 scoped cancellation to model requests — extend to preflight only if it bites in practice.
- **Settings tag-list probe timeout** (R3 audit, 2026-07-10): the GUI Settings model dropdown probes via `listInstalledVisionTags` with the built-in 180 s default rather than the configured `model_timeout_seconds`; run preflight is fully covered. Cosmetic inconsistency.

## 7. Verification

Every R-milestone ends with: `swift test` green; `swift run aisidecar --help`; `swift build --product CupricAspect`; the R1 gate additionally requires the manual GUI pass listed there. R3-8 (artifact names) and R3-1 (exit codes) change observable behavior: update `agent_docs/testing-and-verification.md`, the README, and golden tests deliberately, and say so in the commits. New config keys (R3-5) go into `aisidecar.config.example.jsonc` + the Settings sheet per the M8a pattern.

## 8. Traceability

| Review finding | Work item |
|---|---|
| GUI H1 (Back dead state) + alpha: re-run data-loss confirmation | R1-1 |
| Alpha: Options per-run model override (dropdown) | R1-8 |
| Alpha: Options XMP conflict policy visible, backup-and-merge default | R1-9 |
| Alpha: opt-in post-write cleanup of intermediate sidecars/artifacts | R1-10 |
| Alpha: Settings default for concurrency | R1-11 |
| Alpha: Settings default for XMP treatment (+ Options inherits it) | R1-12 |
| Alpha: relabel the program's `.ai.json` sidecar control (vs XMP) | R1-13 |
| Alpha: seconds-per-image wrong on skip-heavy re-run | R1-14 |
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
| XMP M1 (file-list grouping) | R4-1 — done, post-audit verified 2026-07-11 |
| XMP M2 (user_only inversion) | R4-2 — done, post-audit verified 2026-07-11 |
| XMP M3 (GPS regex) | R4-3 — done, post-audit verified 2026-07-11 |
| XMP M4 (vocab ambiguity) | R4-4 — done, post-audit verified 2026-07-11 |
| XMP L2/L3/L4/L6 + Core #17 (stamp serialization) | R4-5 — done, post-audit verified 2026-07-11 |
| CLI #6/#7 (cache cross-process, eviction) | R4-6 — done with P2/P3, post-audit verified 2026-07-11 |
