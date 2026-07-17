# Quality in the GUI (CupricAspect) — Staged Implementation Plan

Version: 1.0
Date: 2026-07-17
Status: ready for execution once its doc-14 dependencies land (see per-stage Depends-on)
Authorities: `agent_docs/12-image-quality-assessment-plan.md` (this is the deferred IQ-M6 pass), `agent_docs/14-quality-normalization-integration-plan.md` (Core seams this plan binds to; its QN7 notes are required reading), `agent_docs/13-image-quality-implementation-stages.md` §0 (work rules), `agent_docs/invariants.md` (especially invariant 13: the GUI is presentation and state orchestration only — no processing leaves Core), `agent_docs/10-hardening-implementation-plan.md` (the R-wave conventions for GUI stages: file-collision ordering, offline `CupricAspectAppTests`, Settings write-through pattern).
Audience: implementing agents (junior engineer / Sonnet-level) and reviewing agents. Each stage is executable unaided after reading §0–§2, the stage itself, and the files it lists.

---

## 0. How to work a stage

Doc 13 §0's eight rules apply verbatim. GUI-specific additions:

9. **Invariant 13 is absolute.** Every stage here changes `Sources/CupricAspectApp` (plus tests) only — configuration assembly, state, and display. If a stage seems to need Core changes, that is a doc-14 gap: stop and ledger-note it; do not add Core code from this plan.
10. **Tests live in `Tests/CupricAspectAppTests`**, offline and deterministic (no Ollama, no network, temp dirs with teardown), following the existing model-test style (`AnalysisRunTests`, `ExportModelTests`, `NormalizationModelTests`, `ReviewModelTests`).
11. **Off means identical.** With the Step-2 quality toggle off (the default), every run the app performs must be byte-identical to today — same overrides, same artifacts. Each UI stage lists an identity test.
12. **File-collision ordering** (plan-10 convention): stages that edit the same view file are ordered below; execute in ledger order so each view file stays a single line of edits.

## 1. Stage ledger

| Stage | Title | Depends on | Size | Status | Notes |
|---|---|---|---|---|---|
| G1 | Quality run-state + persistence (no UI) | — | M | pending | |
| G2 | Step 2 "Assess image quality" toggle | G1 | M | pending | |
| G3 | Step 3 Options grading group | G1; QN1+QN3+QN5 for the normalize action | M | pending | |
| G4 | Settings defaults for quality | G3 | S | pending | |
| G5 | Apply-session grading toggle | QN6 | S | pending | |
| G6 | Review-step quality surfacing | G3 | M | pending | |
| G7 | Documentation pass | G1–G6 | S | pending | |

## 2. Design overview

### UX decision — a cross-cutting toggle, not a fifth card

Step 2 ("What should CupricAspect do?") stays a three-card action choice (`WizardAction`: analyze / write / normalize, plus the apply-session link). Quality is orthogonal — it composes with **every** card — so it becomes a single toggle row rendered beneath the cards in `Step2ActionView`:

> **[ ] Assess image quality** `EXPERIMENTAL`
> Ask the model to judge focus, exposure, composition, and more. With *Analyze only*, the verdicts are saved in the sidecars for later; with the XMP paths, they also become culling metadata — quality keywords, color labels, and Lightroom pick/reject flags.

Rationale: a fifth card would force quality to be an alternative to tagging, which contradicts the Core design (assessment rides the same model pass; grading rides the same export). The subtitle adapts to the selected card (exact copy per action is specified in G2). The `EXPERIMENTAL` chip reuses the capsule treatment `Step2ActionView.actionCard` already draws for milestone badges.

### Where each concern lives

| Concern | Surface | Binds to (Core seam) |
|---|---|---|
| Assess on/off (per run) | Step 2 toggle | `RunConfigurationOverrides.qualityAssessment` (exists; `AnalysisRunModel` builds these) |
| Grade on/off + per-run choices (rating opt-in, conflict policy) | Step 3 Options "Quality grading" group | `QualityGradingConfigurationOverrides` on the export/normalization overrides (write path exists today; normalize path arrives with QN1/QN3) |
| Channel/tier-map defaults | Settings sheet CONFIGURATION section | existing `xmp_quality_*` keys written through `config.json` (R1-11/12 write-through pattern) |
| Apply-time grading | Apply-session flow | QN6's apply-session grading configuration |
| Results display | Step 4 Working (counts), Step 5 Review + ChangePlanSheet (rows) | plan `*_write` rows, `quality_tier`, `quality_explanation`, progress `wrote_*` fields — read-only |

### Decisions (record deviations per §0 rule 6)

- **D-G1 — Ship visible, labeled experimental.** The toggle is live (the Core feature ships in `0.2.0-beta.1`), marked with an `EXPERIMENTAL` chip; no `FeatureFlags` env gate. If the maintainer prefers gating, `FeatureFlags`'s `CUPRIC_*` pattern is the fallback — ask before improvising.
- **D-G2 — Step 3 stays small.** Per-run grading choices are exactly: grading on/off, "Write star ratings" (the opt-in channel), and the conflict policy picker (`preserve`/`refresh`/`overwrite`). Everything else (channel toggles, tier maps, min-confidence) is a Settings default. This mirrors the R1-11/12 split between per-run Options and Settings defaults.
- **D-G3 — Grading implies assessing where it can.** If the user enables grading for a write/normalize run that also analyzes, the app sets both `qualityAssessment` and the grading block — one Step-2 toggle plus one Step-3 group, never a contradictory state. Grading with the Step-2 toggle off is still meaningful for from-JSON-style runs only, which the wizard does not expose; the Options group is therefore disabled (with explanatory text) unless the Step-2 toggle is on.
- **D-G4 — No new state stores.** Quality fields join the existing persisted wizard/run state so kill-relaunch-restore (a tested app flow) carries them like every other option. Discover the actual persistence container in G1 by reading `AnalysisRunModel.loadResolvedDefaults()` / `StateHousekeeping` — do not invent a parallel store.

---

## 3. Stages

### G1 — Quality run-state + persistence (no UI)

**Goal.** The app's run state carries `assessQuality: Bool` and a grading sub-state (enabled, writeRating, conflictPolicy), persisted and restored, and threads them into the overrides the models build — with every UI entry point still absent, so nothing observable changes.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift` (the `RunConfigurationOverrides(...)` construction — currently around line 77 — gains `qualityAssessment: state.assessQuality ? true : nil`), the options/state type it persists (read `loadResolvedDefaults()` and `Support/StateHousekeeping.swift` first to find it), and the export/normalization configuration assembly sites the wizard uses (locate by reading `Features/Export/ExportModel.swift` and `Features/Normalize/NormalizationModel.swift` end to end — they do not call `ConfigurationResolver` directly, so find where their resolved configurations are produced and thread the grading overrides there; cite the discovered path in the ledger note).
- Read first: doc 14 QN7's binding-point notes (they name these seams with file/symbol citations — if QN7 hasn't landed, do that verification reading yourself and record it).

**Do.** Add the fields with defaults off; wire persistence; map into overrides using the `flag ? true : nil` idiom so an off toggle never stomps config/env values (S1.2's rule). For the write action, grading maps into `XMPExportConfigurationOverrides.qualityGrading` (exists today). For the normalize action, the same sub-state maps into the QN1 normalization overrides — if QN1 has not landed, wire the write action only and ledger-note the gap.

**Tests** (`AnalysisRunTests`, `ExportModelTests`, `NormalizationModelTests`): overrides carry the fields when set and omit them when off; state round-trips through the persistence path; identity test — default state produces overrides equal to today's.

**Commit.** `Carry quality assess/grade state through the wizard models (G1)`

### G2 — Step 2 "Assess image quality" toggle

**Goal.** The What-to-do page offers the toggle, with copy that adapts to the selected action.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/WizardAction.swift` (`Step2ActionView` gains the toggle row bound to G1's state; the view's binding surface grows by one), `Shells/WizardShellView.swift` only if the binding must pass through it (read first; keep the diff minimal).
- Read first: `WizardAction.swift` end to end (card layout, the milestone-chip capsule to reuse for `EXPERIMENTAL`), the Wizard design doc cited in `WizardAction.swift`'s header comment (§6 Step 2) for layout language.

**Do.**
1. Render the toggle beneath the three cards, above the apply-session link, using the theme's existing panel/border treatment. Chip text: `EXPERIMENTAL`.
2. Subtitle varies by selection: analyze → "Verdicts are saved in the .ai.json sidecars; nothing touches XMP."; write → "Also writes culling metadata: quality keywords, color labels, and Lightroom pick/reject flags."; normalize → same as write with "after normalization" appended; no selection → the generic copy in §2.
3. The toggle is always enabled (it composes with every card); it does **not** alter card availability.

**Tests.** View-model/logic level per the app test conventions (state flips propagate to G1 fields; subtitle selection logic is a pure function — extract it as one and test it directly). Identity: toggle off leaves `Step2ActionView`'s selection behavior untouched (existing tests stay green).

**Commit.** `Add the Step 2 assess-quality toggle (G2)`

### G3 — Step 3 Options grading group

**Goal.** Write/normalize runs expose the per-run grading choices from D-G2.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift` (new "QUALITY" group: grading toggle, "Write star ratings" checkbox, conflict-policy picker; visible only when the G2 toggle is on **and** the action writes XMP; disabled state with one-line explanation otherwise), plus the G1 state fields it binds to.
- Read first: `Step3OptionsView.swift` end to end (R1-8/R1-9 established its control patterns and its relationship to `AnalysisOptions`/`ExportModel` — mirror them), D-G3.

**Do.** Bind the three controls to G1 state; conflict-policy picker labels spell out the semantics in one clause each ("Preserve — never replace existing values", "Refresh — replace only values this app wrote before", "Overwrite — always replace"). Rating checkbox carries the same rationale one-liner as the CLI docs ("stars stay yours unless you opt in").

**Tests.** Options→overrides mapping (each control changes exactly its field); visibility matrix (action × toggle); identity with the group untouched.

**Commit.** `Add the Step 3 quality-grading options group (G3)`

### G4 — Settings defaults for quality

**Goal.** Settings' CONFIGURATION section can set the persistent defaults (channels, min-confidence) by writing through to `config.json`, like every other Settings default.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Settings/SettingsSheet.swift`, `Features/Settings/SettingsModel.swift` (write-through of `xmp_quality_write_label`, `xmp_quality_write_urgency`, `xmp_quality_write_flag`, `xmp_quality_write_keywords`, `xmp_quality_write_rating`, `xmp_quality_min_confidence` — tier maps stay config-file-only and out of the GUI, matching the CLI).
- Read first: how R1-11/R1-12 added their Settings controls and write-throughs; `SettingsModel`'s config read/write path.

**Do.** One "Quality grading defaults" subsection; controls seed from the resolved configuration on open (so env/config precedence is visible truthfully); writes go through the existing `SettingsModel` path — never a second config writer.

**Tests.** Round-trip: set → written key present in the temp config → resolved configuration reflects it; unset keys absent (no key spam); identity when untouched.

**Commit.** `Add quality-grading defaults to Settings (G4)`

### G5 — Apply-session grading toggle

**Goal.** The apply-session flow can enable grading at apply time (QN6 semantics: re-derived from current sidecars, never from the frozen session).

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Export/Step3ApplyView.swift` and the model that drives apply (read `ReviewModel.swift` / `ExportModel.swift` to find it), binding one toggle + the conflict-policy picker to QN6's apply-session grading overrides.
- Read first: QN6's landed surface; the apply flow end to end.

**Do.** Mirror G3's group in the apply context, with copy that states the QN6 rule plainly: "Grades are derived from the sidecars as they are now, not from the saved session."

**Tests.** Overrides mapping + identity; a state test that the toggle survives the apply flow's own persistence if it has one.

**Commit.** `Add apply-session quality grading toggle (G5)`

### G6 — Review-step quality surfacing

**Goal.** The user can see what grading will do (plan) and did (results) without leaving the app.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Export/ChangePlanSheet.swift` (scalar rows: planned rating/label/urgency/pick-good values with their actions, plus `quality_explanation` and ungraded reasons — read-only rendering of fields the plan document already carries), `Features/Review/Step5ReviewView.swift` and `Features/Review/ReviewModel.swift` (per-asset tier chip when a grade exists; summary counts — graded / ungraded-with-reason / skipped-by-policy — from the report/progress fields `wrote_*`), `Features/Run/Step4WorkingView.swift` only if a one-line graded-count is cheap there (optional; skip if it grows the diff).
- Read first: `ChangePlanSheet.swift` (R1-10 built it — mirror its row idiom), `ReviewModel.swift` end to end.

**Do.** Display only — every value comes from plan/report/progress documents; no derivation in the app. Tier chips use tier raw values as labels; explanations render verbatim.

**Tests.** Decoding→display mapping over fixture plan/report JSON (including a 1.1-era document without scalar rows — the sheet must render it unchanged); identity for ungraded runs.

**Commit.** `Surface quality grading in plan sheet and review (G6)`

### G7 — Documentation pass

Update `README.md` (the CupricAspect section: the Step-2 toggle, the Options group, Settings defaults — keeping the experimental framing consistent with the CLI section), `agent_docs/cli-implementation-notes.md` (GUI binding notes updated from "planned" to "wired"), `architecture-map.md` (app feature row). Docs-only commit: `Document quality in the CupricAspect wizard (G7 docs)`.

---

## 4. Acceptance criteria (plan-level)

- **AC-G1** With the Step-2 toggle off, every wizard path produces byte-identical Core invocations and artifacts to the pre-plan app (pinned by identity tests in G1–G3).
- **AC-G2** One Step-2 toggle + one Step-3 group is the entire per-run surface; a user can run analyze-with-assessment, write-with-grading, and (once doc 14 lands) normalize-with-grading without touching a config file.
- **AC-G3** Settings defaults round-trip through `config.json` using only existing `xmp_quality_*` keys, and the CLI honors what the app writes (shared config, by construction).
- **AC-G4** All quality values shown in the app are read from plan/report/progress documents — `grep` finds no tier derivation, conflict resolution, or keyword construction in `Sources/CupricAspectApp`.
- **AC-G5** Kill-relaunch-restore preserves the quality toggles like every other wizard option.
- **AC-G6** The experimental status is visible on every surface that enables the feature (Step 2 chip; Settings subsection note).
