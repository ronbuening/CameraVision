# Image Quality Assessment — Requirements and Implementation Plan

Version: 1.0
Date: 2026-07-15
Status: planned (no code started)
Origin: GitHub milestone 1 "Image Quality Assessment" — issues [#30](https://github.com/ronbuening/CameraVision/issues/30), [#31](https://github.com/ronbuening/CameraVision/issues/31), [#36](https://github.com/ronbuening/CameraVision/issues/36), [#37](https://github.com/ronbuening/CameraVision/issues/37), [#38](https://github.com/ronbuening/CameraVision/issues/38), [#39](https://github.com/ronbuening/CameraVision/issues/39)
Audience: maintainer (decision points, §9) and junior engineer / Sonnet-level agent (execution: §5–§8 are written to be executable unaided)

Position in sequence: maintainer-directed work, inserted ahead of the roadmap's default order by the milestone itself. It does not depend on M9–M11 or the efficiency backlog. It **is** the first scoped XMP namespace expansion under roadmap doc 09 §F12's per-field rules (`xmp:Rating` and `xmp:Label` become managed fields); the F12 process requirements are folded into Stream E below so no separate F12 pass is needed for these two fields.

Precedence: `agent_docs/invariants.md` > this document. Every invariant applies; the ones this feature touches hardest are 1 (analyze never writes XMP), 4 (all XMP writes through the guarded engine), 7 (stable raw strings), 8 (additive schemas), 9 (config precedence), 12 (offline tests), 13 (Core/CLI/GUI split).

---

## 0. How to use this document

- §1 defines the feature and maps requirements to the GitHub issues (traceability).
- §2 records the facts the design rests on: what the codebase supports today and what Lightroom Classic / Capture One actually read from XMP. Do not re-litigate these facts during implementation; if one turns out wrong, stop and update this document first.
- §3 reviews the schema/prompt addendums attached to issues #30/#31 and states exactly what is adopted, what is amended, and why.
- §4 is the formal requirements list (FR-IQ / AC-IQ IDs).
- §5 is the design: every new type, every touched file, with example source.
- §6 is the milestone plan (IQ-M0 … IQ-M6). One milestone at a time, `swift test` green and a commit at each boundary, docs commits separate from code commits.
- §7 is the consolidated test plan, §8 live verification / release evidence, §9 open decisions for the maintainer.

Terminology used throughout:

| Term | Meaning |
|---|---|
| **assessment** | The model's `quality_assessment` object in a raw sidecar (subjective, produced once per model run). |
| **grading** | The deterministic, replayable mapping from stored assessments to XMP-facing values (tier → rating/label/keywords). Never involves the model. |
| **tier** | The derived 5-value quality bucket (`reject`, `below_average`, `neutral`, `good`, `excellent`) that all output mappings key on. |
| **combined mode** | `analyze --assess-quality`: tagging + assessment in one model call per role (issue #36). |
| **quality-only mode** | `assess-quality` subcommand: assessment without tagging (issue #37). |

---

## 1. Feature overview and traceability

### 1.1 What the feature does

1. The vision model, in addition to (or instead of) tagging, produces a structured **perceptual quality assessment** per image — per-criterion levels (`problem` / `acceptable` / `strong` / `unrated`), up to two strengths/concerns, and a confidence band — recorded in the raw `.ai.json` sidecar exactly like every other model output (Streams A–C).
2. A deterministic, user-configurable **grading policy** maps stored assessments to a quality tier, and the tier to any combination of three output channels (Stream D):
   - `xmp:Rating` (0–5 stars, optionally −1 for rejected),
   - `xmp:Label` (color label text),
   - hierarchical quality keywords (e.g. `AI Quality|reject`).
3. The owned XMP engine learns to write the two new **managed scalar fields** (`xmp:Rating`, `xmp:Label`) under the same guarantees as keywords: change plan first, backups, merge validation, restore on failure, and never clobbering user-set values by default (Stream E).
4. The result is filterable culling in Lightroom Classic and Capture One using each app's native metadata filters (rating ≥ N, label = Red, keyword contains `AI Quality`).

The two-step split (assess once, grade many times) is deliberate: assessments are expensive (a model call) and subjective; grading is free, deterministic, and replayable. A user can re-grade an entire library with a stricter policy without touching the model, exactly as Phase 3 re-applies sessions without re-analyzing.

### 1.2 Traceability matrix

| GitHub issue | Requirement IDs | Milestone |
|---|---|---|
| #30 Add Quality Assessments to Schema | FR-IQ-001, 003, 004, 005 | IQ-M0 |
| #31 Add Quality Assessments to Prompt | FR-IQ-002, 003, 004 | IQ-M0 |
| #36 Quality flags in existing analyze pipeline | FR-IQ-010–013 | IQ-M1 |
| #37 Quality-assessment-only CLI pipeline | FR-IQ-020–023 | IQ-M2 |
| #38 Algorithm for quality → flags/colors/tags | FR-IQ-030–034 | IQ-M3 |
| #39 XMP engine flags and colors | FR-IQ-040–046 | IQ-M4 |
| Milestone description: "user driven" | FR-IQ-032 (config), §9 decisions | IQ-M3/M4 |
| #36 "for use in the GUI" | FR-IQ-060 (outline only) | IQ-M6 (follow-on) |

Issue #30 names four criteria (focus, composition, noise, exposure). The adopted addendum schema (§3) supersedes that list with a richer superset: noise is covered by `technical_cleanliness`, exposure by `exposure_and_tone`, and it adds lighting/color, detail, subject-background relationship, and moment/expression. This is treated as satisfying #30, not diverging from it.

---

## 2. Facts the design rests on

### 2.1 Codebase facts (verified 2026-07-15)

**Model runtime** (`Sources/AISidecarCore/ModelRuntime/`, resources in `Sources/AISidecarCore/Resources/ModelRuntime/`):

- Active contract is v1.5.0 per role: `whole_image_v1.5.0.{txt,json}`, `subject_isolated_v1.5.0.{txt,json}`. Selection is a hard-coded switch in `PromptRegistry.resourceName(for:)` and `ResponseSchemas.resourceName(for:)` (both at lines 12–19 of their files). Version files are immutable once shipped; a new version = new files + repointed switch (see `agent_docs/prompt-and-schema-design.md`).
- Both 1.5.0 schemas already define `$defs.confidence` = enum `high|medium|low` — the addendums' `$ref: "#/$defs/confidence"` resolves cleanly.
- Ollama grammar enforcement: `$ref`/`$defs` and `pattern` are poison pills **in the wire form**, but `OllamaWireSchema.wireSchema(from:)` inlines refs and strips `pattern`/`description`/`$id`/`title`/`$schema` before sending. The addendums' constructs (`$ref`, nested object with `required` + `additionalProperties:false`, `enum`, `maxItems`, `minLength`/`maxLength`, `pattern`) are all either grammar-enforced or already stripped. No transform change is needed.
- Anything the model must always emit goes in top-level `required` (the v1.4.0 → v1.5.0 lesson). The addendums correctly append `quality_assessment` to `required`.
- Field emission is alphabetical (`JSONCoding` re-encodes with `.sortedKeys`). Within `quality_assessment`, the model will emit `concerns` and `confidence` *before* most criterion levels. Precedent exists (candidates emit `confidence` before `term`); prompts must not assume order and the addendum text doesn't.
- The parsed response is stored untyped as `model_runs[*].parsed_response_json` (`JSONValue`); there is no typed response struct. `response_schema_version` and `prompt_version` are recorded per run. The sidecar container version `ai-sidecar-json/1.3` is a separate axis and does **not** need a bump for a new response field.
- `CandidateExtractor` iterates only the eight `CandidateSourceField` array fields; it will silently ignore `quality_assessment` (regression-test this, don't change it).
- Token budget: measured healthy responses are median 577 / p99 796 tokens against a 2048 `num_predict` cap. The assessment object adds ~11 short keys + ≤4 notes ≤160 chars — estimated +200–350 output tokens, and the prompt addendum ~+300 input tokens. Within budget, but IQ-M5 must re-measure `runtime_metrics.eval_count` on real runs before the feature is recommended for defaults.

**XMP engine** (`Sources/AISidecarCore/Metadata/`):

- The engine manages exactly two fields, both keyword *bags*: `dc:subject` and `lr:hierarchicalSubject`, modeled by the `XMPManagedField` enum (`XMPXMLSupport.swift:10–34`) that the parser, reader, merger, fingerprint, and validator all iterate. The abstraction assumes bag-of-`rdf:li`; scalars do not fit it.
- The `xmp` namespace (`http://ns.adobe.com/xap/1.0/`) is not declared anywhere (`XMPNamespace`, `XMPXMLSupport.swift:3–8`).
- Everything the engine doesn't manage is protected by `XMPUnmanagedContentFingerprint` (SHA-256 over canonical entries of all unmanaged elements/attributes/text), enforced as a hard equality gate post-write (`XMPMergeValidator.swift:97–101`); a failed gate triggers backup restore (`XMPExportPipeline.swift:396–409`). **Today `xmp:Rating`/`xmp:Label` are unmanaged content — writing them would trip the gate.** Making them writable requires reclassifying them as managed (excluded from the fingerprint) and giving them their own expectation/preservation validation.
- `XMPChangePlan`, `XMPWriteRequest`, `XMPWritePreview`, `XMPWriteResult`, `XMPExportProgressRecord`, and `XMPExportReport` are all keyword-array-shaped; each needs additive scalar fields. Schema id constants live in `Reporting/XMPExportSchemaIdentifiers.swift` and are guarded by `XMPExportInvocationTests.testSchemaIdentifierConstantsAreStable`.
- Existing test fixtures already carry `xmp:Rating`/`xmp:Label` **as unmanaged content** (`XMPOwnedEngineTests.swift:53–64, 504–539`) — those tests will be affected by reclassification and must be updated deliberately, not mechanically.

**Pipelines/CLI/config**:

- Boolean option template (e.g. `recursive`): `@Flag` in `SharedOptions` → `overrides` (`flag ? true : nil`) → `RunConfigurationOverrides` → env in `ConfigurationResolver.environmentOverrides` → `AppConfig` (five touch points; unknown config keys are rejected) → `ConfigurationBuilder` → `ResolvedRunConfiguration` (with `decodeIfPresent … ?? builtInDefaults` for old-sidecar compatibility).
- New subcommand = one file in `Sources/AISidecarCLI/` + registration in `AISidecarCommand.subcommands`.
- New batch artifacts need prefixes in `Reporting/ArtifactNames.swift` (also the single source of truth `cleanup` scans) and schema-id constants.
- `AnalyzeAndXMPPipeline` is the composition template; its `rawInputBatch(from:)` adapter (lines 105–153) is the seam that hands Phase-1 output to the Phase-2 export pipeline.

### 2.2 External-application compatibility (the honest matrix)

These facts shape the whole Stream D/E design. Each row must be re-verified live in IQ-M5 (release-evidence pattern) before the compatibility claims go in user-facing docs.

| Mechanism | XMP property | Lightroom Classic | Capture One | Verdict for this feature |
|---|---|---|---|---|
| Star rating | `xmp:Rating` (0–5) | Reads & writes; filterable | Reads & writes; filterable | **Primary channel.** The only fully standardized, symmetric field. |
| Rejected marker | `xmp:Rating = -1` (XMP spec "rejected") | **Ignored** (flags are catalog-local) | Not supported | Opt-in only (Bridge honors it); off by default. |
| Color label | `xmp:Label` (free text) | Reads & writes; matches text against the user's configured label set (default set: `Red`, `Yellow`, `Green`, `Blue`, `Purple`); non-matching text shows as a white/custom label | *Writes* `None/Red/Orange/Yellow/Green/Blue/Pink/Purple`; historically **reads `photoshop:Urgency` rather than `xmp:Label`** (asymmetric; newer builds reportedly prefer the label name — must verify live) | **Secondary channel.** Default label values chosen from the LR-default ∩ C1 set (`Red`, `Yellow`, `Green`, `Blue`, `Purple`); text fully configurable. `photoshop:Urgency` ships as a companion managed scalar (D-4, resolved 2026-07-15) so Capture One label reading works regardless of its `xmp:Label` behavior; its value mapping is captured empirically before defaults ship (§6 IQ-M4 prework). |
| Pick/Reject flag | — (none exists) | Flags are catalog-only; **never written to or read from XMP** | No flag concept (uses color tags) | **No portable flag exists.** Issue #38's "Flags (Pick, Reject)" is delivered as a *mapping convention*: reject tier → label and/or keyword and/or optional `Rating=-1`, documented as such. |
| Keywords | `dc:subject` + `lr:hierarchicalSubject` | Full support, filterable | Full support, filterable | **Always-works channel**; already implemented by the engine. Quality tiers as hierarchical keywords are the most portable filter of all. |

Sources: [Adobe — Metadata basics and actions in Lightroom Classic](https://helpx.adobe.com/lightroom-classic/help/metadata-basics-actions.html), [Ask Tim Grey — Preserving Metadata Beyond Lightroom Classic](https://asktimgrey.com/2022/12/02/preserving-metadata-beyond-lightroom-classic/) (flags/virtual copies/collections excluded from XMP), [FastRawViewer — XMP color labels compatible with either C1 or LR, not both](https://www.fastrawviewer.com/node/395), [FastRawViewer — Capture One / LR / FRV metadata](https://www.fastrawviewer.com/node/485), [Capture One community — color labels not read from xmp](https://support.captureone.com/hc/en-us/community/posts/360009396057-Lightroom-migration-bug-Color-labels-not-read-from-xmp), [Image Alchemist — Sync Metadata Between Photo Mechanic and Capture One](https://imagealchemist.net/sync-metadata-between-photo-mechanic-and-capture-one/).

Design consequences:

1. `xmp:Rating` is the backbone; every default assumes it works everywhere.
2. Color labels are best-effort cross-app; the label *text* must be configurable because label sets are user-configurable in both apps.
3. "Flags" ship as documented conventions on top of rating/label/keywords — the plan never promises LR pick flags.
4. Keywords are the portability floor and also the only channel that can carry *why* (per-criterion problem tags, opt-in).

---

## 3. Addendum review (issues #30/#31 attachments)

The four attached addendum files are adopted as the substance of the v1.6.0 contract, with the amendments below. Anything not listed here is adopted verbatim.

### 3.1 Adopted as-is (and why they're right)

- **Separate `quality_assessment` object, appended to `required`.** Matches the grammar lesson (required-only enforcement) and keeps quality out of the keyword flow.
- **4-level `quality_level` enum** (`problem/acceptable/strong/unrated`) instead of a numeric scale. Correct call: VLMs are unreliable on fine-grained numeric scales, and ordinal-band precedent (`confidence`) exists. Star granularity is recovered deterministically at grading time from (overall level × criterion counts × confidence) — see §5.5. `unrated` as an explicit level is essential (grammar can't make fields conditional).
- **`maxItems: 2` strengths/concerns with 160-char items.** Grammar-enforceable bounds that stop repetition loops, same trick as the 220-char evidence bound.
- **Prompt discipline**: visible-evidence-only, no EXIF/GPS inference, "do not use strong merely because no problem is visible", intentional-choice tolerance (blur/grain/dark not auto-problems), `unrated` over `problem` when unjudgeable. All consistent with the base prompts' evidence rules and invariant 3's spirit.
- **Role asymmetry**: whole-image assesses composition/subject-background; subject-isolated explicitly does not, and ignores matte/isolation edges unless they obscure detail. Matches the existing role split exactly.

### 3.2 Amendments (each with justification)

| # | Amendment | Justification |
|---|---|---|
| A-1 | The addendums are shipped as **new immutable version files** — `whole_image_v1.6.0.{txt,json}`, `subject_isolated_v1.6.0.{txt,json}` — not as a merge into the 1.5.0 files. `$id` becomes `urn:aisidecar:response:whole-image:1.6.0` / `…:subject-isolated:1.6.0`; `PROMPT_VERSION` becomes `aisidecar.prompt.whole_image/1.6.0` / `…subject_isolated/1.6.0`. The addendum JSON "merge instructions" files themselves are not shipped as resources. | Invariants 7/8 and the documented shipping process: version files are immutable once shipped; a new version is a new pair of files plus a registry pointer change. |
| A-2 | The prompt addendum text is integrated as a `QUALITY ASSESSMENT` section **before** the final `Return only the JSON object.` line, and the addendum's own duplicate closing line ("Return only the JSON object matching the supplied schema.") is dropped. The `PROMPT_ADDENDUM_VERSION` header line is dropped; provenance is carried by the file's `PROMPT_VERSION` + recorded `prompt_sha256`. | `PromptRegistry` parses exactly one `PROMPT_VERSION:` header on line 1; a second header mid-file would be sent to the model as prompt text. Duplicate closing lines waste budget tokens. |
| A-3 | The whole-image addendum's field-name list ("genre, species, subject, scene, habitat, behavior…") is rewritten to the actual schema field names: `genre_or_photography_type, species, main_subjects, secondary_subjects, scene_context, habitat_or_setting, behavior_or_action, proposed_keywords, and evidence strings`. Subject-isolated likewise (minus `scene_context`/`habitat_or_setting`). | The model sees these exact key names in the schema; prompts that name fields loosely invite mismatches. Cheap fix, zero token cost. |
| A-4 | Quality-only mode (#37) gets **standalone** contract files rather than "the 1.6.0 schema minus tagging": `whole_image_quality_v1.0.0.{txt,json}` (`urn:aisidecar:response:whole-image-quality:1.0.0`, `aisidecar.prompt.whole_image_quality/1.0.0`) and `subject_isolated_quality_v1.0.0.{txt,json}`. Their schemas contain only `quality_assessment` (with `quality_level`, `quality_note`, and a **copied** `confidence` def in `$defs`); their prompts are short standalone texts (§5.2.3). | #37 says "the schema from #30 and prompt from #31 *or a derivation thereof*". A quality-only call with the full tagging schema would force the model to emit ~500 tokens of tagging output nobody asked for; the derivation keeps quality-only runs ~3–4× cheaper on output tokens. The `confidence` def must be copied because standalone schemas have no base `$defs` to reference. |
| A-5 | In the quality-only schemas, `quality_assessment` stays a **nested object under the root** (root = object with one required property `quality_assessment`), not flattened to the root. | Keeps `parsed_response_json.quality_assessment` at the same JSON path in both combined and quality-only sidecars, so the extractor (§5.4) has exactly one lookup path. |
| A-6 | No schema-technical changes to the addendum JSON: `$defs`/`$ref`/`pattern` are kept in the authoritative files. | `OllamaWireSchema` already inlines/strips them; local validation still enforces `pattern`. Removing them would weaken the authoritative contract for no wire benefit. |

### 3.3 Considered and rejected

- **Making `quality_assessment` optional in one always-active schema** — rejected: the grammar can't enforce optional-when-configured, and the v1.4.0 conditional-species failure is the direct precedent. Opt-in is expressed by *version selection* (1.5.0 vs 1.6.0), not by optional fields.
- **A 5-point overall enum** to feed star ratings directly — rejected: pushes a hard calibration problem into the model (where it's opaque and unfixable) instead of the grading policy (where it's configurable and replayable).
- **Injecting the quality addendum as a runtime prompt block** (the GPS-context pattern) — rejected: the GPS block carries *data* with fixed rules; quality changes the *response schema*, which the injection mechanism cannot do. Version selection is the correct lever, and it keeps prompt+schema pairs atomic.
- **Writing `photoshop:Urgency` for Capture One label reading** — initially deferred; **resolved 2026-07-15 (D-4): in scope for IQ-M4** as the third managed scalar. Because its tier→value mapping is not reliably documented, the mapping is captured empirically from Capture One itself (IQ-M4 prework, §6) before default values ship.

---

## 4. Formal requirements

### Stream A — model contract (issues #30, #31 → IQ-M0)

- **FR-IQ-001** Ship `whole_image_v1.6.0.json` and `subject_isolated_v1.6.0.json`: byte-wise the 1.5.0 schemas plus the addendum content as amended in §3.2 (`quality_assessment` in `required` and `properties`; `quality_level` + `quality_note` added to `$defs`; `$id`/`title` bumped). Old files untouched.
- **FR-IQ-002** Ship `whole_image_v1.6.0.txt` and `subject_isolated_v1.6.0.txt`: the 1.5.0 prompts plus an integrated `QUALITY ASSESSMENT` section per §3.2 A-2/A-3, `PROMPT_VERSION` bumped. Base prompts still contain no GPS/EXIF/external-context language (regression test stays green).
- **FR-IQ-003** Ship standalone quality-only contract files per §3.2 A-4/A-5 for both roles.
- **FR-IQ-004** Registry selection becomes task-aware (§5.2): `(role, task)` → resource name. `tagging` task keeps selecting the 1.5.0 files — a run without quality enabled is byte-identical in prompt, wire schema, and sidecar provenance to today's runs.
- **FR-IQ-005** Wire-schema compatibility proven: a unit test asserts the derived wire form of every new schema contains no `$ref`/`$defs`/`pattern`/`description` and preserves `required`, `enum`, `additionalProperties:false`, and item/length bounds. Before IQ-M1 merges, a live probe (documented in `benchmarks/`, not CI) confirms grammar enforcement is active for the 1.6.0 wire form (no post-root output, no missing required keys at temperature 0).
- **AC-IQ-A1** `JSONSchemaValidator` accepts a fixture response with a complete `quality_assessment` and rejects: a missing `quality_assessment` (1.6.0 only), an unknown criterion key, a level outside the enum, 3 concerns, a 161-char note, and a note containing `\n`.
- **AC-IQ-A2** `PromptSchemaTests` version/hash/field assertions updated; existing 1.5.0 fixtures still pass against 1.5.0 (both versions stay tested).
- **AC-IQ-A3** Golden sidecar and `model-responses` fixtures updated only where the new contract is exercised; legacy fixtures remain valid for the legacy versions they record.

### Stream B — combined analyze integration (issue #36 → IQ-M1)

- **FR-IQ-010** New boolean configuration `quality_assessment` (default `false`): CLI `--assess-quality` on `analyze` (and on `write-xmp`'s analyze-and-write shape), env `AISIDECAR_QUALITY_ASSESSMENT`, config key `quality_assessment`, standard precedence (invariant 9). Full five-touch-point `AppConfig` wiring plus `aisidecar.config.example.jsonc`.
- **FR-IQ-011** When enabled, `AnalyzePipeline` selects the 1.6.0 prompt+schema for both roles via the task profile; everything else (rendering, isolation, retries, repair, sidecar writing) is unchanged. When disabled, behavior is bit-for-bit today's.
- **FR-IQ-012** Provenance: `ResolvedRunConfiguration` gains `task_profile` (recorded in every sidecar's `run_configuration`); old sidecars without the key decode to `tagging` via the `decodeIfPresent … ?? builtInDefaults` pattern.
- **FR-IQ-013** The repair path works unchanged: a truncated 1.6.0 response repairs under the 1.6.0 wire schema (mock-runner test with a truncated fixture).
- **AC-IQ-B1** `analyze --assess-quality` on a mock runner writes sidecars whose model runs record `prompt_version …/1.6.0`, `response_schema_version …:1.6.0`, and contain `parsed_response_json.quality_assessment`; without the flag, 1.5.0 versions and no quality object.
- **AC-IQ-B2** `NoXMPRegressionTests` extended: a quality-enabled analyze run creates/modifies no `.xmp` (invariant 1).
- **AC-IQ-B3** Config precedence test: file `true` + env `false` + flag absent → disabled; flag present → enabled regardless.

### Stream C — quality-only pipeline (issue #37 → IQ-M2)

- **FR-IQ-020** New subcommand `aisidecar assess-quality <input-path>` (one new CLI file; Core logic in a thin `QualityAssessPipeline` that delegates to `AnalyzePipeline` configured with `task_profile = quality_only`). Supports the shared analyze options that make sense (`--mode`, `--recursive`, `--dry-run`, `--existing`, `--output-dir`, model/runtime options); never touches XMP.
- **FR-IQ-021** Quality-only runs write to a **separate sidecar**: `<image>.<ext>.quality.ai.json`, same `ai-sidecar-json/1.3` container. Rationale: a raw sidecar carries exactly one `run_configuration`; merging model runs from different invocations into one file would break the 1:1 run-provenance model. Naming lives beside the existing suffix constants in `Sidecars/SidecarNaming.swift`; `cleanup` recognizes the new suffix as owned; `--existing` policies apply to quality sidecars independently of tagging sidecars.
- **FR-IQ-022** Batch artifacts: new `ArtifactNames` prefixes (`quality-progress-`, `quality-summary-`) and a summary schema id (`ai-sidecar-quality-summary/1.0` or reuse of `BatchSummary` with its existing id — decide at implementation by whichever keeps `BatchSummary.derive` reusable; record the choice in the code comment).
- **FR-IQ-023** `RawJSONSidecarInputResolver` (and the Phase-2 input batch machinery) can resolve quality sidecars alongside tagging sidecars for the same image, so grading (Stream D) sees both.
- **AC-IQ-C1** `assess-quality` on a fixture folder (mock runner) produces `.quality.ai.json` files with quality-only prompt/schema versions, valid against the standalone schema; `analyze` afterwards still writes its own `.ai.json` untouched, and vice versa.
- **AC-IQ-C2** `assess-quality --dry-run` writes nothing and reports planned work; interruption mid-batch follows the existing fail-closed interruption contract.
- **AC-IQ-C3** `cleanup` removes `.quality.ai.json` files it owns and nothing else new.

### Stream D — grading algorithm (issue #38 → IQ-M3)

- **FR-IQ-030** `QualityAssessmentRecord`: typed, role-tagged decode of `quality_assessment` from `parsed_response_json` (combined) or a quality sidecar (quality-only), tolerant of unknown criterion keys (ignored, warned) for forward compatibility.
- **FR-IQ-031** `QualityTierDeriver`: deterministic tier derivation per §5.5's rule table from up to two records (whole + subject) per asset. Same inputs → same tier, always; no floating point, no randomness.
- **FR-IQ-032** `QualityGradingPolicy` (Codable, user-configurable): minimum confidence gate, per-tier rating map, per-tier label map, keyword root, per-criterion problem-keyword toggle, reject-as-minus-one toggle, and channel enables (rating/label/keywords independently). Defaults per §5.5.3.
- **FR-IQ-033** Grading runs at plan/write time only (inside the Phase-2 flow), is model-free, and is replayable: re-running with a different policy over unchanged sidecars yields a change plan that reflects only the policy delta.
- **FR-IQ-034** Every graded asset gets a `QualityGradingExplanation` (tier, rule hits, counts, source runs) recorded in the change plan and export report; assets below the confidence gate or with `overall == unrated` are explicitly reported as ungraded, never silently skipped.
- **AC-IQ-D1** A golden table test pins the tier for every meaningful combination of (overall level × strong count × problem count × confidence × subject-focus veto) — the rule table in §5.5.2 rendered as test cases.
- **AC-IQ-D2** Policy round-trips through JSON config; an invalid policy (unknown tier key, rating outside −1…5, empty label) fails resolution with `SidecarError.configInvalid`.
- **AC-IQ-D3** Given fixtures with whole-only, subject-only, both, and conflicting assessments, the deriver's precedence and veto behavior match §5.5.2 exactly.

### Stream E — XMP managed scalars + export integration (issue #39 → IQ-M4)

- **FR-IQ-040** New managed scalar support in the owned engine: `xmp:Rating` and `xmp:Label` (namespace `http://ns.adobe.com/xap/1.0/`, prefix `xmp`) and `photoshop:Urgency` (namespace `http://ns.adobe.com/photoshop/1.0/`, prefix `photoshop`; integer 1–8 serialized as text, written only alongside a label — its sole purpose is Capture One label reading), modeled by a new `XMPManagedScalar` enum parallel to (not shoehorned into) the bag-shaped `XMPManagedField`. Parser reads **both** storage forms (attribute on `rdf:Description`, or child element); writer updates in place preserving the existing form, and uses attribute form for new writes (the form LR/C1 emit). Multiple conflicting occurrences across descriptions → fail closed (`xmpUnsupportedRDF`), consistent with the engine's narrow posture.
- **FR-IQ-041** `XMPUnmanagedContentFingerprint` excludes managed scalars; `algorithmVersion` bumps to `xmp-unmanaged-content-fingerprint/2.0` (comparisons are within-run, so the bump is safe). `XMPMergeValidator` gains scalar expectation checks (planned value present post-write) and scalar preservation checks (unplanned scalars unchanged pre→post).
- **FR-IQ-042** `XMPChangePlan`/`XMPWriteRequest`/`XMPWritePreview`/`XMPWriteResult`/`XMPExportProgressRecord`/`XMPExportReport` gain additive scalar fields carrying old→new values and per-scalar action (`write`/`skip_existing`/`overwrite`). Change-plan and export-report schema ids bump `1.0` → `1.1` (additive minor; update `testSchemaIdentifierConstantsAreStable` deliberately).
- **FR-IQ-043** Conflict policy for scalars, independent of the keyword conflict policy, with three modes: `preserve` (default — write only when the property is absent or equal), `refresh` (like `preserve`, plus overwrite a value that exactly matches what a previous run's `xmp_export` stamp recorded as written by us — i.e., re-grade our own unchanged writes; a value changed by the user or another app is skipped and reported; a missing stamp degrades to `preserve` behavior), and `overwrite` (always, opt-in per run). Every skipped conflicting write is reported with both values. Dry-run shows all of this before anything is written (GUI change-plan sheet inherits it for free).
- **FR-IQ-044** All invariant-4 guarantees hold unchanged for scalar writes: deterministic backups, source-image SHA-256 pre/post checks, post-write readable validation, restore-on-validation-failure. The `xmp_export` stamp in contributing raw sidecars additionally records the written rating/label/urgency values and the derived tier (this stamp is what powers `refresh`).
- **FR-IQ-045** Quality keywords route through the **existing** keyword machinery (`PlannedKeyword` → merger → `dc:subject`/`lr:hierarchicalSubject`), pass `KeywordSafetyPolicy`, and are deterministic policy outputs (never model candidates, never normalization inputs). Root defaults to `AI Quality`.
- **FR-IQ-046** `write-xmp` grows a quality-grading surface: `--quality-grading` master switch (default off — the command is keywords-only by default, unchanged), `--write-rating/--no-write-rating`, `--write-label/--no-write-label`, `--write-quality-keywords/--no-write-quality-keywords`, `--write-urgency/--no-write-urgency`, `--quality-conflicts <preserve|refresh|overwrite>`, `--quality-min-confidence <high|medium|low>`; matching `AISIDECAR_XMP_QUALITY_*` env keys and `xmp_quality_*` config keys; tier maps configurable via config file only (structured values don't belong on flags).
- **AC-IQ-E1** New-file write: rating 4 + label `Green` + `AI Quality|good` keywords produce an XMP read back by the engine's own snapshot with those values, keyword bags intact, and a stable unmanaged fingerprint for untouched content.
- **AC-IQ-E2** Merge into a foreign XMP carrying `crs:*` develop settings, an existing user rating, and unknown namespaces: with `preserve`, the user rating survives, the skip is reported, label/keywords merge, and every unmanaged byte of content is semantically preserved (fingerprint gate green).
- **AC-IQ-E3** With `overwrite`, the plan shows `3 → 2` before the write and the report shows it after; backup exists; a forced validation failure restores the original file.
- **AC-IQ-E4** Attribute-form and element-form fixtures both round-trip; mixed/conflicting occurrences fail closed without writing.
- **AC-IQ-E5** `NoXMPRegressionTests` still proves `analyze`/`assess-quality` paths write no XMP.
- **AC-IQ-E6** `refresh` matrix: value matches our stamp → overwritten with the new grade; value differs from our stamp → skipped and reported; no stamp → behaves as `preserve`; stamp present but property absent → written.
- **AC-IQ-E7** A label-bearing grade writes `photoshop:Urgency` per the captured map alongside `xmp:Label` (attribute/element forms and fail-closed conflicts covered like the other scalars); tiers without a label mapping write no urgency.

### Cross-cutting

- **FR-IQ-050** All new tests deterministic and offline (invariant 12); mock/recorded runners only.
- **FR-IQ-051** Documentation updated in the same milestone as the behavior: `AGENTS.md` index (this doc), `architecture-map.md` (new types/artifacts), `prompt-and-schema-design.md` (v1.6.0 + quality-only contract notes), `cli-implementation-notes.md` (new subcommand + flags), `aisidecar.config.example.jsonc`.
- **FR-IQ-052** Before any default flips on (quality in analyze, or any channel in write-xmp), IQ-M5's live evidence exists: real-model token/latency measurements and LR Classic + Capture One read-back verification recorded under `agent_docs/release-evidence/`.
- **FR-IQ-060** (outline, not in milestone 1's issues) GUI: Settings/Step-3 toggle for `--assess-quality`; Review shows per-asset assessment read-only; Export change-plan sheet shows rating/label rows (inherited from FR-IQ-043's plan data). Scoped in IQ-M6 when GUI work is scheduled.

---

## 5. Design

### 5.1 Contract versioning and file inventory (IQ-M0)

New resource files (all under `Sources/AISidecarCore/Resources/ModelRuntime/`, auto-bundled by the existing `.process("Resources")` declaration):

```
Prompts/whole_image_v1.6.0.txt              PROMPT_VERSION: aisidecar.prompt.whole_image/1.6.0
Prompts/subject_isolated_v1.6.0.txt         PROMPT_VERSION: aisidecar.prompt.subject_isolated/1.6.0
Prompts/whole_image_quality_v1.0.0.txt      PROMPT_VERSION: aisidecar.prompt.whole_image_quality/1.0.0
Prompts/subject_isolated_quality_v1.0.0.txt PROMPT_VERSION: aisidecar.prompt.subject_isolated_quality/1.0.0
Schemas/whole_image_v1.6.0.json             $id: urn:aisidecar:response:whole-image:1.6.0
Schemas/subject_isolated_v1.6.0.json        $id: urn:aisidecar:response:subject-isolated:1.6.0
Schemas/whole_image_quality_v1.0.0.json     $id: urn:aisidecar:response:whole-image-quality:1.0.0
Schemas/subject_isolated_quality_v1.0.0.json $id: urn:aisidecar:response:subject-isolated-quality:1.0.0
```

The 1.6.0 schema content = the 1.5.0 file + the addendum's `quality_assessment` property (verbatim), `quality_assessment` appended to `required`, and `quality_level`/`quality_note` appended to `$defs`. The standalone quality schema (whole-image shown; subject-isolated differs only in `$id`, `title`, and using the subject addendum's property set):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "urn:aisidecar:response:whole-image-quality:1.0.0",
  "title": "AISidecar Whole Image Quality-Only Model Response 1.0.0",
  "type": "object",
  "additionalProperties": false,
  "required": ["quality_assessment"],
  "properties": {
    "quality_assessment": { /* verbatim from the whole-image addendum */ }
  },
  "$defs": {
    "confidence": {
      "type": "string",
      "enum": ["high", "medium", "low"],
      "description": "Ordinal confidence band. Numeric confidence is intentionally not used."
    },
    "quality_level": { /* verbatim from the addendum */ },
    "quality_note": { /* verbatim from the addendum */ }
  }
}
```

### 5.2 Task-profile selection

#### 5.2.1 The new enum

`ModelInputRole` stays exactly two cases — it names the *rendered input* (whole frame vs subject crop), which is unchanged. What varies is the *task* asked of the model:

```swift
// Sources/AISidecarCore/ModelRuntime/ModelRuntimeTypes.swift (additive)
/// What the model is asked to do with a rendered input. Selects the
/// prompt/schema pair per role; recorded in run_configuration provenance.
public enum ModelTaskProfile: String, Codable, Sendable, CaseIterable {
    case tagging = "tagging"                        // v1.5.0 contract (today's behavior)
    case taggingWithQuality = "tagging_with_quality" // v1.6.0 contract (issue #36)
    case qualityOnly = "quality_only"               // quality-only v1.0.0 contract (issue #37)
}
```

Raw strings are load-bearing (invariant 7): additive, never renamed.

#### 5.2.2 Registry changes

```swift
// PromptRegistry.swift — resourceName becomes task-aware; ResponseSchemas mirrors it.
static func resourceName(for role: ModelInputRole, task: ModelTaskProfile) -> String {
    switch (role, task) {
    case (.wholeImage, .tagging):                 return "whole_image_v1.5.0"
    case (.wholeImage, .taggingWithQuality):      return "whole_image_v1.6.0"
    case (.wholeImage, .qualityOnly):             return "whole_image_quality_v1.0.0"
    case (.subjectIsolated, .tagging):            return "subject_isolated_v1.5.0"
    case (.subjectIsolated, .taggingWithQuality): return "subject_isolated_v1.6.0"
    case (.subjectIsolated, .qualityOnly):        return "subject_isolated_quality_v1.0.0"
    }
}
```

`AnalyzePipeline.runModel` (currently `AnalyzePipeline.swift:786–787`) passes `configuration.taskProfile` through. Keeping `.tagging` pointed at 1.5.0 preserves FR-IQ-004's byte-identical guarantee; whether `.tagging` later advances to a hypothetical 1.6.x is a normal version-bump decision, out of scope here.

#### 5.2.3 Quality-only prompt text (whole-image; subject variant differs as the addendum does)

```
PROMPT_VERSION: aisidecar.prompt.whole_image_quality/1.0.0

Assess the perceptual quality of the complete photograph and return exactly one
JSON object matching the supplied JSON Schema.

OUTPUT RULES

Return only the JSON object: no Markdown, no code fences, no comments, no fields
beyond the schema. Complete every required field of quality_assessment.

QUALITY RULES

Use only visible image evidence. Do not use GPS, EXIF, filename, location, or
other external context. Do not estimate numeric sharpness, clipping, noise,
color accuracy, resolution, capture settings, or edit history. Rate focus, fine
detail, and artifacts only when visible at the supplied resolution; otherwise
use unrated.

QUALITY LEVELS

- problem: a clear visible weakness that reduces effectiveness.
- acceptable: adequate or neutral; not a notable strength.
- strong: clearly contributes to the photograph.
- unrated: not relevant or not reliably judgeable.

Do not use strong merely because no problem is visible. Judge intentional
choices by their visible effect; do not mark blur, darkness, grain, shallow
depth of field, or unusual color as problems merely because they are
unconventional.

Assess composition and subject-background relationship from the complete frame.
Use unrated for subject_background_relationship when no distinct subject
exists. Use unrated for moment_or_expression when timing, gesture, behavior, or
expression is not relevant. technical_cleanliness covers only obvious visible
artifacts.

overall_effectiveness is a separate holistic judgment, not an average.
strengths and concerns contain at most two short visible observations each,
must agree with the ratings, and use [] when none are clear. Do not give
editing instructions. confidence is confidence in the assessment, not a
quality score.

Return only the JSON object.
```

(~230 words — well under the ~700-word base-prompt budget; quality-only calls are the cheap path.)

GPS-context injection is **suppressed** for `.qualityOnly` runs: assessments must not use external context (the addendum's own rule), so the `MODEL INPUT CONTEXT` block would be dead weight at best and a contamination vector at worst. Combined-mode runs keep the block (tagging still uses it; the quality section instructs the model not to). Add a regression test beside the existing no-GPS prompt tests.

### 5.3 Configuration plumbing (IQ-M1)

Follow the `recursive` template end-to-end. Touch points, in dependency order:

1. `RunConfiguration.swift`: `RunConfigurationOverrides.qualityAssessment: Bool?`; `ResolvedRunConfiguration.taskProfile: ModelTaskProfile` (coding key `task_profile`, built-in default `.tagging`, `decodeIfPresent … ?? builtInDefaults.taskProfile`).
2. `AppConfig.swift`: `qualityAssessment: Bool?` + coding key `quality_assessment` + init/decode/encode (five spots; unknown-key rejection means every raw-JSON config test must be checked).
3. `ConfigurationResolver.swift`: env `AISIDECAR_QUALITY_ASSESSMENT` in `environmentOverrides`; `ConfigurationBuilder` field + `apply(config:)`/`apply(overrides:)`; `resolved()` maps the boolean to `taskProfile = qualityAssessment ? .taggingWithQuality : .tagging` (the boolean is the user surface; the profile is the provenance value). `withoutConfigPath()` updated.
4. `SharedOptions.swift`: `@Flag(help: "Also produce a perceptual quality assessment per image (adds the quality_assessment block to raw sidecars).") var assessQuality = false`; `overrides` maps `assessQuality ? true : nil`.
5. `aisidecar.config.example.jsonc`: documented key.

The `assess-quality` subcommand (IQ-M2) sets `taskProfile = .qualityOnly` directly on its resolved configuration rather than via the boolean.

Note for implementers: `taskProfile` lands inside `run_configuration` in every sidecar, which feeds provenance-dimension ideas later (roadmap F3) for free.

### 5.4 Quality extraction (IQ-M3)

New file `Sources/AISidecarCore/Metadata/QualityAssessmentExtractor.swift`:

```swift
/// One decoded quality_assessment block, tagged with where it came from.
public struct QualityAssessmentRecord: Sendable, Equatable {
    public enum Criterion: String, CaseIterable, Sendable {
        case focus, composition
        case exposureAndTone = "exposure_and_tone"
        case lightingAndColor = "lighting_and_color"
        case detailAndTexture = "detail_and_texture"
        case subjectBackgroundRelationship = "subject_background_relationship"
        case momentOrExpression = "moment_or_expression"
        case poseExpressionOrMoment = "pose_expression_or_moment"
        case technicalCleanliness = "technical_cleanliness"
    }
    public enum Level: String, Sendable { case problem, acceptable, strong, unrated }
    public enum Confidence: String, Comparable, Sendable {
        case low, medium, high
        public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
        private var rank: Int { self == .low ? 0 : self == .medium ? 1 : 2 }
    }

    public let role: ModelInputRole
    public let promptVersion: String
    public let criteria: [Criterion: Level]   // unknown keys dropped with a warning issue
    public let overall: Level                  // overall_effectiveness / overall_subject_quality
    public let strengths: [String]
    public let concerns: [String]
    public let confidence: Confidence
}

public struct QualityExtractionResult: Sendable {
    public let sourceImagePath: String
    public let records: [QualityAssessmentRecord]  // 0–2 per source (whole/subject), newest run wins per role
    public let issues: [QualityExtractionIssue]    // malformed block, unknown criterion, missing overall …
}

public enum QualityAssessmentExtractor {
    /// Walks model_runs of a tagging sidecar and (if resolved) its sibling
    /// .quality.ai.json, reading parsed_response_json.quality_assessment.
    /// Malformed blocks produce issues, never fatals — mirrors CandidateExtractor's posture.
    public static func extract(from inputs: ResolvedRawSidecarInput...) -> QualityExtractionResult
}
```

Decoding notes: `overall_effectiveness` (whole) and `overall_subject_quality` (subject) both land in `overall`; the two role-specific criterion spellings (`moment_or_expression` vs `pose_expression_or_moment`) are kept distinct in `Criterion` so explanations can echo the model's actual field. A record with `overall` missing or unparseable is dropped with an issue. `CandidateExtractor` is not modified (it already ignores unknown keys — add the regression test pinning that).

### 5.5 Grading: tier derivation and policy (IQ-M3)

#### 5.5.1 Types

```swift
// Sources/AISidecarCore/Metadata/QualityGrading.swift
public enum QualityTier: String, Codable, CaseIterable, Sendable, Comparable {
    case reject, belowAverage = "below_average", neutral, good, excellent
    // Comparable by declaration order (reject < … < excellent)
}

public struct QualityGradingPolicy: Codable, Sendable, Equatable {
    public var minimumConfidence: QualityAssessmentRecord.Confidence = .medium
    public var writeRating = true
    public var writeLabel = true
    public var writeUrgency = true                 // photoshop:Urgency companion for C1 label reading;
                                                   // only emitted for tiers that also produce a label
    public var writeKeywords = true
    public var rejectAsMinusOne = false            // xmp:Rating = -1 instead of the map value
    public var perCriterionProblemKeywords = false // adds e.g. "AI Quality|problems|focus"
    public var keywordRoot = "AI Quality"
    public var ratingMap: [QualityTier: Int] = [
        .reject: 1, .belowAverage: 2, .neutral: 3, .good: 4, .excellent: 5,
    ]
    public var labelMap: [QualityTier: String] = [
        .reject: "Red", .excellent: "Green",       // other tiers: no label by default
    ]
    /// Values 1–8. Built-in defaults are set from the IQ-M4 prework capture
    /// (Capture One's own label→Urgency numbers); empty means "never write".
    public var urgencyMap: [QualityTier: Int] = [:]
    public static let builtInDefaults = QualityGradingPolicy()
}

public struct QualityGrade: Sendable, Equatable {
    public let tier: QualityTier
    public let rating: Int?          // nil = channel off or no map entry
    public let label: String?
    public let urgency: Int?         // photoshop:Urgency companion to label (C1 label reading)
    public let keywords: [String]    // hierarchical paths ("AI Quality|good"); the planner
                                     // derives the flat dc:subject form by space-joining components
    public let explanation: [String] // ordered human-readable rule hits
}
```

#### 5.5.2 Tier derivation — the rule table

Deterministic, integer-only, and small enough to hold in your head. Inputs per asset: `whole` and/or `subject` records. The **primary** record is `whole` when present, else `subject` (whole-frame judgment carries composition and subject-background information the subject crop deliberately lacks).

Counting: over the primary record's criteria excluding `overall`, `strongCount` = criteria at `strong`, `problemCount` = criteria at `problem` (`unrated` counts as nothing).

| # | Rule (first match wins within its step) | Result |
|---|---|---|
| 1 | No records at all | not graded (asset reported ungraded) |
| 2 | `primary.confidence < policy.minimumConfidence` | not graded (reported with reason) |
| 3 | `primary.overall == unrated` | not graded (reported with reason) |
| 4 | `overall == problem` and (`focus == problem` or `problemCount >= 3`) | `reject` |
| 5 | `overall == problem` | `below_average` |
| 6 | `overall == acceptable` and `problemCount == 0` and `strongCount >= 2` | `good` |
| 7 | `overall == acceptable` | `neutral` |
| 8 | `overall == strong` and `problemCount == 0` and `strongCount >= 3` and `confidence == high` | `excellent` |
| 9 | `overall == strong` | `good` |
| — | **Subject veto** (applied after 4–9, only when both records exist): `subject.criteria[.focus] == .problem` and tier > `below_average` | demote one tier, append explanation `"subject focus veto: demoted from <tier>"` |

Design rationale: `excellent` is deliberately hard to reach (the prompt already forbids `strong` for "merely no problem", and rule 8 stacks confidence on top) so 5-star inflation doesn't erode trust in the ratings; `reject` requires the overall judgment *plus* corroboration (bad focus or pervasive problems) so one harsh criterion can't tank a keeper. Every threshold lives in one function so a future policy knob can expose them; V1 exposes only the maps and gates in 5.5.1 to keep the config surface honest.

#### 5.5.3 Channel derivation

```swift
public enum QualityTierDeriver {
    public static func grade(
        whole: QualityAssessmentRecord?,
        subject: QualityAssessmentRecord?,
        policy: QualityGradingPolicy
    ) -> QualityGrade? {
        guard let primary = whole ?? subject else { return nil }
        guard primary.confidence >= policy.minimumConfidence, primary.overall != .unrated else {
            return nil  // caller reports the reason from the record
        }
        var explanation: [String] = []
        var tier = baseTier(for: primary, explaining: &explanation)         // rules 4–9
        if whole != nil, let s = subject, s.criteria[.focus] == .problem, tier > .belowAverage {
            tier = tier.demoted()
            explanation.append("subject focus veto: demoted to \(tier.rawValue)")
        }
        let rating: Int? = policy.writeRating
            ? (tier == .reject && policy.rejectAsMinusOne ? -1 : policy.ratingMap[tier])
            : nil
        let label = policy.writeLabel ? policy.labelMap[tier] : nil
        let urgency: Int? = (policy.writeUrgency && label != nil) ? policy.urgencyMap[tier] : nil
        var keywords: [String] = []
        if policy.writeKeywords {
            keywords.append("\(policy.keywordRoot)|\(tier.rawValue)")
            if policy.perCriterionProblemKeywords {
                for (criterion, level) in primary.criteria.sorted(by: { $0.key.rawValue < $1.key.rawValue })
                where level == .problem {
                    keywords.append("\(policy.keywordRoot)|problems|\(criterion.rawValue)")
                }
            }
        }
        return QualityGrade(tier: tier, rating: rating, label: label, urgency: urgency,
                            keywords: keywords, explanation: explanation)
    }
}
```

Keyword terms are deterministic and pass through `KeywordSafetyPolicy` like everything else on the way to XMP (they trivially pass; the call is there so no route around the gate exists — invariant 3's "every route" rule).

Quality keywords are written to **both** managed bags, like every keyword the engine writes, governed by the existing `writeFlatKeywords`/`writeHierarchicalKeywords` toggles:

- `lr:hierarchicalSubject` gets the full `|`-separated path (`AI Quality|good`, `AI Quality|problems|focus`) — Lightroom and Capture One render it as a keyword tree, filterable at the parent or leaf.
- `dc:subject` gets a **self-describing space-joined form** (`AI Quality good`, `AI Quality problems focus`), derived by the planner from the path components. This deliberately departs from Lightroom's leaf-only flat convention: bare leaves (`good`, `reject`) are too generic and would collide with real content keywords in flat-only readers and keyword-text search, and a pipe-containing flat entry would be misread by apps that don't parse `|` in `dc:subject`.

Note these are the first genuinely multi-level keywords the pipeline writes (all existing keywords are single-level, identical in both bags per FR2-007a), so the flat-form derivation above is a new explicit planner rule, not inherited behavior.

### 5.6 XMP managed scalars (IQ-M4)

#### 5.6.1 The scalar model

Do **not** widen `XMPManagedField` (its contract is bag-of-`rdf:li`; every consumer iterates it assuming bags). Add a parallel enum with its own narrow contract:

```swift
// Metadata/XMPXMLSupport.swift (additive)
enum XMPNamespace {
    // existing: x, rdf, dc, lr
    static let xmp = "http://ns.adobe.com/xap/1.0/"
    static let photoshop = "http://ns.adobe.com/photoshop/1.0/"
}

/// Managed single-value XMP properties. Unlike XMPManagedField (keyword bags),
/// a scalar is one literal stored either as an attribute of rdf:Description
/// or as a simple child element. Reading accepts both forms; updates preserve
/// the form found; new writes use the attribute form (what LR/C1 emit).
enum XMPManagedScalar: CaseIterable {
    case rating    // xmp:Rating — "-1" | "0"..."5"
    case label     // xmp:Label — free text, app-matched
    case urgency   // photoshop:Urgency — "1"..."8", C1 label-read companion

    var namespaceURI: String {
        switch self {
        case .rating, .label: return XMPNamespace.xmp
        case .urgency: return XMPNamespace.photoshop
        }
    }
    var preferredPrefix: String {
        switch self {
        case .rating, .label: return "xmp"
        case .urgency: return "photoshop"
        }
    }
    var localName: String {
        switch self {
        case .rating: return "Rating"
        case .label: return "Label"
        case .urgency: return "Urgency"
        }
    }
}
```

New file `Metadata/XMPScalarReader.swift` / extension of the merger:

```swift
enum XMPScalarValueForm { case attribute, element }

struct XMPScalarOccurrence {
    let scalar: XMPManagedScalar
    let value: String
    let form: XMPScalarValueForm
}

enum XMPScalarReader {
    /// Returns the single occurrence of the scalar, nil when absent.
    /// Throws .xmpUnsupportedRDF when the scalar appears more than once
    /// (across attributes/elements/descriptions) with differing values —
    /// the narrow-engine fail-closed posture.
    static func read(_ scalar: XMPManagedScalar, in document: XMLDocument) throws -> XMPScalarOccurrence?
}

extension XMPKeywordMerger {   // or a sibling XMPScalarMerger, implementer's choice
    /// Sets the scalar on the writable rdf:Description. Updates in place
    /// preserving the existing form; creates an attribute when absent.
    /// Declares xmlns:xmp on rdf:RDF if not present.
    func setScalar(_ scalar: XMPManagedScalar, to value: String, in document: XMLDocument) throws
}
```

Rating values are validated at plan time (integer −1…5, serialized without sign for 0…5); the engine writes strings and never interprets foreign values beyond equality comparison.

#### 5.6.2 Fingerprint and validation

- `XMPUnmanagedContentFingerprint.appendEntries`: skip elements/attributes matching any `XMPManagedScalar` (same shape as the existing `isManagedProperty`/`isManagedAttribute` filters); bump `algorithmVersion` to `"xmp-unmanaged-content-fingerprint/2.0"`.
- `XMPMetadataSnapshot` gains `rating: String?` and `label: String?` (additive; snapshot is in-memory + report-serialized only).
- `XMPMergeValidator`: for each scalar — if the plan wrote it, assert the post-write value equals the planned value; if the plan didn't touch it, assert pre == post. Unmanaged gate logic unchanged otherwise.
- Consequence to embrace in tests: fixtures that treated `xmp:Rating` as unmanaged-fingerprint content (`XMPOwnedEngineTests` `testParserAcceptsMissingManagedBags` et al.) now see it excluded — update assertions to the new managed expectations rather than deleting them.

#### 5.6.3 Plan/engine/report surface

`XMPChangePlan` additions (additive Codable fields, snake_case keys):

```swift
public struct PlannedScalarWrite: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable { case write, skipExisting = "skip_existing", overwrite }
    public let field: String          // "xmp:Rating" | "xmp:Label" | "photoshop:Urgency"
    public let plannedValue: String
    public let existingValue: String?
    public let action: Action
}
// on XMPChangePlan:
public var ratingWrite: PlannedScalarWrite?
public var labelWrite: PlannedScalarWrite?
public var urgencyWrite: PlannedScalarWrite?
public var qualityExplanation: [String]?   // from QualityGrade.explanation
```

`XMPWritePreview`/`XMPWriteResult` gain `rating`/`label` before/after values; `XMPExportProgressRecord` gains `wroteRating`/`wroteLabel`; `XMPExportReport` target entries surface the `PlannedScalarWrite`s and skips. Change-plan/report schema ids: `ai-sidecar-xmp-change-plan/1.1`, `ai-sidecar-xmp-export/1.1`.

`OwnedXMPSidecarEngine.apply` ordering: read snapshot → merge keywords (existing) → apply scalar writes per plan action → the existing "skip write when nothing changed" check now also considers scalars → atomic write + readable validation, unchanged.

The `xmp_export` stamp (`RawSidecarExportStamp`) additionally records `{ "rating": "4", "label": "Green", "quality_tier": "good" }` — this both documents what the tool did and enables a future `refresh-ours-only` overwrite mode (§9 D-3) without new plumbing.

#### 5.6.4 Where grading hooks into the export pipeline

`XMPExportConfiguration` gains a nested resolved block (own builder, same precedence discipline as the rest of Phase 2 config):

```swift
public struct ResolvedQualityGradingConfiguration: Codable, Sendable, Equatable {
    public var enabled: Bool                 // --quality-grading, default false
    public var conflictPolicy: ScalarConflictPolicy  // preserve | refresh | overwrite, default preserve
    public var policy: QualityGradingPolicy  // maps/gates, config-file-configurable
}
```

`XMPChangePlanner.plan(...)` — when grading is enabled — additionally calls `QualityAssessmentExtractor` + `QualityTierDeriver` per target, resolves conflicts against the pre-read snapshot (`preserve`: absent-or-equal → `write`/`skipExisting`; `refresh`: as `preserve`, plus `overwrite` when the existing value exactly equals the value recorded in the newest `xmp_export` stamp among the contributing sidecars — a value changed by the user or another app is skipped and reported, and a missing stamp degrades to `preserve`; `overwrite`: always, with the old value recorded), merges quality keywords into the planned keyword lists, and attaches the explanation. Everything downstream (dry-run document, GUI change-plan sheet, reports) inherits the new data because it lives on the plan.

`write-xmp --from-json` thus covers combined-mode sidecars out of the box; FR-IQ-023's resolver work makes it also see `.quality.ai.json` siblings. A composed `assess-quality → write-xmp` single command is deliberately **not** in scope (the two-command flow matches the analyze/write-xmp separation users already know); if demanded later, `AnalyzeAndXMPPipeline` is the template.

### 5.7 CLI surface summary

| Command | New surface |
|---|---|
| `analyze` | `--assess-quality` (combined mode) |
| `assess-quality <input>` | new subcommand: `--mode whole\|subject\|both`, `--recursive`, `--dry-run`, `--existing skip\|overwrite\|fail`, `--output-dir`, shared model/runtime options |
| `write-xmp` | `--quality-grading`, `--write-rating/--no-write-rating`, `--write-label/--no-write-label`, `--write-urgency/--no-write-urgency`, `--write-quality-keywords/--no-write-quality-keywords`, `--quality-conflicts preserve\|refresh\|overwrite`, `--quality-min-confidence high\|medium\|low` |
| `cleanup` | recognizes `.quality.ai.json` + new batch-artifact prefixes (no new flags) |

Example subcommand skeleton (follows `AnalyzeCommand` conventions exactly):

```swift
// Sources/AISidecarCLI/AssessQualityCommand.swift
struct AssessQualityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assess-quality",
        abstract: "Run the vision model in quality-assessment-only mode, writing .quality.ai.json sidecars.",
        discussion: BatchExitHelp.discussion
    )
    @Argument(help: "Folder or single image to assess.") var inputPath: String
    @OptionGroup var shared: SharedOptions

    mutating func run() async throws {
        var resolved = try ConfigurationResolver.resolve(cli: shared.overrides)
        resolved = resolved.with(taskProfile: .qualityOnly)   // small additive helper
        let logger = Logger.standard()
        let monitor = InterruptionMonitor(); monitor.installSignalHandlers()
        let result = try await withBatchInterruptionExit(monitor: monitor) {
            try await QualityAssessPipeline(logger: logger).run(
                inputPath: inputPath, configuration: resolved, interruptionMonitor: monitor)
        }
        try enforceBatchExitPolicy(failureCount: result.failureCount, interrupted: result.interrupted)
    }
}
```

### 5.8 Reporting and artifact identifiers

Additions to `Reporting/ArtifactNames.swift`: `qualityProgressPrefix = "quality-progress-"`, `qualitySummaryPrefix = "quality-summary-"`. Sidecar suffix constant beside the existing one in `SidecarNaming`: `.quality.ai.json`. Schema ids: change plan and export report bump to `/1.1` (FR-IQ-042); quality-only batch summary reuses `BatchSummary` machinery (see FR-IQ-022 note). `cleanup` scans the new prefixes/suffix through the same constants — no drift possible.

---

## 6. Milestone plan

Every milestone: implement → `swift test` green → `Scripts/format.sh` → commit (code and doc updates split per repo practice). No milestone starts before the previous one's commit. Estimated sizes assume a Sonnet-level agent with this document open.

> **Staged execution:** each milestone is decomposed into small, individually committable stages in `agent_docs/13-image-quality-implementation-stages.md` (with per-stage specs, code skeletons, tests, review checklists, and a status ledger). Execute from doc 13; this section remains the scope/acceptance authority.

### IQ-M0 — Model contract (issues #30, #31) — size M

1. Author the four 1.6.0 files and four quality-only files per §5.1/§5.2.3 (content is fully specified between §3, §5.1, and the addendum attachments; the addendum JSON/text files themselves live in the issue attachments, not the repo).
2. Add `ModelTaskProfile`; make `PromptRegistry`/`ResponseSchemas` task-aware with `.tagging` defaulted so **no behavior changes yet** (registry callers pass `.tagging` explicitly this milestone).
3. Tests: extend `PromptSchemaTests` (versions/hashes for all six active files; quality fixtures valid; AC-IQ-A1 rejection matrix; no-GPS regression covers the new prompts), `ModelRuntimeTests` wire-schema assertions for the new schemas (FR-IQ-005), fixture additions under `Fixtures/model-responses/` (`whole_image_quality_valid.json`, a combined 1.6.0 response, a truncated-quality repair fixture).
4. Docs: `prompt-and-schema-design.md` gains a v1.6.0/quality-only section (version table + task-profile selection note).

Acceptance: AC-IQ-A1..A3. Commit boundary: "Model contract v1.6.0 + quality-only v1.0.0 (no pipeline wiring)".

### IQ-M1 — Combined analyze integration (issue #36) — size M

1. Config plumbing per §5.3 (all five `AppConfig` touch points, env, builder, resolved profile, flag).
2. `AnalyzePipeline` consumes `configuration.taskProfile` at the prompt/schema selection point; provenance lands in sidecars automatically via `ResolvedRunConfiguration`.
3. Tests: AC-IQ-B1 (mock-runner end-to-end both ways), AC-IQ-B2 (`NoXMPRegressionTests` extension), AC-IQ-B3 (`ConfigResolutionTests` matrix), FR-IQ-013 repair test, golden sidecar fixture update **only if** the golden run enables quality (recommended: add a second golden, keep the existing one on `.tagging` to pin FR-IQ-004's byte-identical claim).
4. Docs: `cli-implementation-notes.md`, `aisidecar.config.example.jsonc`, `architecture-map.md` (task profile row).

Acceptance: AC-IQ-B1..B3. Live probe (FR-IQ-005 second half) happens here against a local Ollama before merge; record the result in `benchmarks/`.

### IQ-M2 — Quality-only pipeline (issue #37) — size M

1. `SidecarNaming` quality suffix + planner support; `QualityAssessPipeline` thin wrapper; `AssessQualityCommand` + registration; `ArtifactNames` prefixes; `cleanup` coverage; `RawJSONSidecarInputResolver` quality-sibling resolution (FR-IQ-023).
2. Tests: AC-IQ-C1..C3 plus resolver tests (image with both sidecars, only quality, only tagging).
3. Docs: `architecture-map.md` pipeline table row, `cli-implementation-notes.md`.

Acceptance: AC-IQ-C1..C3.

### IQ-M3 — Extraction + grading (issue #38, Core only) — size M

1. `QualityAssessmentExtractor`, `QualityTierDeriver`, `QualityGradingPolicy` (+ config decode/validation into `SidecarError.configInvalid`).
2. Tests: AC-IQ-D1 golden rule-table (enumerate all rule rows × representative counts, including the veto and both ungraded reasons), AC-IQ-D2 policy round-trip/validation, AC-IQ-D3 precedence fixtures, extractor malformed-block issues, `CandidateExtractor` ignores `quality_assessment` regression.

Acceptance: AC-IQ-D1..D3. Nothing user-visible yet; pure Core commit.

### IQ-M4 — XMP managed scalars + write-xmp integration (issue #39) — size L

Order inside the milestone matters; keep each step green:

0. **Prework (no code, can happen any time earlier):** capture Capture One's label→`photoshop:Urgency` mapping empirically — in C1, apply each color tag to a test image with sidecar sync on Full Sync, then read the written `xmp:Label`/`photoshop:Urgency` values from the sidecars. Record the table in `agent_docs/release-evidence/` and use it as `urgencyMap`'s `builtInDefaults` (tiers map through their label color).
1. `XMPNamespace.xmp` + `.photoshop`, `XMPManagedScalar` (rating/label/urgency), `XMPScalarReader`, scalar merge (§5.6.1). Unit tests: both forms, round-trip, fail-closed conflicts (AC-IQ-E4, E7).
2. Fingerprint v2 + snapshot fields + `XMPMergeValidator` scalar checks (§5.6.2); update the affected `XMPOwnedEngineTests` fixtures deliberately.
3. Plan/preview/result/report/progress additive fields + schema-id bumps (§5.6.3); update `testSchemaIdentifierConstantsAreStable`.
4. `ResolvedQualityGradingConfiguration` + builder + `write-xmp` flags/env/config keys; planner hookup (§5.6.4) including quality keywords through `KeywordSafetyPolicy`; export-stamp extension.
5. End-to-end tests AC-IQ-E1..E3, E5, E6; dry-run change-plan snapshot test showing scalar rows; conflict-policy matrix (absent/equal/different/stamp-match/stamp-missing × preserve/refresh/overwrite).
6. Docs: `02-cli-xmp-sidecar-requirements-updated.md` addendum note (new managed fields under F12 rules), `architecture-map.md` Metadata row.

Acceptance: AC-IQ-E1..E7.

### IQ-M5 — Live verification and evidence — size S (manual)

1. Real-model benchmark on the TestingFileSet: token deltas (`runtime_metrics.eval_count` distribution for 1.6.0 vs 1.5.0 and quality-only), repair-rate check, spot-check assessment sanity. Record under `benchmarks/`.
2. Release-evidence run (pattern in `agent_docs/testing-and-verification.md`): write rating/label/urgency/keywords for a small set; verify in Lightroom Classic (rating filter, label filter, keyword filter; confirm label text matches the default label set; confirm the extra `photoshop:Urgency` doesn't perturb LR) and Capture One (rating; confirm color tags appear via the written urgency values; determine empirically whether the installed C1 version also reads `xmp:Label` — record the answer either way; keyword filter). Exercise a `refresh` re-grade end-to-end on real files. Record under `agent_docs/release-evidence/`.
3. Update §2.2's matrix and user-facing docs with verified facts; revisit §9 D-4 (Urgency) with data.

Acceptance: FR-IQ-052 satisfied; evidence files committed.

### IQ-M6 — GUI surface (outline; schedule with GUI work, not before) — size M

Settings/Step-3 checkbox bound to `quality_assessment` via the existing `ConfigFileEditor` write-through; Review step read-only assessment panel (levels + strengths/concerns from the sidecar); Export change-plan sheet renders the scalar rows it already receives from the plan. Formal FRs assigned when scheduled (FR-IQ-060 placeholder). Wizard-vs-Studio placement follows whatever M9 has established by then.

---

## 7. Test plan (consolidated)

| Layer | New/updated tests |
|---|---|
| Schema/prompt | `PromptSchemaTests`: six active version/hash assertions; quality fixture validity; rejection matrix (AC-IQ-A1); no-GPS regression over new prompts; wire-schema strip/inline assertions for all new schemas |
| Model runtime | Repair-under-1.6.0 test; recorded-fixture validity against new schemas |
| Pipeline | Analyze combined-mode end-to-end (mock runner) both toggle states; quality-only pipeline end-to-end; dry-run; interruption; existing-policy on quality sidecars; `NoXMPRegressionTests` extensions |
| Config | Precedence matrix for `quality_assessment` and all `xmp_quality_*` keys; invalid-policy rejection; example-config parse |
| Extraction/grading | Rule-table golden (every row of §5.5.2), veto, ungraded reasons, malformed blocks, unknown-criterion tolerance, `CandidateExtractor`-ignores-quality regression |
| XMP engine | Scalar read both forms; fail-closed conflict matrix; merge preserve/overwrite; fingerprint v2 exclusions; validator expectation/preservation; rollback-on-validation-failure with scalars; new-file write read-back |
| Reports/plans | Change-plan JSON snapshot with scalar rows + explanation; report/progress fields; schema-id stability test updated; summary rendering |
| Fixtures | `model-responses/` additions; second golden sidecar (quality-enabled); XMP fixtures for attribute-form/element-form/conflicting scalars |

All offline (invariant 12). The only non-CI verification is IQ-M5's live probe/bench/evidence, which is deliberately manual and recorded.

## 8. Live verification and release evidence

Covered by IQ-M5 (§6). The two claims that **must not** ship in user-facing docs without evidence: "Capture One picks up the color label from our sidecars" (historically false via `xmp:Label`; verify on the current version) and token/latency cost of enabling quality by default. Everything else (LR rating/label/keyword filters, C1 rating) is expected to verify cleanly but is recorded anyway per the release-evidence pattern.

## 9. Maintainer decisions

### 9.1 Resolved 2026-07-15 (maintainer)

| ID | Decision | Resolution |
|---|---|---|
| D-1 | Star map | **Full 1–5 map**, with stars derived from the weighted rule table in §5.5.2 (overall level adjusted by strong/problem counts and confidence). |
| D-2 | Reject representation | **Keyword + Red label**; `rejectAsMinusOne` stays available but off by default. |
| D-3 | `refresh` conflict mode | **In scope for IQ-M4** (FR-IQ-043): overwrite only values whose current content matches what our export stamp recorded; user/app-changed values are skipped and reported. Default mode remains `preserve` (see D-6 rationale). |
| D-4 | `photoshop:Urgency` | **In scope for IQ-M4** as the third managed scalar, written only alongside a label; tier→value mapping captured empirically from Capture One (IQ-M4 prework) before defaults ship. |
| D-5 | Subcommand name | **`assess-quality`**. |
| D-6 | Folding quality into the default contract | **Never fold in — quality remains permanently opt-in.** Rationale recorded: avoid any risk of touching prior work, even with safeguards. The `.tagging` contract line stays quality-free; reopening requires new acceptance criteria (invariant 17's spirit). |

### 9.2 Still open (plan defaults proceed if unchallenged; none block IQ-M0–M3)

| ID | Decision | Default in this plan | Notes |
|---|---|---|---|
| D-7 | `urgencyMap` default values and whether `writeUrgency` stays on by default | On, with values from the IQ-M4 prework capture | If the capture shows current C1 reads `xmp:Label` directly, consider flipping `writeUrgency` default off (less foreign metadata written). |
| D-8 | `perCriterionProblemKeywords` default | Off (tier keyword only) | On gives "why" filters (`AI Quality\|problems\|focus`) at the cost of keyword-list noise. |
| D-9 | `minimumConfidence` gate default | `medium` | `high` grades fewer images but with fewer embarrassing calls; tune after IQ-M5 sanity checks. |
| D-10 | `assess-quality` default `--mode` | Inherit the analyze default | `whole`-only would halve cost per asset; the subject pass only adds the focus veto. |
| D-11 | Label text for middle tiers | None (only reject→Red, excellent→Green) | Users with 5-color workflows can map all tiers in config. |
| D-12 | IQ-M6 GUI scheduling | Deferred until GUI work is scheduled | Placement (Wizard vs Studio) follows whatever M9 establishes. |

## 10. Documentation updates shipped with this plan

- `AGENTS.md` documentation index: this file added under Plans (done in the same commit as this document).
- On each milestone: the per-milestone doc updates listed in §6 (FR-IQ-051).
