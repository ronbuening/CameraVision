# Quality in the GUI (CupricAspect) — Staged Implementation Plan

Version: 1.1
Date: 2026-07-17
Status: ready for execution (doc-14 dependencies are implemented; see per-stage Depends-on)
Authorities: `agent_docs/12-image-quality-assessment-plan.md` (this is the deferred IQ-M6 pass), `agent_docs/14-quality-normalization-integration-plan.md` (Core seams this plan binds to; its QN7 notes are required reading), `agent_docs/13-image-quality-implementation-stages.md` §0 (work rules), `agent_docs/invariants.md` (especially invariant 13: the GUI is presentation and state orchestration only — no processing leaves Core), `agent_docs/10-hardening-implementation-plan.md` (the R-wave conventions for GUI stages: file-collision ordering, offline `CupricAspectAppTests`, Settings write-through pattern).
Audience: implementing agents (junior engineer / Sonnet-level) and reviewing agents. Each stage is executable unaided after reading §0–§2, the stage itself, and the files it lists.

---

## 0. How to work a stage

Doc 13 §0's eight rules apply verbatim. GUI-specific additions:

9. **Invariant 13 is absolute.** Every stage here changes `Sources/CupricAspectApp` (plus tests) only — configuration assembly, state, and display. If a stage seems to need Core changes, that is a doc-14 gap: stop and ledger-note it; do not add Core code from this plan.
10. **Tests live in `Tests/CupricAspectAppTests`**, offline and deterministic (no Ollama, no network, temp dirs with teardown), following the existing model-test style (`AnalysisRunTests`, `ExportModelTests`, `NormalizationModelTests`, `ReviewModelTests`).
11. **Off means identical.** With absent/default-off quality configuration and the Step-2 quality toggle off, every run the app performs must produce the same resolved Core configurations and byte-identical artifacts as today. Each UI stage lists an identity test. Explicit environment/config quality defaults remain visible and effective through the standard resolver precedence.
12. **File-collision ordering** (plan-10 convention): stages that edit the same view file are ordered below; execute in ledger order so each view file stays a single line of edits.

## 1. Stage ledger

| Stage | Title | Depends on | Size | Status | Notes |
|---|---|---|---|---|---|
| G1 | Quality run-state + resolver plumbing (no UI) | — | M | done | Implemented 2026-07-17. Quality state is seeded once in `AnalysisOptions`, mapped through the existing optional Core overrides, and normalization/review/apply builders now use the standard resolvers. The apply override freezes after a successful plan and is reused for confirmation. Focused 49-test gate and full `swift test` passed (754 tests, 2 skipped); `Scripts/format.sh` and `git diff --check` passed. |
| G2 | Step 2 "Assess image quality" toggle | G1 | M | done | Implemented 2026-07-17. Step 2 now presents an always-enabled assess-quality toggle beneath the action cards, with the `EXPERIMENTAL` chip and action-specific copy. The binding updates `AnalysisOptions.assessQuality` without altering the action selection. Focused 20-test gate and full `swift test` passed (757 tests, 2 skipped); `Scripts/format.sh` and `git diff --check` passed. |
| G3 | Step 3 Options grading group | G1; QN1+QN3+QN5 for the normalize action | M | done | Implemented 2026-07-17. Write and normalize now show the Step 3 quality-grading group; assessment-off disables the group while preserving choices, and effective mapping forces grading off without leaking retained rating/conflict values. Analyze remains unchanged. `WizardShellView.swift`, omitted from the stage file list, required a minimal routing update so the G1 overrides reach normalization, review, and export builders. Focused 53-test gate and full `swift test` passed (761 tests, 2 skipped); `Scripts/format.sh` and `git diff --check` passed. |
| G4 | Settings defaults for quality | G3 | S | done | Implemented 2026-07-17. Settings now shows an experimental quality-grading defaults subsection seeded from the effective apply-session resolver. Minimum confidence and all five metadata channels write only their existing `xmp_quality_*` keys through `ConfigFileEditor`; tier maps remain config-only. Tests cover every key, resolver round-trip, environment precedence, and untouched/no-key-spam identity. Focused 14-test gate and full `swift test` passed (764 tests, 2 skipped); `Scripts/format.sh` and `git diff --check` passed. |
| G5 | Apply-session grading toggle | G1; QN6 | S | done | Implemented 2026-07-17. Apply now owns transient grading-enabled and scalar-conflict state seeded from the effective apply-session resolver, exposes the same conflict labels as G3, and states that grades come from current sidecars rather than the saved session. The apply-only override is passed into `ExportModel.plan(...)` and frozen for confirmation. Tests cover state mapping, effective-default seeding, default-off identity, and a current-sidecar boundary case where an assessment added after session creation produces the apply-time tier. Focused 14-test gate and full `swift test` passed (768 tests, 2 skipped); `Scripts/format.sh` and `git diff --check` passed. |
| G6 | Review-step quality surfacing | G3 | M | pending | |
| G7 | Documentation pass | G1–G6 | S | pending | |

## 2. Design overview

### UX decision — a cross-cutting toggle, not a fifth card

Step 2 ("What should CupricAspect do?") stays a three-card action choice (`WizardAction`: analyze / write / normalize, plus the apply-session link). Quality is orthogonal — it composes with **every** card — so it becomes a single toggle row rendered beneath the cards in `Step2ActionView`:

> **[ ] Assess image quality** `EXPERIMENTAL`
> Ask the model to judge focus, exposure, composition, and more. The verdicts are saved in the sidecars for later; on XMP paths, enable Quality grading in Options to also write culling metadata — quality keywords, color labels, and Lightroom pick/reject flags.

Rationale: a fifth card would force quality to be an alternative to tagging, which contradicts the Core design (assessment rides the same model pass; grading rides the same export). The subtitle adapts to the selected card (exact copy per action is specified in G2). The `EXPERIMENTAL` chip reuses the capsule treatment `Step2ActionView.actionCard` already draws for milestone badges.

### Where each concern lives

| Concern | Surface | Binds to (Core seam) |
|---|---|---|
| Assess on/off (per run) | Step 2 toggle | `RunConfigurationOverrides.qualityAssessment` (exists; `AnalysisRunModel` builds these) |
| Grade on/off + per-run choices (rating opt-in, conflict policy) | Step 3 Options "Quality grading" group | `QualityGradingConfigurationOverrides` on normalization previews and `ApplySessionConfigurationOverrides` for the authoritative Wizard write |
| Channel/tier-map defaults | Settings sheet CONFIGURATION section | existing `xmp_quality_*` keys written through `config.json` (R1-11/12 write-through pattern) |
| Apply-time grading | Apply-session flow | QN6's apply-session grading configuration |
| Results display | Step 5 Review + ChangePlanSheet (rows) | Core assessment extraction plus plan `*_write` rows, `quality_tier`, `quality_explanation`, and export-report write results — read-only |

### Decisions (record deviations per §0 rule 6)

- **D-G1 — Ship visible, labeled experimental.** The toggle is live (the Core feature ships in `0.2.0-beta.1`), marked with an `EXPERIMENTAL` chip; no `FeatureFlags` env gate. If the maintainer prefers gating, `FeatureFlags`'s `CUPRIC_*` pattern is the fallback — ask before improvising.
- **D-G2 — Step 3 stays small.** Per-run grading choices are exactly: grading on/off, "Write star ratings" (the opt-in channel), and the conflict policy picker (`preserve`/`refresh`/`overwrite`). Everything else (channel toggles, tier maps, min-confidence) is a Settings default. This mirrors the R1-11/12 split between per-run Options and Settings defaults.
- **D-G3 — Grading requires assessing in analyze flows.** For write/normalize runs that first analyze, the grading group is enabled only while `qualityAssessment` is on, and effective override mapping combines both gates so retained UI state can never create a contradictory run. Grading without a model assessment is meaningful only for from-JSON/apply-session flows; the Wizard exposes that separately in G5.
- **D-G4 — Reuse existing per-run state.** Quality fields live on `AnalysisOptions` with the other Wizard run options. They survive step navigation and the non-destructive Review → Options transition within the current Wizard instance. A fresh import or relaunch reloads resolved defaults from config/environment (off unless those sources say otherwise). Persistent quality defaults are handled only by G4 through shared `config.json`; no UserDefaults key, recovery-file extension, or parallel state store is added. Review recovery continues to persist the normalization session and review decisions only.

---

## 3. Stages

### G1 — Quality run-state + resolver plumbing (no UI)

**Goal.** `AnalysisOptions` carries `assessQuality: Bool` and a grading sub-state (enabled, writeRating, conflictPolicy), seeded once from the resolved configuration and retained for the current Wizard run. The state reaches every Core resolver used by analysis, normalization preview/review, and the authoritative apply-session export — with every UI entry point still absent.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/AnalysisRunModel.swift` (`AnalysisOptions` and its `RunConfigurationOverrides(...)` construction), `Features/Normalize/NormalizationModel.swift`, `Features/Review/ReviewModel.swift`, and `Features/Export/ExportModel.swift`.
- Read first: doc 14 QN7's binding-point notes (they name these seams with file/symbol citations — if QN7 hasn't landed, do that verification reading yourself and record it).

**Do.**
1. Add the fields to `AnalysisOptions`; seed their visible values once from `ConfigurationResolver.resolve(...)`, `resolveNormalization(...)`, and/or `resolveApplySession(...)` as appropriate, following the existing `defaultsLoaded` lifecycle. Built-in defaults are off, rating is opt-in, and scalar conflicts preserve existing values.
2. Map assessment into `RunConfigurationOverrides.qualityAssessment`. The control value is a CLI-equivalent per-run override, so a user can turn an effective config/environment default on or off truthfully.
3. Build one `QualityGradingConfigurationOverrides` from the per-run sub-state. Set only the GUI-owned fields (`enabled`, `writeRating`, `conflictPolicy`); leave channel maps, the other channel switches, and minimum confidence to Settings/config resolution.
4. Route `NormalizationModel.buildConfiguration(...)` and `ReviewModel.buildSession(...)` through `ConfigurationResolver.resolveNormalization(cli:)` instead of mutating `.builtInDefaults`. The normalize flow and the write flow's review-base session both receive grading previews when grading is enabled, while preserving config/environment defaults.
5. Route `ExportModel.applyConfiguration(...)` through `ConfigurationResolver.resolveApplySession(cli:)`. The Wizard has no direct `XMPExportConfigurationOverrides` call: write, normalize, and imported-session exports all commit through `ApplySessionPipeline`. Freeze the grading override when `plan(...)` succeeds and reuse that identical override in `confirmWrite()` so the reviewed dry run and committed write cannot disagree.
6. Do not add UserDefaults or another recovery file. A fresh import uses `resetToResolvedDefaults()`; ordinary step navigation retains the live `AnalysisOptions` instance.

**Tests** (`AnalysisRunTests`, `ExportModelTests`, `NormalizationModelTests`, `ReviewModelTests`): resolved defaults seed the state; each GUI-owned field maps exactly; normalize/review builders preserve resolver precedence; apply planning and confirmation receive identical grading overrides; step-navigation retention uses the same options instance; and absent/default-off quality configuration produces resolved configurations and artifacts equal to today's. No persistence round-trip test exists because per-run options are intentionally not durable.

**Commit.** `Carry quality assess/grade state through the wizard models (G1)`

### G2 — Step 2 "Assess image quality" toggle

**Goal.** The What-to-do page offers the toggle, with copy that adapts to the selected action.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/WizardAction.swift` (`Step2ActionView` gains the toggle row bound to G1's state; the view's binding surface grows by one), `Shells/WizardShellView.swift` only if the binding must pass through it (read first; keep the diff minimal).
- Read first: `WizardAction.swift` end to end (card layout, the milestone-chip capsule to reuse for `EXPERIMENTAL`), the Wizard design doc cited in `WizardAction.swift`'s header comment (§6 Step 2) for layout language.

**Do.**
1. Render the toggle beneath the three cards, above the apply-session link, using the theme's existing panel/border treatment. Chip text: `EXPERIMENTAL`.
2. Subtitle varies by selection: analyze → "Verdicts are saved in the .ai.json sidecars; nothing touches XMP."; write → "Verdicts are saved in the .ai.json sidecars. Enable Quality grading in Options to also write culling metadata."; normalize → "Verdicts are saved in the .ai.json sidecars. Enable Quality grading in Options to write culling metadata after normalization."; no selection → the generic copy in §2.
3. The toggle is always enabled (it composes with every card); it does **not** alter card availability.

**Tests.** View-model/logic level per the app test conventions (state flips propagate to G1 fields; subtitle selection logic is a pure function — extract it as one and test it directly). Identity: toggle off leaves `Step2ActionView`'s selection behavior untouched (existing tests stay green).

**Commit.** `Add the Step 2 assess-quality toggle (G2)`

### G3 — Step 3 Options grading group

**Goal.** Write/normalize runs expose the per-run grading choices from D-G2.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Run/Step3OptionsView.swift` (new "QUALITY" group: grading toggle, "Write star ratings" checkbox, conflict-policy picker; visible for write/normalize actions, enabled only when the G2 toggle is on), plus the G1 state fields it binds to.
- Read first: `Step3OptionsView.swift` end to end (R1-8/R1-9 established its control patterns and its relationship to `AnalysisOptions`/`ExportModel` — mirror them), D-G3.

**Do.** Hide the group for Analyze; show it for Write and Normalize. When assessment is off, keep the group visible but disabled and explain that this Wizard run must assess quality before it can grade. Effective override mapping must force grading off while the group is disabled, even if its retained UI sub-state was previously enabled. Bind the three controls to G1 state; conflict-policy picker labels spell out the semantics in one clause each ("Preserve — never replace existing values", "Refresh — replace only values this app wrote before", "Overwrite — always replace"). Rating checkbox carries the same rationale one-liner as the CLI docs ("stars stay yours unless you opt in").

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
- Modify: `Sources/CupricAspectApp/Features/Export/Step3ApplyView.swift`, `Features/Export/ExportModel.swift`, and `Shells/WizardShellView.swift` as needed to own and pass an apply-only grading state.
- Read first: QN6's landed surface; the apply flow end to end.

**Do.** Mirror G3's grading toggle and conflict-policy picker in the apply context, with copy that states the QN6 rule plainly: "Grades are derived from the sidecars as they are now, not from the saved session." Apply-session does not require or expose assessment because it performs no model run; it grades from the current contributor sidecars. Pass this apply-only state to `ExportModel.plan(...)`, which freezes it for the matching `confirmWrite()` per G1.

**Tests.** Apply-state→override mapping, current-sidecar semantics at the model boundary, and default-off identity. Do not add a persistence test; the apply flow has no durable UI-state container.

**Commit.** `Add apply-session quality grading toggle (G5)`

### G6 — Review-step quality surfacing

**Goal.** The user can see what grading will do (plan) and did (results) without leaving the app.

**Files.**
- Modify: `Sources/CupricAspectApp/Features/Export/ChangePlanSheet.swift` (scalar rows: planned rating/label/urgency/pick-good values with their actions, plus `quality_explanation` and ungraded reasons), `Features/Review/Step5ReviewView.swift` and `Features/Review/ReviewModel.swift` (read-only assessment detail, per-asset tier chip when a grade exists, and summary counts), and `Features/Export/ExportModel.swift` or `Features/Export/ExportReportView.swift` for completed-result summaries. `Features/Run/Step4WorkingView.swift` remains optional only if a real retained result count is already available; do not add progress plumbing merely for that line.
- Read first: doc 12 IQ-M6's read-only assessment requirement, `QualityAssessmentExtractor.swift`, `ChangePlanSheet.swift` (R1-10 built it — mirror its row idiom), `ReviewModel.swift` end to end, and `XMPExportReport.swift`.

**Do.** Display only; no parsing, tier derivation, conflict resolution, or keyword construction lives in the app.
1. Resolve the current raw-sidecar inputs through Core and call `QualityAssessmentExtractor` off the main actor. Show each stored role's overall/criterion levels, confidence, strengths, and concerns read-only, as required by doc 12 IQ-M6. Extraction issues surface as non-fatal diagnostics rather than being reinterpreted in the view.
2. Planned grading comes directly from `XMPChangePlan`: scalar `*_write` rows, `qualityTier`, and `qualityExplanation`. A skipped-by-policy scalar is `PlannedScalarWrite.action == .skipExisting`; tier chips use the tier raw value; explanations render verbatim.
3. Completed grading comes from `XMPExportReport.targetReports`, including each target's retained plan and `writeResult` existing/resulting scalar values. Do not depend on `XMPExportProgressRecord.wrote_*`: those records are artifact-only and the current GUI apply path does not retain them.
4. Treat `qualityTier == nil` plus an explanation beginning `ungraded reason=` as ungraded-with-reason. Runs with no quality fields render exactly as before.

**Tests.** Core extraction→display mapping over combined and quality-only sidecar fixtures; plan/report→display mapping including written, `skip_existing`, and ungraded-reason rows; a 1.1-era document without scalar rows renders unchanged; identity for runs without assessments or grading.

**Commit.** `Surface quality grading in plan sheet and review (G6)`

### G7 — Documentation pass

Update `README.md` (the CupricAspect section: the Step-2 toggle, the Options group, Settings defaults — keeping the experimental framing consistent with the CLI section), `agent_docs/cli-implementation-notes.md` (GUI binding notes updated from "planned" to "wired"), `architecture-map.md` (app feature row). Docs-only commit: `Document quality in the CupricAspect wizard (G7 docs)`.

---

## 4. Acceptance criteria (plan-level)

- **AC-G1** With absent/default-off quality configuration and the Step-2 toggle off, every wizard path produces the same resolved Core configurations and byte-identical artifacts as the pre-plan app (pinned by identity tests in G1–G3). Explicit environment/config quality defaults remain effective and are represented truthfully in the controls.
- **AC-G2** One Step-2 toggle + one Step-3 group is the entire analyze-path per-run surface; a user can run analyze-with-assessment, write-with-grading, and normalize-with-grading without touching a config file. Apply-session's model-free grading control is the separate G5 surface.
- **AC-G3** Settings defaults round-trip through `config.json` using only existing `xmp_quality_*` keys, and the CLI honors what the app writes (shared config, by construction).
- **AC-G4** All quality values shown in the app come from Core extraction, plan, or export-report values — `grep` finds no assessment parsing, tier derivation, conflict resolution, or keyword construction in `Sources/CupricAspectApp`.
- **AC-G5** Quality selections survive Step 2/3 navigation and the non-destructive Review → Options transition. A fresh import or relaunch reloads effective config/environment defaults; persistent channel and confidence defaults survive through shared `config.json`.
- **AC-G6** The experimental status is visible on every surface that enables the feature (Step 2 chip; Settings subsection note).
