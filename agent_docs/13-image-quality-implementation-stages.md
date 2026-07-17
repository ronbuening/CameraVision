# Image Quality Assessment — Staged Implementation Plan

Version: 1.0
Date: 2026-07-15
Status: ready for execution (no code started)
Companion to: `agent_docs/12-image-quality-assessment-plan.md` (the requirements/design authority — **doc 12 wins on any scope or design conflict**; record the conflict in the ledger notes and stop rather than improvising)
Audience: implementing agents (junior engineer / Sonnet-level) and reviewing agents. Each stage is written to be executed **unaided** by an agent that has read only: this document's §0, the stage itself, the doc-12 sections the stage cites, and the source files the stage lists.

---

## 0. How to work a stage

Rules for every stage, no exceptions:

1. **One stage at a time, in ledger order.** A stage may only start when every stage it depends on is marked `done` in §1. Do not batch stages into one commit.
2. **Before writing code:** read `agent_docs/invariants.md` (all of it), the cited doc-12 sections, and every file the stage lists under *Files* — read them fully, not just the lines you expect to change. The codebase is the truth for exact line numbers; this document's line references are anchors, not gospel.
3. **Never modify shipped version files.** Prompt/schema files `*_v1.1.0`–`*_v1.5.0` are immutable (invariant 7/8). New behavior = new files. Never rename or reuse an existing raw string, error code, schema identifier, or artifact-name pattern; only add.
4. **Tests are deterministic and offline** (invariant 12): no Ollama, no network, no real images. Use `MockVisionModelRunner`, `RecordedFixtureRunner`, temp directories with teardown, and the fixture layout in `Tests/AISidecarCoreTests/Fixtures/`.
5. **Every stage ends green:** `swift test` passes (prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if XCTest is missing), then `Scripts/format.sh`, then one commit using the stage's commit message. Code and documentation changes go in **separate commits** when a stage contains both.
6. **If reality disagrees with this plan** (an API changed, a file moved, a test already covers something differently): stop, write what you found in the ledger's Notes column, and surface it to the maintainer. Do not silently adapt the design.
7. **Scope discipline:** touch only the files the stage lists (plus their tests). If you believe another file must change, that's a finding for the ledger, not a license to expand the diff.
8. **Comments:** follow `agent_docs/commenting_guide.md` — comments state constraints the code can't show, never narration of the change.

**For reviewing agents:** each stage has a *Review checklist*. Verify every item against the diff, plus the global checks: no shipped version file modified, no new XMP write path outside the owned engine, no test requiring network/Ollama, raw strings additive only, `swift test` output included in the review evidence.

Naming note: stages are numbered `S<milestone>.<n>` and map 1:1 onto doc 12's milestones (S0.* = IQ-M0 … S5.* = IQ-M5). IQ-M6 (GUI) is deliberately not staged here; it gets its own pass when GUI work is scheduled.

---

## 1. Stage ledger

Update Status (`pending` / `in progress` / `done` / `blocked`) and Notes as stages complete. This table is the single source of truth for execution state.

| Stage | Title | Depends on | Size | Status | Notes |
|---|---|---|---|---|---|
| S0.1 | Response schemas v1.6.0 + quality-only v1.0.0 | — | M | done | `swift test` passed (594 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: positive-path test fixtures were not the Appendix A.4 objects — realigned post-audit; subject 1.6.0 schema `title` reads "Subject Isolated" (1.5.0 hyphen dropped) — accepted, `$id` correct. |
| S0.2 | Prompts v1.6.0 + quality-only v1.0.0 | S0.1 | S | done | `swift test` passed (595 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: B.4's neutral-matte paragraph was missing from `subject_isolated_quality_v1.0.0.txt` — restored pre-release (no pinned hash affected); v1.6.0 QUALITY ASSESSMENT sections reworded vs B.1/B.2 (bulleted QUALITY LEVELS heading, minor word swaps) — semantics preserved, accepted. |
| S0.3 | `ModelTaskProfile` + task-aware registries | S0.1, S0.2 | S | done | `swift test` passed (596 tests, 2 skipped) on 2026-07-15. |
| S0.4 | Wire-schema proofs + model-response fixtures | S0.3 | S | done | `swift test` passed (598 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: fixture quality objects were not the Appendix A.4 objects and the truncated fixture was not a prefix of the valid one — both realigned post-audit (quality golden regenerated to match). |
| S1.1 | `quality_assessment` config plumbing | S0.3 | M | done | `swift test` passed (600 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: also updated golden `phase1-both-normalized.json` (`task_profile` key, forced by the non-optional field) — outside the stage's file list, recorded here per §0 rule 7. |
| S1.2 | `--assess-quality` flag + pipeline selection | S1.1 | M | done | `swift test` passed (602 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: also added `--assess-quality` to write-xmp (`WriteXMPCommand.swift`, `XMPExportConfiguration.swift` incl. from-json rejection) — outside the stage's file list, recorded here per §0 rule 7; S4.7 must account for the existing flag. |
| S1.3 | Quality golden sidecar + repair coverage + docs | S1.2 | S | done | Code + documentation commits complete; `swift test` passed (604 tests, 2 skipped) on 2026-07-15. |
| S2.1 | Quality sidecar naming, artifact names, cleanup | S0.3 | S | done | `swift test` passed (605 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: this stage's "leaves tagging sidecars untouched" wording conflicts with established cleanup ownership (tagging sidecars have always been cleanup-owned); read as "removing a quality sidecar never touches the tagging file", which is covered. `.quality.ai.json` was already removable pre-stage via the `.ai.json` suffix match — real ownership growth is the two batch-artifact prefixes plus a reclassification. |
| S2.2 | `QualityAssessPipeline` + GPS suppression | S1.2, S2.1 | M | done | `swift test` passed (611 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: clean; minor untested corners in `--existing` coverage (overwrite over a pre-existing quality sidecar; skip isolation with only a tagging sidecar present) — low risk, path independence follows from `SidecarNaming.plan(kind:)`. |
| S2.3 | `assess-quality` subcommand + docs | S2.2 | S | done | Code + documentation commits complete; `swift test` passed (611 tests, 2 skipped), and both CLI help checks passed on 2026-07-15. Audit 2026-07-15: the shared `--assess-quality` flag appears in `assess-quality --help` and is silently discarded (pipeline forces quality-only) — misleading help text, consider hiding it on this command in a follow-up; the §5.7 skeleton's task-profile forcing lives in `QualityAssessPipeline` rather than the command — accepted, stronger invariant-13 posture. |
| S2.4 | Input-resolver quality-sibling support | S2.1 | S | done | `swift test` passed (615 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: direct-file resolution hard-fails on a corrupt/identity-mismatched quality sibling while folder scans degrade gracefully (recoverable failure, tagging input kept) — asymmetry uncommented and untested; an explicitly passed `.quality.ai.json` with a tagging sibling resolves the tagging file as primary — document when S4.8 consumes this. |
| S3.1 | `QualityAssessmentRecord` + extractor | S0.4 | M | done | `swift test` passed (624 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: phase 2-3 branch was rooted before 85c7634's fixture realignment, so the happy-path test asserted stale pre-A.4 values and went red after merge 2d0d115 — assertions realigned post-audit (suite green, 643 tests). `extract` is array-based (`[ResolvedRawSidecarInput] -> [QualityExtractionResult]` + single-input overload) instead of §5.4's variadic single-result — accepted; S2.4 folded the quality sibling into `ResolvedRawSidecarInput`, making the variadic pairing obsolete. |
| S3.2 | Tier deriver + grading types | S3.1 | M | done | `swift test` passed (633 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: rule table, defaults, veto, and channels verified row-by-row against §5.5 — clean. Doc 12 is internally inconsistent on the veto explanation string (§5.5.2 table vs §5.5.3 code block); implementation follows §5.5.3 — accepted. |
| S3.3 | Grading policy Codable + validation | S3.2 | S | done | `swift test` passed (643 tests, 2 skipped) on 2026-07-15. Audit 2026-07-15: unknown-tier-key rejection happens in `init(from:)` decoding rather than `validate()` (typed `[QualityTier:_]` maps can't hold unknown keys) — behaviorally equivalent, still `configInvalid`, accepted. |
| S4.0 | (manual prework) Capture C1 Urgency mapping | — | S | done | Capture One 16.8.4 samples supplied under `agent_docs/XMP_Samples/CaptureOne_ColorLabels/`; mapping recorded in `release-evidence/c1-urgency-mapping.md`. Red→1 and Green→2 feed S4.7 defaults. No `None` sample was supplied (not needed by the default tier map). Samples use child elements, contrary to doc 12 §5.6.1's parenthetical claim that C1 emits attributes; the binding read-both/update-in-place/create-as-attribute design is unchanged, and S4.9 must document the observed form. `swift test` passed (643 tests, 2 skipped) on 2026-07-16. |
| S4.1 | Managed-scalar types + reader | — | M | done | Namespace-aware reader covers attribute and child-element forms for rating, label, and urgency; equal boundary-whitespace-normalized duplicates are tolerated, while conflicting or structured scalar content fails closed. `swift test` passed (649 tests, 2 skipped) on 2026-07-16. |
| S4.2 | Scalar merge/write support | S4.1 | M | done | Existing attributes/elements and all tolerated equal duplicates update in place; absent scalars use attribute form with one namespace declaration on `rdf:RDF`. `swift test` passed (653 tests, 2 skipped) on 2026-07-16. |
| S4.3 | Fingerprint v2 + snapshot scalars | S4.2 | M | done | Fingerprint v2 excludes scalars only in the owned direct-`rdf:Description` shapes; nested and exact-name foreign-namespace lookalikes remain protected. Snapshots expose all three scalars and fail closed on conflicts. Throw propagation required minimal changes to `OwnedXMPSidecarEngine.swift` and the `XMPMergeValidatorTests` helper beyond the stage's incomplete file list. The plan's named fixture contains unmanaged `aux:rating`, not `xmp:Rating`, so it correctly remains fingerprinted. `swift test` passed (658 tests, 2 skipped) on 2026-07-16. |
| S4.4 | Merge-validator scalar checks | S4.3 | S | done | Planned writes require exact post-write scalar values; unplanned scalars require exact pre/post preservation for rating, label, and urgency. The additive defaulted validator inputs defer `PlannedScalarWrite` plumbing to S4.5/S4.6 without breaking existing callers. `swift test` passed (662 tests, 2 skipped) on 2026-07-16. |
| S4.5 | Change-plan/report type extensions + id bumps | S4.4 | M | done | Added optional scalar plan/request/preview/result/progress/report surfaces, legacy-plan decoding, mock action projection, and 1.1 schema ids. Urgency is intentionally symmetric despite doc 12 §5.6.3 naming only rating/label in one sentence; FR-IQ-040/042/044, AC-IQ-E7, and the Capture One evidence require it. Production `wrote_*` population was initially assigned to S4.8 at this type-only stage and completed early in S4.6 when validator plumbing made the pipeline expansion unavoidable. `swift test` passed (665 tests, 2 skipped) on 2026-07-16. |
| S4.6 | Engine apply path for scalars | S4.5 | M | done | The owned engine previews and applies rating→label→urgency after keyword merge, treats `skip_existing` as a true no-op, includes semantic scalar changes in the write decision, enforces slot/field agreement and Urgency-with-Label, and reports re-read values. Validator arguments and progress flags required minimal `XMPExportPipeline.swift` expansion; the existing restore injection therefore required `XMPExportPipelineTests.swift`, both omitted from the stage file list. Review found and this stage fixed a pre-existing thrown-post-write-validation gap so invalid new targets are removed as well as returned validation failures. `swift test` passed (674 tests, 2 skipped) on 2026-07-16. |
| S4.7 | Quality-grading configuration + write-xmp flags | S3.3, S4.5 | M | pending | |
| S4.8 | Planner hookup: grade → plan → write → stamp | S2.4, S4.6, S4.7 | L | pending | |
| S4.9 | Phase-4 documentation pass | S4.8 | S | pending | |
| S5.1 | (manual) Real-model bench + token evidence | S1.3 | S | pending | maintainer-run |
| S5.2 | (manual) LR/C1 release evidence + refresh run | S4.8, S4.0 | S | pending | maintainer-run |
| S5.3 | Evidence-driven doc + default updates | S5.1, S5.2 | S | pending | |

---

## 2. Phase 0 — model contract (doc 12 §5.1, §5.2, §3; issues #30/#31)

### S0.1 — Response schemas v1.6.0 + quality-only v1.0.0

**Goal.** The four new schema resource files exist, are loadable, and the local validator enforces the quality contract.

**Files.**
- Create: `Sources/AISidecarCore/Resources/ModelRuntime/Schemas/whole_image_v1.6.0.json`, `subject_isolated_v1.6.0.json`, `whole_image_quality_v1.0.0.json`, `subject_isolated_quality_v1.0.0.json`
- Modify: `Tests/AISidecarCoreTests/PromptSchemaTests.swift` (additions only)
- Read first: `Schemas/whole_image_v1.5.0.json`, `Schemas/subject_isolated_v1.5.0.json`, `ModelRuntime/JSONSchemaValidator.swift`, `Support/AISidecarResourceBundle.swift`

**Do.**
1. Copy `whole_image_v1.5.0.json` → `whole_image_v1.6.0.json`. Change `$id` to `urn:aisidecar:response:whole-image:1.6.0` and `title` to `AISidecar Whole Image Model Response 1.6.0`. Append `"quality_assessment"` to the top-level `required` array. Add the `quality_assessment` property from **Appendix A.1** to `properties`. Add the `quality_level` and `quality_note` definitions from **Appendix A.3** to `$defs`. Change nothing else.
2. Same for `subject_isolated_v1.6.0.json` from the 1.5.0 subject file, using **Appendix A.2** for the property (`$id` … `subject-isolated:1.6.0`).
3. Create the two quality-only schemas exactly as specified in doc 12 §5.1's template: root object, `additionalProperties:false`, single required property `quality_assessment` (Appendix A.1 for whole-image / A.2 for subject-isolated), and `$defs` containing `confidence` (copy verbatim from the 1.5.0 file), `quality_level`, `quality_note`. `$id`s: `urn:aisidecar:response:whole-image-quality:1.0.0`, `urn:aisidecar:response:subject-isolated-quality:1.0.0`.
4. Tests (direct-load via `AISidecarResourceBundle.current.url(forResource:withExtension:)` — the registries don't know these files until S0.3):
   - Each of the four files loads, decodes as `JSONValue`, and its `$id` equals the expected string.
   - Using `JSONSchemaValidator`, the fixture in **Appendix A.4** (wrapped appropriately: merged into a full 1.5.0-valid response for the 1.6.0 schemas; wrapped as `{"quality_assessment": …}` for the quality-only schemas) **passes** against all four schemas (use the subject variant fixture for subject schemas).
   - Rejection matrix (AC-IQ-A1), against the whole-image 1.6.0 schema at minimum: missing `quality_assessment` → invalid; missing one required criterion → invalid; unknown key inside `quality_assessment` → invalid; a level value `"excellent"` → invalid; three `concerns` entries → invalid; a 161-char note → invalid; a note containing `\n` → invalid (this proves the authoritative `pattern` still validates locally).
   - The 1.5.0 schemas still load with unchanged `$id`s (pin both strings).

**Do not.** Touch the 1.5.0 files, `OllamaWireSchema`, `PromptRegistry`, or `ResponseSchemas` — selection comes in S0.3.

**Review checklist.** Diff shows four new files + test additions only; `required` arrays contain every field doc 12 lists; `$defs.confidence` in quality-only files is byte-identical to 1.5.0's; the rejection matrix actually asserts invalid (not just "doesn't throw").

**Commit.** `Add v1.6.0 and quality-only v1.0.0 response schemas (IQ S0.1)`

### S0.2 — Prompts v1.6.0 + quality-only v1.0.0

**Goal.** The four new prompt files exist with correct headers; base-prompt regressions extended.

**Files.**
- Create: `Sources/AISidecarCore/Resources/ModelRuntime/Prompts/whole_image_v1.6.0.txt`, `subject_isolated_v1.6.0.txt`, `whole_image_quality_v1.0.0.txt`, `subject_isolated_quality_v1.0.0.txt`
- Modify: `Tests/AISidecarCoreTests/PromptSchemaTests.swift`
- Read first: both 1.5.0 prompt files, `ModelRuntime/PromptRegistry.swift` (header parsing rules)

**Do.**
1. `whole_image_v1.6.0.txt` = the 1.5.0 file with (a) line 1 changed to `PROMPT_VERSION: aisidecar.prompt.whole_image/1.6.0`, and (b) the `QUALITY ASSESSMENT` section from **Appendix B.1** inserted immediately **before** the final `Return only the JSON object.` line, separated by blank lines matching the file's section style. No other edits.
2. `subject_isolated_v1.6.0.txt` likewise with **Appendix B.2**.
3. The two quality-only prompts are complete files: **Appendix B.3** (whole) and **Appendix B.4** (subject), verbatim.
4. Tests: header parses for all four (version strings exact); trailing-newline/shape checks mirror the existing 1.5.0 assertions; extend the no-GPS/external-context regression (`testBasePromptsCarryNoGPSOrExternalContextLanguage` or its current name) to cover all four new files; add sha256-determinism assertions following the existing pattern; pin that the 1.5.0 prompt hashes are **unchanged** by this stage.

**Do not.** Add a second `PROMPT_VERSION` line anywhere in a file body (the addendum's own version header is deliberately dropped — doc 12 §3.2 A-2). Do not duplicate the closing "Return only the JSON object." line.

**Review checklist.** Exactly one header line per file; quality section field-name list matches the actual schema keys (doc 12 §3.2 A-3); the words GPS/EXIF/coordinate appear in the new prompts **only** inside the "Do not use GPS, EXIF…" prohibition sentence (the regression test must accept that framing exactly as it does for existing rules — read the existing test's mechanism first).

**Commit.** `Add v1.6.0 and quality-only v1.0.0 prompts (IQ S0.2)`

### S0.3 — `ModelTaskProfile` + task-aware registries

**Goal.** Code can select any of the three contracts per role; default behavior byte-identical to today.

**Files.**
- Modify: `Sources/AISidecarCore/ModelRuntime/ModelRuntimeTypes.swift`, `PromptRegistry.swift`, `ResponseSchemas.swift`; `Tests/AISidecarCoreTests/PromptSchemaTests.swift`
- Read first: all three source files end to end.

**Do.**
1. Add the `ModelTaskProfile` enum exactly as in doc 12 §5.2.1 (raw values `tagging` / `tagging_with_quality` / `quality_only`; `Codable`, `Sendable`, `CaseIterable`).
2. Change `PromptRegistry.prompt(for:context:)` → `prompt(for:task:context:)` with `task: ModelTaskProfile = .tagging` so existing call sites compile unchanged; same for `ResponseSchemas.schema(for:)` → `schema(for:task:)`. Implement `resourceName(for:task:)` with the six-arm switch from doc 12 §5.2.2.
3. Tests: all six (role, task) pairs load, with exact prompt-version and `$id` assertions; `(anyRole, .tagging)` returns the 1.5.0 versions (this is FR-IQ-004's pin).

**Review checklist.** Default parameter present (no call-site churn in this diff); switch is exhaustive with no `default:` arm (so a future role/profile addition forces a compile error here); enum raw strings match doc 12 exactly.

**Commit.** `Add ModelTaskProfile and task-aware prompt/schema selection (IQ S0.3)`

### S0.4 — Wire-schema proofs + model-response fixtures

**Goal.** Grammar-safety of the new schemas is proven at unit level; reusable response fixtures exist.

**Files.**
- Create: `Tests/AISidecarCoreTests/Fixtures/model-responses/whole_image_with_quality_valid.json` (a full 1.6.0-valid response: take the existing whole-image valid fixture's content and add the Appendix A.4 object), `whole_image_quality_only_valid.json` (`{"quality_assessment": …}`), `subject_isolated_with_quality_valid.json`, `whole_image_quality_truncated.txt` (the quality-only valid JSON cut mid-string, for repair-path tests)
- Modify: `Tests/AISidecarCoreTests/ModelRuntimeTests.swift`
- Read first: `ModelRuntime/OllamaWireSchema.swift`, existing wire-schema test (`testWireSchemaInlinesRefsAndStripsUnsupportedKeywords`), existing fixtures in `model-responses/`

**Do.**
1. For each of the four new schemas: assert the derived wire schema contains no `$ref`, `$defs`, `pattern`, `description`, `$schema`, `$id`, `title` anywhere (recursive walk — reuse the existing test's helper); `quality_assessment` present in wire `required`; its `additionalProperties == false`; `strengths`/`concerns` retain `maxItems: 2` and item `minLength`/`maxLength` after inlining.
2. New fixtures validate against their schemas via `JSONSchemaValidator` (one test looping the pairs).
3. Do **not** attempt a live Ollama probe in tests — the live probe is S5.1's job.

**Review checklist.** Fixture JSON files are valid per their schema in-test (not just by eye); the truncated fixture is genuinely invalid JSON; no network use.

**Commit.** `Prove wire-schema safety of quality schemas; add response fixtures (IQ S0.4)`

---

## 3. Phase 1 — combined analyze integration (doc 12 §5.3; issue #36)

### S1.1 — `quality_assessment` config plumbing

**Goal.** The boolean rides the full precedence chain and resolves to a recorded `task_profile`.

**Files.**
- Modify: `Sources/AISidecarCore/Configuration/RunConfiguration.swift`, `AppConfig.swift`, `ConfigurationResolver.swift`; `aisidecar.config.example.jsonc`; `Tests/AISidecarCoreTests/ConfigResolutionTests.swift`, `ConfigValidationTests.swift` (if validation added), `JSONSidecarTests.swift` (decode-compat)
- Read first: how `recursive` flows through every one of those files (doc 12 §2.1 lists the chain; find each site by searching `recursive`).

**Do.** Mirror `recursive` at every site:
1. `RunConfigurationOverrides.qualityAssessment: Bool?` (+ init).
2. `ResolvedRunConfiguration.taskProfile: ModelTaskProfile` — coding key `task_profile`, built-in default `.tagging`, decoded with `decodeIfPresent … ?? builtInDefaults.taskProfile` (old sidecars/configs must keep decoding — add a test decoding a recorded `run_configuration` JSON **without** the key).
3. `AppConfig.qualityAssessment: Bool?` — property, `CodingKeys.qualityAssessment = "quality_assessment"`, init param, `decodeIfPresent`, `encodeIfPresent` (all five spots; the decoder rejects unknown keys, so missing a spot fails loudly — good).
4. `ConfigurationResolver`: env `AISIDECAR_QUALITY_ASSESSMENT` via the existing `boolValue` helper; builder field seeded `false`; `apply(config:)`/`apply(overrides:)`; `resolved()` sets `taskProfile = qualityAssessment ? .taggingWithQuality : .tagging`; update `withoutConfigPath()`.
5. Example config: `"quality_assessment": false,` with a one-line comment.
6. Tests: precedence matrix (AC-IQ-B3: file true + env false → off; env true → on; flag override tested in S1.2); resolved default is `.tagging`; provenance round-trip (encode resolved config, key `task_profile` present).

**Review checklist.** All five `AppConfig` spots present; the CLI override uses the `flag ? true : nil` idiom (S1.2) so `--assess-quality` absent never stomps env/file; no change to `purge`'s resolution path (invariant 9's second sentence).

**Commit.** `Plumb quality_assessment config through precedence chain (IQ S1.1)`

### S1.2 — `--assess-quality` flag + pipeline selection

**Goal.** `analyze --assess-quality` runs the v1.6.0 contract; without it, byte-identical behavior.

**Files.**
- Modify: `Sources/AISidecarCLI/SharedOptions.swift`, `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift`; `Tests/AISidecarCoreTests/AnalyzePipelineTests.swift`, `NoXMPRegressionTests.swift`
- Read first: `SharedOptions.swift` fully; `AnalyzePipeline.runModel` (prompt/schema selection site, ~L786) and the test helpers at the bottom of `AnalyzePipelineTests.swift` (including the recording runner around L994).

**Do.**
1. `@Flag(help: "Also produce a perceptual quality assessment per image (adds the quality_assessment block to raw sidecars).") var assessQuality = false`; map into `overrides` as `qualityAssessment: assessQuality ? true : nil`.
2. In `AnalyzePipeline.runModel`, pass `task: configuration.taskProfile` to both `PromptRegistry.prompt` and `ResponseSchemas.schema`.
3. Tests:
   - Using the recording-runner pattern, run the pipeline with `taskProfile: .taggingWithQuality` and assert the prompt text handed to the runner starts with `PROMPT_VERSION: aisidecar.prompt.whole_image/1.6.0` (and subject 1.6.0 for `.both` mode), and the schema version passed is the 1.6.0 `$id`; with defaults, 1.5.0. If the runner seam doesn't expose prompt/schema, extend the recording runner to capture them — additive test-target change only.
   - Decode a written sidecar (`decodeSidecar` helper): `run_configuration.task_profile == "tagging_with_quality"` when enabled.
   - `NoXMPRegressionTests`: add a quality-enabled analyze run to the existing no-XMP assertion (AC-IQ-B2).

**Review checklist.** No other `AnalyzePipeline` behavior touched (render/isolation/retry paths unchanged in diff); flag help text present; the `? true : nil` idiom used.

**Commit.** `Wire --assess-quality through analyze to the v1.6.0 contract (IQ S1.2)`

### S1.3 — Quality golden sidecar + repair coverage + docs

**Goal.** End-to-end shape is pinned by a golden; repair path proven for the quality contract; docs current.

**Files.**
- Create: `Tests/AISidecarCoreTests/Fixtures/golden-sidecars/phase1-quality-combined.json`
- Modify: `Tests/AISidecarCoreTests/GoldenSidecarTests.swift`, `ModelRuntimeTests.swift`; docs: `agent_docs/prompt-and-schema-design.md`, `agent_docs/cli-implementation-notes.md`, `agent_docs/architecture-map.md`
- Read first: `GoldenSidecarTests.swift` (how the existing golden is generated/compared), the repair-path tests in `ModelRuntimeTests.swift` (~L599–645 support code in `OllamaVisionRunner`).

**Do.**
1. Add a second golden test: same harness as the existing golden but with `taskProfile: .taggingWithQuality` and a `RecordedFixtureRunner` replaying the S0.4 combined fixture; commit the generated golden after manual inspection (versions = 1.6.0, `quality_assessment` present in both runs). **The existing golden stays untouched** — it pins FR-IQ-004.
2. Repair test: drive the mock transport with the truncated quality fixture then a valid completion, assert the repair loop validates against the quality schema and succeeds (mirror the existing repair test's structure).
3. Docs (separate commit): prompt-and-schema-design.md gains a short "v1.6.0 and quality-only v1.0.0" section (version table + task-profile selection + token-budget note from doc 12 §2.1); cli-implementation-notes and architecture-map mention `--assess-quality`/`task_profile`.

**Commits.** `Add quality-enabled golden sidecar and repair coverage (IQ S1.3)`; `Document v1.6.0/quality-only contract and task profiles (IQ S1.3 docs)`

---

## 4. Phase 2 — quality-only pipeline (doc 12 §5.2.3 note, FR-IQ-020–023; issue #37)

### S2.1 — Quality sidecar naming, artifact names, cleanup

**Goal.** The `.quality.ai.json` suffix and quality batch-artifact prefixes exist and are owned by cleanup.

**Files.**
- Modify: `Sources/AISidecarCore/Sidecars/SidecarNaming.swift`, `Sources/AISidecarCore/Reporting/ArtifactNames.swift`, the cleanup recognition site (find it: `Sources/AISidecarCore/Cleanup/ArtifactCleanup.swift` scans `ArtifactNames`/suffix constants); matching tests (`XMPNamingTests` is XMP-side — sidecar-naming tests live where `SidecarNaming` is currently tested; search `SidecarNaming` in `Tests/`).
- Read first: `SidecarNaming.swift` end to end (how the `.ai.json` suffix and plan entries work), `ArtifactCleanup.swift`.

**Do.**
1. Add a suffix constant for `.quality.ai.json` beside the existing one and a way for the naming plan to target it (mirror the existing mechanism — likely a parameter or variant on the plan function; keep it additive and default to the existing suffix).
2. `ArtifactNames`: `qualityProgressPrefix = "quality-progress-"`, `qualitySummaryPrefix = "quality-summary-"`.
3. Cleanup: quality sidecars and quality batch artifacts are owned/removable; **nothing else new is** (invariant 6).
4. Tests: naming produces `<name>.<ext>.quality.ai.json`; a tagging sidecar and a quality sidecar for the same image never collide; cleanup matrix removes quality artifacts and leaves `.xmp`, backups, and tagging sidecars untouched.

**Review checklist.** Constants additive; no existing pattern string changed; cleanup ownership list grew by exactly the new artifacts.

**Commit.** `Add quality sidecar suffix, artifact prefixes, cleanup ownership (IQ S2.1)`

### S2.2 — `QualityAssessPipeline` + GPS suppression

**Goal.** A quality-only run end to end: renders, isolates (per mode), calls the quality contract, writes `.quality.ai.json`, never XMP.

**Files.**
- Create: `Sources/AISidecarCore/Pipeline/QualityAssessPipeline.swift`
- Modify: `Sources/AISidecarCore/Pipeline/AnalyzePipeline.swift` (sidecar-suffix + GPS-suppression seams), `Sources/AISidecarCore/Configuration/RunConfiguration.swift` (`with(taskProfile:)` helper); `Tests/AISidecarCoreTests/` new `QualityAssessPipelineTests.swift`, extend `NoXMPRegressionTests.swift`
- Read first: `AnalyzePipeline.swift` fully (flow summary in doc 12 §2.1), `AnalyzeAndXMPPipeline.swift` (thin-wrapper style).

**Do.**
1. `ResolvedRunConfiguration.with(taskProfile:)` — returns a copy with the profile replaced (needed because resolved configs are otherwise immutable).
2. `AnalyzePipeline` learns two things, both keyed on `configuration.taskProfile == .qualityOnly`: (a) sidecar naming targets the quality suffix (S2.1's variant); (b) GPS/model-input context is suppressed — where the `ModelInputContext` is built or passed to `runModel`, force `nil` for quality-only runs (doc 12 §5.2.3: external context is banned for assessments; the block would be dead weight).
3. `QualityAssessPipeline`: a thin struct holding an `AnalyzePipeline`; `run(inputPath:configuration:interruptionMonitor:progressHandler:)` forces the profile via the helper and delegates. Result type may reuse `AnalyzeResult`.
4. Tests: mock-runner end-to-end writes `.quality.ai.json` whose model runs record the quality-only prompt/schema versions and validate against the quality schema (AC-IQ-C1); dry-run writes nothing (AC-IQ-C2); `--existing` policies act on quality sidecars without touching a co-present tagging sidecar (byte-compare it before/after); GPS-suppression test: a source with GPS context configured still produces a prompt with no `MODEL INPUT CONTEXT` block (recording runner); interruption mid-batch follows the existing contract (mirror an existing interruption test); NoXMP extension for the quality pipeline.

**Review checklist.** No duplicated pipeline logic (the wrapper is thin; suffix/GPS are small seams inside `AnalyzePipeline`); tagging-mode runs show zero diff in recorded prompts/sidecars (covered by untouched existing tests).

**Commit.** `Add QualityAssessPipeline: quality-only runs to .quality.ai.json (IQ S2.2)`

### S2.3 — `assess-quality` subcommand + docs

**Goal.** `aisidecar assess-quality <input>` works with the shared options.

**Files.**
- Create: `Sources/AISidecarCLI/AssessQualityCommand.swift` (use the skeleton in doc 12 §5.7 verbatim, adjusted to compile against the real helpers — read `AnalyzeCommand.swift` first and mirror its interruption/exit-policy scaffolding exactly)
- Modify: `Sources/AISidecarCLI/AISidecarCommand.swift` (add to `subcommands`); docs: `agent_docs/cli-implementation-notes.md`, `architecture-map.md` (pipeline table + CLI list)
- Verification: `swift run aisidecar assess-quality --help` renders; `swift run aisidecar --help` lists it.

**Review checklist.** Command file contains argument parsing/wiring/presentation only (invariant 13); registered in the subcommands array; help text says quality-only and names the sidecar suffix.

**Commits.** `Add assess-quality subcommand (IQ S2.3)`; docs commit.

### S2.4 — Input-resolver quality-sibling support

**Goal.** Phase-2 input resolution can see both sidecars per image so grading (S4.8) has full inputs.

**Files.**
- Modify: `Sources/AISidecarCore/Sidecars/RawJSONSidecarInputResolver.swift` (+ its tests; search `RawJSONSidecarInputResolver` in `Tests/`)
- Read first: the resolver and `ResolvedRawSidecarInput` shape, and how `XMPExportPipeline.runFromJSON` builds its batch.

**Do.** Additively extend resolution so each resolved input can carry an optional quality-sidecar path/document alongside the tagging sidecar (or, if the resolver returns per-sidecar entries, ensure `.quality.ai.json` files resolve as first-class inputs grouped with their image — choose whichever matches the existing structure with the smallest diff, and record the choice in a comment). Tests: image with both sidecars → both visible, correctly associated; only-quality; only-tagging; a `.quality.ai.json` never masquerades as a tagging sidecar.

**Review checklist.** Existing resolution behavior for plain `.ai.json` unchanged (existing tests untouched and green); grouping keys can't collide across the two suffixes.

**Commit.** `Resolve .quality.ai.json siblings in raw-sidecar input resolution (IQ S2.4)`

---

## 5. Phase 3 — extraction + grading (doc 12 §5.4, §5.5; issue #38)

### S3.1 — `QualityAssessmentRecord` + extractor

**Goal.** Typed, tolerant decode of stored assessments from both sidecar kinds.

**Files.**
- Create: `Sources/AISidecarCore/Metadata/QualityAssessmentExtractor.swift`
- Tests: new `Tests/AISidecarCoreTests/QualityAssessmentExtractorTests.swift`
- Read first: doc 12 §5.4 (the types are specified there — implement them as written, including the two role-specific criterion spellings and the `Confidence: Comparable` conformance); `CandidateExtractor.swift` (issue-collection posture to mirror); `JSONValue.swift` accessors.

**Do.**
1. Implement `QualityAssessmentRecord`, `QualityExtractionResult`, `QualityExtractionIssue` (an enum with associated context: `malformedBlock`, `unknownCriterion(String)`, `missingOverall`, `invalidLevel(field: String, value: String)` — additive raw-string-stable cases), and `QualityAssessmentExtractor.extract`.
2. Decode rules: walk model runs newest-last (last valid run per role wins); read `parsed_response_json.quality_assessment`; map `overall_effectiveness`/`overall_subject_quality` → `overall`; unknown criterion keys → dropped + `unknownCriterion` issue; unparseable level → issue, criterion dropped; missing/invalid `overall` or `confidence` → record dropped + issue. Never throw for content problems.
3. Tests: happy path both roles; combined-sidecar and quality-sidecar sources; malformed matrix (one test per issue case); newest-run-wins; **regression: `CandidateExtractor` ignores `quality_assessment`** — run it over the S0.4 combined fixture and assert extracted keyword candidates are identical to the same response without the quality block.

**Review checklist.** No mutation of `CandidateExtractor`; issue enum raw values stable-string style; extractor is pure (no I/O beyond the passed-in documents).

**Commit.** `Add QualityAssessmentExtractor for stored assessments (IQ S3.1)`

### S3.2 — Tier deriver + grading types

**Goal.** Deterministic tier + channel derivation exactly per doc 12 §5.5.2/§5.5.3.

**Files.**
- Create: `Sources/AISidecarCore/Metadata/QualityGrading.swift`
- Tests: new `QualityGradingTests.swift`
- Read first: doc 12 §5.5 in full — the rule table is normative; the code blocks there are the intended implementation shape (including `urgency` derivation and the `QualityGrade` fields).

**Do.**
1. Implement `QualityTier` (Comparable by declaration order, raw values per doc 12 including `below_average`), `QualityGradingPolicy` with the exact defaults in §5.5.1 (note `urgencyMap` defaults **empty** until S4.0's capture lands), `QualityGrade`, `QualityTierDeriver.grade` including `tier.demoted()` and the subject-focus veto.
2. Ungraded outcomes return `nil` — the caller reports reasons from the record; expose a small `ungradedReason(whole:subject:policy:)` helper so S4.8 can report without duplicating gate logic.
3. Tests (AC-IQ-D1/D3): a table-driven test enumerating **every row** of the §5.5.2 rule table with representative strong/problem counts either side of each threshold, plus: veto demotes exactly one tier and appends the explanation; veto never applies when only the subject record exists; whole-precedence when both exist; confidence gate at each boundary; `rejectAsMinusOne` flips only the reject rating; urgency emitted only when a label is emitted and the map has the tier; keyword forms (`AI Quality|good`; per-criterion `AI Quality|problems|focus` sorted by criterion raw value when enabled).

**Review checklist.** Integer-only logic (no Double anywhere); rule numbers cited in comments only where a constraint isn't obvious; explanation strings human-readable and stable enough to assert.

**Commit.** `Add QualityTierDeriver and grading policy types (IQ S3.2)`

### S3.3 — Grading policy Codable + validation

**Goal.** The policy round-trips through JSON config and rejects invalid values with `SidecarError.configInvalid`.

**Files.**
- Modify: `QualityGrading.swift`; tests in `QualityGradingTests.swift`
- Read first: how existing config validation raises `SidecarError.configInvalid` in `ConfigurationResolver.resolved()`.

**Do.** Snake_case CodingKeys (`minimum_confidence`, `write_rating`, `write_label`, `write_urgency`, `write_keywords`, `reject_as_minus_one`, `per_criterion_problem_keywords`, `keyword_root`, `rating_map`, `label_map`, `urgency_map`; maps keyed by tier raw values). `validate()` throwing `configInvalid` for: rating outside −1…5; urgency outside 1…8; empty or `|`-containing label text or keyword root; unknown tier key in any map. Tests: round-trip equality; one test per rejection.

**Commit.** `Make QualityGradingPolicy configurable and validated (IQ S3.3)`

---

## 6. Phase 4 — XMP managed scalars + export integration (doc 12 §5.6; issue #39)

### S4.0 — (manual prework) Capture Capture One's Urgency mapping

Not a code stage; can run any time before S4.7 finalizes defaults. In Capture One with sidecar sync = Full Sync: apply each color tag (Red, Orange, Yellow, Green, Blue, Pink, Purple, None) to a distinct test image; open the written `.xmp` files in a text editor; record the `xmp:Label` and `photoshop:Urgency` value C1 wrote for each color. Save the table as `agent_docs/release-evidence/c1-urgency-mapping.md` (include the C1 version string). S4.7 turns the Red/Green rows (the default labels) into `urgencyMap` built-in defaults.

### S4.1 — Managed-scalar types + reader

**Goal.** The engine can read `xmp:Rating`/`xmp:Label`/`photoshop:Urgency` in both storage forms, failing closed on conflicts.

**Files.**
- Modify: `Sources/AISidecarCore/Metadata/XMPXMLSupport.swift` (namespaces + `XMPManagedScalar` exactly per doc 12 §5.6.1, including the `photoshop` cases)
- Create: `Sources/AISidecarCore/Metadata/XMPScalarReader.swift`
- Tests: extend `Tests/AISidecarCoreTests/XMPOwnedEngineTests.swift` (new section) — note the existing inline fixtures there already carry ratings/labels to read against.
- Read first: `XMPXMLSupport.swift`, `XMPDocumentParser.swift` (element walking + `locateRDFElement`), the inline fixtures in `XMPOwnedEngineTests.swift`.

**Do.** Implement `XMPScalarValueForm`, `XMPScalarOccurrence`, and `XMPScalarReader.read` per doc 12 §5.6.1: scan every `rdf:Description` for (a) attributes and (b) direct child elements matching (namespaceURI, localName); collect occurrences; zero → `nil`; multiple with **equal** normalized values → return one; differing values → throw `.xmpUnsupportedRDF`. Tests: attribute form, element form, absent, equal duplicates tolerated, conflicting values throw, all three scalars.

**Commit.** `Add managed-scalar model and reader to the XMP engine (IQ S4.1)`

### S4.2 — Scalar merge/write support

**Goal.** The engine can set a scalar, preserving existing storage form, creating attribute form when absent.

**Files.**
- Create or extend: `Sources/AISidecarCore/Metadata/XMPScalarMerger.swift` (sibling to `XMPKeywordMerger`)
- Read first: `XMPKeywordMerger.swift` (especially `ensureKeywordBag`'s lazy namespace/property creation) and `XMPDocumentWriter.swift`.

**Do.** `setScalar(_:to:in:)`: locate via `XMPScalarReader`; update in place (attribute value or element text) when present; otherwise set as an attribute on the writable `rdf:Description` (reuse the parser's `locateOrCreateWritableDescription`); declare `xmlns:xmp`/`xmlns:photoshop` on `rdf:RDF` when first needed. Tests: create-on-new-document; update attribute form in place; update element form in place (form preserved — assert the serialized XML shape); namespace declared exactly once.

**Commit.** `Add scalar write/update support to the owned XMP engine (IQ S4.2)`

### S4.3 — Fingerprint v2 + snapshot scalars

**Goal.** Managed scalars leave the unmanaged fingerprint; snapshots expose their values.

**Files.**
- Modify: `Metadata/XMPUnmanagedContentFingerprint.swift`, `XMPMetadataSnapshot.swift`; update affected tests in `XMPOwnedEngineTests.swift` **deliberately** (doc 12 §5.6.2 note)
- Read first: the fingerprint's `appendEntries` filter structure and `testParserAcceptsMissingManagedBags` (it currently asserts `"rating"` appears in canonical entries — that assertion inverts in this stage).

**Do.** Extend the managed-exclusion filters to skip elements/attributes matching any `XMPManagedScalar`; bump `algorithmVersion` to `xmp-unmanaged-content-fingerprint/2.0`. Add `rating: String?`, `label: String?`, `urgency: String?` to `XMPMetadataSnapshot`, populated via the reader in `make(from:)`/`empty`. Tests: fingerprint unchanged when only a managed scalar's value differs between two documents; still changes when any truly-unmanaged content differs (keep the `crs:Exposure2012` assertions); snapshot values populated for both storage forms.

**Review checklist.** Version string bumped exactly once; no fingerprint comparison crosses the version boundary anywhere (it's within-run only — confirm by reading `XMPMergeValidator` call sites).

**Commit.** `Exclude managed scalars from the unmanaged fingerprint (v2) (IQ S4.3)`

### S4.4 — Merge-validator scalar checks

**Goal.** Post-write validation covers scalars: planned values present; unplanned values untouched.

**Files.** `Metadata/XMPMergeValidator.swift` + `XMPMergeValidatorTests.swift`.

**Do.** Extend the validation input with the planned scalar writes (plumbed properly in S4.5 — for this stage add the parameters with defaults so existing call sites compile). Checks per scalar: plan wrote it → post value == planned value; plan didn't → pre == post. Failures use the existing `.validationFailed` error shape with distinct messages. Tests: each check's pass and fail case, all three scalars.

**Commit.** `Validate managed-scalar expectations and preservation post-write (IQ S4.4)`

### S4.5 — Change-plan/report type extensions + id bumps

**Goal.** Plans, previews, results, progress records, and reports carry scalar data; document ids bump to 1.1.

**Files.**
- Modify: `Metadata/XMPChangePlan.swift` (`PlannedScalarWrite` + `ratingWrite`/`labelWrite`/`urgencyWrite`/`qualityExplanation` + CodingKeys), `MetadataWriteEngine.swift` (`XMPWriteRequest`/`XMPWritePreview`/`XMPWriteResult` scalar fields; `MockMetadataWriteEngine` support), `Reporting/XMPExportProgressLog.swift`, `XMPExportReport.swift`, `XMPExportSchemaIdentifiers.swift` (`…-change-plan/1.1`, `…-xmp-export/1.1`)
- Tests: `XMPChangePlanTests.swift`, `XMPExportReportTests.swift`, and `XMPExportInvocationTests.testSchemaIdentifierConstantsAreStable` (update the pinned strings **in the same diff** that bumps them — the test exists to make this deliberate).

**Do.** All additive fields optional with snake_case keys per doc 12 §5.6.3; JSON encode/decode round-trip tests; a plan without scalar fields (old JSON) still decodes.

**Review checklist.** No existing CodingKey renamed; identifiers bumped minor-only; mock engine updated so downstream stages can test against it.

**Commit.** `Extend XMP plan/report types with scalar writes; bump ids to 1.1 (IQ S4.5)`

### S4.6 — Engine apply path for scalars

**Goal.** `OwnedXMPSidecarEngine` executes planned scalar writes under the full guard chain.

**Files.** `Metadata/OwnedXMPSidecarEngine.swift` + `XMPOwnedEngineTests.swift`, `XMPMergeValidatorTests.swift` as needed.
- Read first: `apply` (merge → skip-if-unchanged → atomic write) and `preview`.

**Do.** In `preview`/`apply`: after keyword merge, apply each planned scalar with action `write`/`overwrite` via `XMPScalarMerger` (a `skip_existing` action applies nothing); the nothing-changed early-exit now also checks scalars; pass planned scalars into the validator (S4.4). Tests: AC-IQ-E1 (new file with rating/label/urgency + keywords, read back via snapshot); AC-IQ-E2 (foreign XMP with `crs:*` + existing user rating, `preserve` semantics → skip action applied nothing, fingerprint gate green); write-failure path still restores (extend the existing failure-injection test to a scalar-bearing plan).

**Commit.** `Apply managed-scalar writes through the owned engine (IQ S4.6)`

### S4.7 — Quality-grading configuration + write-xmp flags

**Goal.** The grading surface resolves via the standard chain and reaches the export pipeline.

**Files.**
- Modify: `Configuration/XMPExportConfiguration.swift` (`ScalarConflictPolicy` enum `preserve|refresh|overwrite`; `ResolvedQualityGradingConfiguration` per doc 12 §5.6.4; overrides struct), `ConfigurationResolver.swift` (env keys `AISIDECAR_XMP_QUALITY_*`; builder), `AppConfig.swift` (keys: `xmp_quality_grading`, `xmp_quality_conflicts`, `xmp_quality_min_confidence`, `xmp_quality_write_rating`, `xmp_quality_write_label`, `xmp_quality_write_urgency`, `xmp_quality_write_keywords`, `xmp_quality_reject_as_minus_one`, `xmp_quality_per_criterion_problem_keywords`, `xmp_quality_keyword_root`, `xmp_quality_rating_map`, `xmp_quality_label_map`, `xmp_quality_urgency_map` — all five spots each), `Sources/AISidecarCLI/WriteXMPCommand.swift` (paired flags per doc 12 §5.7, using the existing `pairedFlag` helper), `aisidecar.config.example.jsonc`
- If S4.0 evidence exists, set `urgencyMap` built-in defaults from it (reject→Red's value, excellent→Green's value); otherwise leave empty and note in the ledger.
- Tests: `ConfigResolutionTests`/`XMPExportInvocationTests` precedence + validation matrix (S3.3's `validate()` invoked during resolution); flag conflicts rejected via `InvocationRules`.

**Commit.** `Add quality-grading configuration and write-xmp flags (IQ S4.7)`

### S4.8 — Planner hookup: grade → plan → write → stamp

**Goal.** `write-xmp --quality-grading` produces graded plans and guarded writes end to end. The largest stage; keep sub-steps green.

**Files.**
- Modify: `Metadata/XMPChangePlanner.swift`, `Pipeline/XMPExportPipeline.swift` (stamp extension), `Sidecars/RawSidecarExportStamp.swift` (additive fields `rating`, `label`, `urgency`, `quality_tier`)
- Tests: `XMPChangePlanTests.swift`, `XMPExportPipelineTests.swift`
- Read first: `XMPChangePlanner.plan` and `plannedKeywords`, `XMPExportPipeline.executeTarget` + `stampSourceSidecars`, doc 12 §5.6.4.

**Do.**
1. When grading is enabled: per target, run `QualityAssessmentExtractor` over the target's contributing sidecars (tagging + quality siblings via S2.4), derive the grade (S3.2), and:
   - Resolve each channel against the pre-read snapshot into a `PlannedScalarWrite` with action per policy — `preserve`: absent→`write`, equal→`skipExisting`, different→`skipExisting` (reported); `refresh`: as preserve, but different-and-equal-to-newest-stamp-value→`overwrite`; missing stamp → preserve behavior; `overwrite`: always `overwrite` with `existingValue` recorded.
   - Merge quality keywords into the planned keyword lists: hierarchical entries as the `|` paths; flat entries as space-joined components (doc 12 §5.5.3); both through `KeywordSafetyPolicy`.
   - Attach `qualityExplanation`; ungraded targets get a reported reason (never silent — FR-IQ-034).
2. After successful writes, `stampSourceSidecars` includes the scalar values + tier.
3. Tests: conflict matrix — (absent / equal / different-foreign / different-matches-stamp / different-stamp-missing) × (preserve / refresh / overwrite), asserting action and, end to end on temp files, the final XMP content (covers AC-IQ-E3 and AC-IQ-E6); keyword-form assertions in the written plan; dry-run plan JSON snapshot shows scalar rows and explanation; a quality-only-sidecar image grades correctly; an assessment below the confidence gate reports ungraded.

**Review checklist.** Grading path only executes under `--quality-grading` (default-off run produces byte-identical plans to pre-feature — assert with an existing fixture); stamp comparison uses the **newest** stamp among contributors; no new write path outside `executeTarget`'s chain (invariant 4).

**Commit.** `Grade assessments into XMP change plans and guarded writes (IQ S4.8)`

### S4.9 — Phase-4 documentation pass

Update `agent_docs/02-cli-xmp-sidecar-requirements-updated.md` (addendum note: managed scalars under F12 rules), `architecture-map.md` (Metadata row + artifacts), `cli-implementation-notes.md` (flags), `testing-and-verification.md` (new smoke checks: a dry-run `write-xmp --quality-grading` command). Docs-only commit: `Document quality grading and managed scalars (IQ S4.9 docs)`.

---

## 7. Phase 5 — live verification (manual; doc 12 §8)

These stages are maintainer-run; agents prepare commands and record results.

- **S5.1 — Bench:** real-model runs over the TestingFileSet for `.tagging` vs `.taggingWithQuality` vs quality-only; record `runtime_metrics.eval_count` distributions, repair rates, and a wire-form grammar probe (no post-root output at temperature 0) in `benchmarks/`. Gate: quality medians must leave ≥ 2× headroom under `model_max_response_tokens` 2048, else raise the default and record why.
- **S5.2 — App evidence:** per doc 12 §6 IQ-M5 item 2 — LR Classic (rating/label/keyword filters; Urgency harmless) and Capture One (rating; color via Urgency; whether current C1 reads `xmp:Label`; keywords), plus a live `refresh` re-grade. Record under `agent_docs/release-evidence/`.
- **S5.3 — Truth-up:** update doc 12 §2.2's matrix, §9.2 decisions D-7/D-9, user-facing docs, and (if warranted) `urgencyMap`/`writeUrgency` defaults, citing the evidence files.

---

## Appendix A — `quality_assessment` schema content

### A.1 Whole-image property (for `whole_image_v1.6.0.json` and `whole_image_quality_v1.0.0.json`)

```json
"quality_assessment": {
  "type": "object",
  "additionalProperties": false,
  "description": "Whole-image perceptual quality assessment. Keep separate from tags and proposed keywords.",
  "required": [
    "focus", "composition", "exposure_and_tone", "lighting_and_color",
    "subject_background_relationship", "moment_or_expression",
    "technical_cleanliness", "overall_effectiveness",
    "strengths", "concerns", "confidence"
  ],
  "properties": {
    "focus": { "$ref": "#/$defs/quality_level", "description": "Whether the intended subject or important detail is appropriately sharp. Do not penalize effective intentional motion blur." },
    "composition": { "$ref": "#/$defs/quality_level", "description": "Framing, balance, visual hierarchy, edge control, and distracting mergers." },
    "exposure_and_tone": { "$ref": "#/$defs/quality_level", "description": "Whether important highlights, shadows, and midtones are suitably rendered." },
    "lighting_and_color": { "$ref": "#/$defs/quality_level", "description": "Effectiveness and coherence of light direction, contrast, white balance, and color." },
    "subject_background_relationship": { "$ref": "#/$defs/quality_level", "description": "Subject separation, depth-of-field use, background contribution, and distractions. Use unrated when no distinct subject exists." },
    "moment_or_expression": { "$ref": "#/$defs/quality_level", "description": "Effectiveness of visible gesture, expression, behavior, or timing. Use unrated when not relevant." },
    "technical_cleanliness": { "$ref": "#/$defs/quality_level", "description": "Obvious visible noise, halos, banding, compression, oversmoothing, masking, or other processing artifacts." },
    "overall_effectiveness": { "$ref": "#/$defs/quality_level", "description": "Overall photographic effectiveness relative to the visible subject, genre, and apparent intent; do not calculate an average." },
    "strengths": { "type": "array", "maxItems": 2, "description": "Up to two concise visible strengths. Use an empty array when none are clear.", "items": { "$ref": "#/$defs/quality_note" } },
    "concerns": { "type": "array", "maxItems": 2, "description": "Up to two concise visible weaknesses. Use an empty array when none are clear.", "items": { "$ref": "#/$defs/quality_note" } },
    "confidence": { "$ref": "#/$defs/confidence", "description": "Confidence in the quality assessment as a whole." }
  }
}
```

### A.2 Subject-isolated property (for `subject_isolated_v1.6.0.json` and `subject_isolated_quality_v1.0.0.json`)

```json
"quality_assessment": {
  "type": "object",
  "additionalProperties": false,
  "description": "Perceptual quality assessment of the isolated subject only. Keep separate from tags and proposed keywords.",
  "required": [
    "focus", "exposure_and_tone", "lighting_and_color", "detail_and_texture",
    "pose_expression_or_moment", "technical_cleanliness",
    "overall_subject_quality", "strengths", "concerns", "confidence"
  ],
  "properties": {
    "focus": { "$ref": "#/$defs/quality_level", "description": "Sharpness of the subject's important features. Do not judge original frame placement." },
    "exposure_and_tone": { "$ref": "#/$defs/quality_level", "description": "Whether subject detail is retained in highlights, shadows, and midtones." },
    "lighting_and_color": { "$ref": "#/$defs/quality_level", "description": "Whether light and color render the subject clearly and coherently." },
    "detail_and_texture": { "$ref": "#/$defs/quality_level", "description": "Natural preservation of important texture and fine detail without smearing or excessive sharpening." },
    "pose_expression_or_moment": { "$ref": "#/$defs/quality_level", "description": "Effectiveness of visible pose, expression, gesture, or behavior. Use unrated when not relevant." },
    "technical_cleanliness": { "$ref": "#/$defs/quality_level", "description": "Obvious visible noise, halos, compression, oversmoothing, or processing artifacts on the subject. Ignore isolation-edge artifacts unless they obscure detail." },
    "overall_subject_quality": { "$ref": "#/$defs/quality_level", "description": "Overall quality of the isolated subject only; do not assess composition, background, or scene context." },
    "strengths": { "type": "array", "maxItems": 2, "description": "Up to two concise visible subject strengths. Use an empty array when none are clear.", "items": { "$ref": "#/$defs/quality_note" } },
    "concerns": { "type": "array", "maxItems": 2, "description": "Up to two concise visible subject weaknesses. Use an empty array when none are clear.", "items": { "$ref": "#/$defs/quality_note" } },
    "confidence": { "$ref": "#/$defs/confidence", "description": "Confidence in the subject-quality assessment as a whole." }
  }
}
```

### A.3 Shared `$defs` additions

```json
"quality_level": {
  "type": "string",
  "enum": ["problem", "acceptable", "strong", "unrated"],
  "description": "Use problem for a visible weakness, acceptable for adequate execution, strong when the criterion materially supports the photograph, and unrated when the criterion is not relevant or cannot be judged reliably."
},
"quality_note": {
  "type": "string",
  "minLength": 1,
  "maxLength": 160,
  "pattern": "^[^\\r\\n\\t]+$",
  "description": "One concise visible observation, not a reasoning trace or edit instruction."
}
```

### A.4 Valid fixture objects (for tests)

Whole-image:

```json
{
  "focus": "strong",
  "composition": "acceptable",
  "exposure_and_tone": "acceptable",
  "lighting_and_color": "strong",
  "subject_background_relationship": "acceptable",
  "moment_or_expression": "unrated",
  "technical_cleanliness": "acceptable",
  "overall_effectiveness": "acceptable",
  "strengths": ["sharp eye detail", "warm directional light"],
  "concerns": [],
  "confidence": "high"
}
```

Subject-isolated:

```json
{
  "focus": "strong",
  "exposure_and_tone": "acceptable",
  "lighting_and_color": "acceptable",
  "detail_and_texture": "strong",
  "pose_expression_or_moment": "unrated",
  "technical_cleanliness": "acceptable",
  "overall_subject_quality": "strong",
  "strengths": ["crisp feather texture"],
  "concerns": ["slight highlight clipping on wing"],
  "confidence": "medium"
}
```

---

## Appendix B — prompt text

### B.1 `QUALITY ASSESSMENT` section for `whole_image_v1.6.0.txt`

```
QUALITY ASSESSMENT

The supplied schema includes quality_assessment. Complete every required field
in that object as a separate evaluation of the complete photograph.

Keep quality separate from tagging. The ban on image-quality terms applies to
genre_or_photography_type, species, main_subjects, secondary_subjects,
scene_context, habitat_or_setting, behavior_or_action, proposed_keywords, and
evidence strings. Put quality judgments only in quality_assessment.

Use only visible image evidence for quality. Do not use GPS, EXIF, filename,
location, species likelihood, or other external context. Do not estimate
numeric sharpness, clipping, noise, color accuracy, resolution, capture
settings, or edit history. Rate focus, fine detail, and artifacts only when
visible at the supplied resolution; otherwise use unrated.

Quality levels: problem is a clear visible weakness that reduces
effectiveness; acceptable is adequate or neutral, not a notable strength;
strong clearly contributes to the photograph; unrated means not relevant or
not reliably judgeable. Do not use strong merely because no problem is
visible. Judge intentional choices by their visible effect; do not mark blur,
darkness, grain, shallow depth of field, or unusual color as problems merely
because they are unconventional.

Assess composition and subject_background_relationship from the complete
frame. Use unrated for subject_background_relationship when no distinct
subject exists. Use unrated for moment_or_expression when timing, gesture,
behavior, or expression is not relevant. technical_cleanliness covers only
obvious visible artifacts.

overall_effectiveness is a separate holistic judgment, not an average.
strengths and concerns contain at most two short visible observations each,
must agree with the ratings, and use [] when none are clear. Do not give
editing instructions. confidence is confidence in the assessment, not a
quality score.
```

### B.2 `QUALITY ASSESSMENT` section for `subject_isolated_v1.6.0.txt`

```
QUALITY ASSESSMENT

The supplied schema includes quality_assessment. Complete every required field
in that object as a separate evaluation of the isolated subject.

Keep quality separate from tagging. The ban on image-quality terms applies to
genre_or_photography_type, species, main_subjects, secondary_subjects,
behavior_or_action, proposed_keywords, and evidence strings. Put quality
judgments only in quality_assessment.

Use only visible subject evidence for quality. Do not use GPS, EXIF, filename,
location, species likelihood, or other external context. Do not estimate
numeric sharpness, clipping, noise, color accuracy, resolution, capture
settings, or edit history. Rate focus, fine detail, and artifacts only when
visible at the supplied crop resolution; otherwise use unrated.

Quality levels: problem is a clear visible weakness that reduces subject
quality; acceptable is adequate or neutral, not a notable strength; strong
clearly supports the rendering or presentation of the subject; unrated means
not relevant or not reliably judgeable. Do not use strong merely because no
problem is visible.

Assess only the isolated subject as shown. Do not assess whole-frame
composition, framing, background, habitat, setting, or subject-background
relationship, and do not infer the original frame. Ignore the neutral matte,
removed background, crop boundary, and ordinary isolation edges; treat an
isolation artifact as a concern only when it obscures or alters subject
detail. When missing or cropped detail prevents a reliable judgment, use
unrated rather than problem.

Judge intentional choices by their visible effect; do not mark blur, darkness,
grain, shallow depth of field, or unusual color as problems merely because
they are unconventional. Use unrated for pose_expression_or_moment when pose,
gesture, behavior, or expression is not relevant. technical_cleanliness covers
only obvious visible defects on the subject.

overall_subject_quality is a separate holistic judgment of the subject only,
not an average. strengths and concerns contain at most two short visible
observations each, must agree with the ratings, and use [] when none are
clear. Do not give editing instructions. confidence is confidence in the
assessment, not a quality score.
```

### B.3 `whole_image_quality_v1.0.0.txt` (complete file)

The complete file is given in doc 12 §5.2.3 — use it verbatim.

### B.4 `subject_isolated_quality_v1.0.0.txt` (complete file)

```
PROMPT_VERSION: aisidecar.prompt.subject_isolated_quality/1.0.0

Assess the perceptual quality of the isolated subject crop and return exactly
one JSON object matching the supplied JSON Schema.

The background has been removed, replaced, cropped away, or composited onto a
neutral matte. Judge only the subject itself.

OUTPUT RULES

Return only the JSON object: no Markdown, no code fences, no comments, no
fields beyond the schema. Complete every required field of quality_assessment.

QUALITY RULES

Use only visible subject evidence. Do not use GPS, EXIF, filename, location,
or other external context. Do not estimate numeric sharpness, clipping, noise,
color accuracy, resolution, capture settings, or edit history. Rate focus,
fine detail, and artifacts only when visible at the supplied crop resolution;
otherwise use unrated.

QUALITY LEVELS

- problem: a clear visible weakness that reduces subject quality.
- acceptable: adequate or neutral; not a notable strength.
- strong: clearly supports the rendering or presentation of the subject.
- unrated: not relevant or not reliably judgeable.

Do not use strong merely because no problem is visible. Assess only the
isolated subject as shown. Do not assess whole-frame composition, framing,
background, habitat, setting, or subject-background relationship, and do not
infer the original frame.

Ignore the neutral matte, removed background, crop boundary, and ordinary
isolation edges. Treat an isolation artifact as a concern only when it
obscures or alters subject detail. When missing or cropped detail prevents a
reliable judgment, use unrated rather than problem.

Judge intentional choices by their visible effect. Do not mark blur, darkness,
grain, shallow depth of field, or unusual color as problems merely because
they are unconventional. Use unrated for pose_expression_or_moment when pose,
gesture, behavior, or expression is not relevant. technical_cleanliness covers
only obvious visible defects on the subject.

overall_subject_quality is a separate holistic judgment of the subject only,
not an average. strengths and concerns contain at most two short visible
observations each, must agree with the ratings, and use [] when none are
clear. Do not give editing instructions. confidence is confidence in the
assessment, not a quality score.

Return only the JSON object.
```
