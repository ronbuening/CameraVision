# GUI Improvements Plan — Accessibility, Review Ergonomics, Error Surfaces

Version: 1.0
Date: 2026-07-21
Scope: `Sources/CupricAspectApp` (presentation/state only — invariant 13; any new data need is a Core seam request, not GUI parsing)
Audience: junior engineer or Sonnet-level coding agent executing one work item at a time.

**Scheduling.** Secondary to `agent_docs/16-refactor-and-optimization-plan.md`: nothing here starts before plan 16's Tranches A–C are complete unless Ron explicitly pulls an item forward. These items do not gate M9, but I1/I2 touch `Step5ReviewView`, which plan 16 C15 splits and B6 optimizes — land those first to avoid churn. Items were screened against `agent_docs/09-post-m11-feature-roadmap.md` (F1–F13) and the M9–M11 ledger: nothing below duplicates planned scope (multi-root import, similarity, vocabulary manager, database mode, Studio shell are all *not* here).

**Provenance.** Findings from the 2026-07-21 GUI review; line anchors captured that day — file + symbol references stay authoritative over drifted line numbers.

## Ground rules

1. `agent_docs/invariants.md` binds every item — especially 13 (no processing in the GUI), 16 (behavior changes ship with tests in `Tests/CupricAspectAppTests`, offline/deterministic), 17 (one item at a time).
2. Visual changes follow design doc 07's tokens (`DesignSystem/Theme.swift`); no new colors or type ramps outside the token set.
3. One item per branch/PR; `swift test` green before and after.

## Execution order

| Order | Item | Why first |
|---|---|---|
| 1 | I7 Move quality grading to the Step 5 write boundary | Corrects the workflow before I1/I2 revise and test the same Step 5 surfaces |
| 2 | I1 Accessibility pass | Highest remaining user value; self-contained; touches many files, so landing it before other view edits minimizes conflicts |
| 3 | I2 Review filter/search | Biggest ergonomic win; establishes the filter-bar component I3 builds on |
| 4 | I3 Keyboard triage | Rides on I2's row focus model |
| 5 | I4 Inline error component | Unifies surfaces the earlier items touched |
| 6 | I5 ETA stat · I6 Drop feedback | Small independent wins, any order |

---

### I7. Move quality grading to the Step 5 write boundary

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Medium (session-preview and export-option timing)

**Problem (verified).** Step 2's **Assess image quality** choice controls whether the model records an assessment
in raw sidecars. Step 3 separately asks whether to export derived quality metadata to XMP. Although those are
different operations, presenting the grading switch before analysis makes it look as if the Step 2 selection was
lost and asks for a write decision before the user has reviewed the results. The actual guarded XMP operation
already starts from Step 5 and is fronted by the authoritative dry-run change plan.

The current early placement is partly structural: `WizardFlowModel.handleRunPhase` passes the Step 3 grading
overrides into `ReviewModel.buildSession` or `NormalizationModel.run`, and session-only normalization uses an
enabled grading configuration to persist preview tiers, explanations, and quality keywords in
`xmpWritePlans`. Apply-time grading already re-resolves the current raw-sidecar contributors and current XMP, so
this preview dependency is not a reason to make the user commit to writing quality metadata in Step 3.

**Interim behavior (2026-07-23).** Until I7 lands, turning on Step 2 assessment defaults the separate Step 3
grading switch to on. Turning assessment off does not clear the retained grading choice, and the effective
configuration still forces grading off while assessment is disabled.

**Change.**
1. Keep Step 2 **Assess image quality** and Step 3 Advanced **Quality scan** (`Normal` / `High quality`) unchanged:
   they control model work. Remove the **Quality grading** group from Step 3 for analyze/write/normalize runs.
2. Present the grading master switch, star-rating opt-in, and culling-metadata conflict policy on both Step 5 XMP
   write surfaces (`Step5ReviewView` for Analyze & write XMP and `NormalizationInspectorView` for Normalize),
   immediately beside or immediately before the corresponding Write XMP action. Analyze-only Step 5 shows no
   grading controls.
3. Keep Apply Session's grading controls on its current Step 3. That path performs no analysis or Step 5 review;
   its Step 3 is already the write-configuration boundary.
4. Seed the moved controls from the same resolved `xmp_quality_*` defaults and retain edits across non-destructive
   Step 2/3/5 navigation. The Step 2 assessment choice only governs whether grading controls are available; it
   must not silently select or clear the separate write choice.
5. Decouple session construction from the pending write choice. Review must continue to show the raw quality
   assessment independently of grading. Do not persist transient Step 5 export intent into a saved normalization
   session merely to obtain a preview. If pre-write tier presentation remains desirable, expose or reuse a
   read-only Core derivation that does not claim scalar conflict outcomes; otherwise show derived tiers first in
   the authoritative dry-run change plan.
6. At **Write XMP**, project the current Step 5 controls into `ExportModel.plan`. The resulting dry-run plan remains
   the source of truth for quality keywords, labels, urgency, flags, optional ratings, conflict handling, and the
   eventual confirmed write. Closing the plan, changing a grading control, and planning again must replace the
   stale plan.

**Tests.**
- Pin the visibility matrix: write/normalize Step 5 show grading controls; analyze Step 5 does not; Apply Session
  retains its existing controls.
- Pin that Step 3 no longer owns or renders the grading group, while its quality-scan mode still maps into the
  analysis configuration.
- Verify assessment-off makes Step 5 grading unavailable without clearing retained grading choices.
- Verify session construction is independent of the pending XMP grading switch and still loads raw assessment
  records for Review.
- Verify `WizardFlowModel.startExport` passes the latest Step 5 grading overrides into the dry-run plan for both
  write and normalize, and that changing the controls causes a replacement plan.
- Run focused GUI tests, full `swift test`, `swift build --product CupricAspect`, formatting, and the manual
  Step 2 → Step 5 write/normalize/apply navigation matrix.

**Acceptance.** No analyze-capable path asks whether to write quality metadata before Step 5. Step 5 places the
choice next to the XMP action, the reviewed dry-run plan accurately reflects the latest selection, raw assessment
review remains available without grading, and all XMP writes retain the existing guarded export pipeline.

---

### I1. Accessibility pass over the interactive surfaces

- **Priority:** HIGH · **Effort:** Medium · **Risk:** Low

**Problem (verified).** Only `ApertureView` and `Step4WorkingView` carry any accessibility annotations. Specifically:
- Icon-only buttons have no `accessibilityLabel`: title-bar theme toggle and settings gear (`Shells/WizardShellView.swift` ~:191-216), vision-tags refresh and copy-pull-command buttons (`Features/Settings/SettingsSheet.swift` ~:156-166, :208-216).
- Review keyword chips encode the verdict purely as color + a `✓/+/~` glyph (`Features/Review/Step5ReviewView.swift` `chipView` ~:327-356): VoiceOver cannot distinguish approved/rejected/deferred, and color-blind users lose the distinction.
- Asset state is color-only in the grid dots (`Features/Import/AssetGridView.swift` `stateDot` ~:79-93) and the queue badges (`Features/Import/Step1PhotosView.swift` `stateBadge` ~:290-307).

**Change.**
1. Add `accessibilityLabel` (and `accessibilityHint` where the action isn't obvious) to every icon-only control in the four files above; sweep the rest of `Features/` for others (grep for `Image(systemName:` inside `Button`).
2. Chips: add `accessibilityValue` carrying the verdict name, and a non-color redundant cue visible to sighted users (the existing glyph is a start — give each verdict a distinct chip *shape or border treatment* from the token set, e.g. filled/outlined/dashed, so state survives color-blindness). Group each chip as one accessibility element (label = keyword, value = verdict, traits = button).
3. State dots/badges: attach `accessibilityLabel` with the state name; add a redundant SF Symbol or text initial next to the dot at the grid cell level where layout allows (follow doc 07 spacing tokens).
4. Verify the wizard step rail and footer navigation announce step names and enabled/disabled state.

**Tests/verification.** Accessibility annotations aren't directly unit-testable in SwiftPM; where logic decides a label/value string (verdict → description), put the mapping in a small testable helper and unit-test it. Manual pass: VoiceOver over Steps 1–5 and Settings; Accessibility Inspector audit shows no unlabeled interactive elements on those screens. Record the audit result in the PR.

**Acceptance.** No unlabeled interactive control on Steps 1–5, Settings, or the title bar; chip verdicts distinguishable without color; VoiceOver reads keyword + verdict on chips.

### I2. Filter, search, and sort for the review step

- **Priority:** HIGH · **Effort:** Medium-Large · **Risk:** Medium (interacts with plan 16 B6 row caching)

**Problem.** `Step5ReviewView` renders every asset in one `LazyVStack` with only global approve-all/reject-all. There is no way to narrow to rejected-only, low-confidence, a quality tier, or a keyword across a large batch — the reviewer scrolls linearly. The Normalization Inspector already ships the pattern to follow (`Features/Normalize/NormalizationInspectorView.swift` `filterBar` ~:156-187: outcome + stage filters).

**Change.**
1. Add a filter bar to Step 5 (visually consistent with the Inspector's): verdict filter (any/approved/rejected/deferred/undecided), a "needs attention" toggle (assets with rejected or low-confidence candidates), a quality-tier filter (shown only when quality data is present — source: the Core `ReviewQualityLoader` seam from plan 16 C13), and a free-text keyword search matching candidate text (case/diacritic-insensitive fold — reuse Core's folding via a Core-exposed helper; do **not** reimplement folding in the GUI).
2. Sort control: default current order (path), plus by undecided-count and by quality tier when present.
3. Filtering/sorting operates on the cached rows from plan 16 B6 (filter the materialized array; never rebuild rows per keystroke — debounce search input).
4. Approve-all/reject-all become scope-aware: they apply to the *filtered* set, with the button title reflecting it ("Approve shown (42)") — this must be unmistakable, since a hidden global apply would be a data-destroying surprise.

**Tests.** `ReviewModel` (or the flow model from 16 C14) gains pure filter/sort functions — unit-test each filter, the search fold, the debounced text path (logic level), and scope-aware bulk-apply counts. Snapshot the empty-filter-result state.

**Acceptance.** A 1,000-asset session can be narrowed to rejected-only or a keyword in one interaction; bulk actions state their scope; filters compose; clearing filters restores the full list; no per-keystroke row rebuilds.

### I3. Keyboard triage for review

- **Priority:** MEDIUM · **Effort:** Medium · **Risk:** Low-Medium

**Problem.** Verdicts require clicking each chip or its context menu (`Step5ReviewView` ~:334-375). On a triage-heavy screen this is the throughput bottleneck; there are no shortcuts at all.

**Change.**
1. Introduce row focus (keyboard-navigable with ↑/↓) in the review list; visible focus ring from the token set.
2. Shortcuts on the focused row's selected chip (←/→ to move chip selection): `A` approve, `R` reject, `D` defer, `U` undecided; `⇧` variants apply to all chips in the row. `⌘F` focuses the I2 search field. Follow macOS conventions; declare them in the menu bar (Commands) so they're discoverable and testable.
3. Keep every action mouse-reachable — shortcuts are additive.

**Tests.** Focus-advance and verdict-application logic live in the model (testable): unit-test next/previous row selection, chip selection wrap, and that a shortcut mutates exactly the focused chip. Manual: full keyboard-only triage of a small session.

**Acceptance.** A session can be fully triaged without touching the mouse; shortcuts are visible in the menu bar; no regression for mouse users.

### I4. A consistent inline error component

- **Priority:** MEDIUM · **Effort:** Small-Medium · **Risk:** Low

**Problem.** Errors render as bare red `Text` one-liners with no dismiss, retry, or copy affordance, and independent channels get collapsed: `Step5ReviewView` ~:28 shows `review.buildError ?? review.fileError ?? review.editError` — a build error *hides* later file/edit errors. `NormalizationInspectorView` ~:19-24 and `SettingsModel.loadError` are similar. The good pattern already exists once: the Step-3 preflight badge with inline **Retry** (`Step3OptionsView` ~:336-342).

**Change.**
1. New `DesignSystem/InlineErrorView.swift`: message (selectable text), optional Retry action, Dismiss, and a copy-to-clipboard affordance for the full message; error styling from tokens.
2. Replace the bare `Text` surfaces with it; **stop collapsing channels** — render each active error independently (stacked, most recent first) instead of `??`-chaining.
3. Model-side: give each error channel explicit clear semantics (dismiss clears that channel only).

**Tests.** Unit-test the channel independence in the models (set build + file errors; assert both surface; dismiss one; assert the other remains). Snapshot/manual pass over Review, Inspector, Settings error states.

**Acceptance.** No `??`-chained error display remains (grep); every inline error is dismissable and copyable; retry appears where a retryable operation exists.

### I5. Estimated time remaining on the working screen

- **Priority:** LOW-MEDIUM · **Effort:** Small · **Risk:** Low

**Problem.** `Features/Run/Step4WorkingView.swift` `statsRow` ~:116-129 shows Elapsed, Rate (s/img), Model — and already has `done`/`total` and `secondsPerImage`; ETA is trivially derivable and absent.

**Change.** Add an ETA stat (`(total - done) × secondsPerImage`, smoothed the same way the existing rate is; display `—` until the rate stabilizes over ≥3 completed items and while paused/interrupted). Respect the R1-14 rate semantics under skips (skipped items must not deflate the estimate).

**Tests.** Unit-test the ETA function: warm-up gating, skip handling, monotonic countdown on steady rate, `—` cases.

**Acceptance.** ETA appears alongside the existing stats after warm-up and behaves sanely under skips and interruption; no layout shift when it flips from `—`.

### I6. Folder drop-zone feedback

- **Priority:** LOW · **Effort:** Small · **Risk:** Low

**Problem.** `Features/Import/Step1PhotosView.swift` `dropZone.dropDestination` ~:151-157 takes `urls.first`, requires a directory, and returns `false` otherwise — dropping files or multiple items silently does nothing.

**Change.** On a rejected drop, show a brief inline hint ("Drop a single folder — files and multiple items aren't supported here") using the I4 component in its transient (auto-dismiss) form; highlight the drop target's invalid state during hover-over with a non-accepting payload where the API allows. Multi-root import itself stays roadmap F2 — this is feedback only.

**Tests.** The accept/reject decision moves to a pure helper (`dropDecision(urls:) -> accepted | rejectedReason`) with unit tests; manual drag/drop pass.

**Acceptance.** A bad drop produces visible, accurate feedback; a valid folder drop is unchanged.

---

## Non-goals

- No Studio shell, database, multi-root, similarity, vocabulary-manager, or any F1–F13 roadmap scope.
- No new persistence (invariant 20) — filters, focus, and dismissed-error state are session-transient.
- No Core behavior changes; any data the GUI newly needs arrives via a Core seam added under plan 16's rules.

## Stage ledger

| Item | State | Date | Notes |
|---|---|---|---|
| I1–I7 | pending | | I7 is first; plan 16 Tranches A–C are complete |
