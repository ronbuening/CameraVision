# Phase 3 Requirements - CLI Normalized Batch Tagger

Version: 0.8
Date: 2026-07-08
Change log: v0.8: removed revision-history and status sections (status now lives in README/AGENTS); merged FR3-AFF-005 numbers into the FR3-AFF-006 table; traceability matrix pointer updated.
Builds on: Phase 1 Requirements v0.4 (`01-cli-raw-json-sidecar-requirements.md`) and Phase 2 Requirements v0.5 (`02-cli-xmp-sidecar-requirements-updated.md`)
Binary: `aisidecar` (subcommands: `normalize`, `apply-session`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat`
Primary output artifacts: normalization session file, normalized XMP sidecar files, batch normalization report

This document inherits the Project-Wide Conventions of the Phase 1 requirements and the owned-XMP metadata-writing requirements of Phase 2. They are not restated except where Phase 3 narrows or clarifies their use.

Implementation status lives in `README.md` and `AGENTS.md`; this document carries requirements only. Phase 3 (Milestones 0–11) is implemented; the traceability matrix lives in `agent_docs/cli-implementation-notes.md`.

Phase 3 compatibility evidence is recorded at `agent_docs/release-evidence/phase-3-milestone-11-compatibility-smoke.md`.

## 1. Purpose

Phase 3 shall expand the command-line toolchain so whole-folder scans produce consistent, normalized metadata. The target workflow is a real photographic batch: multiple frames often contain the same subject, event, habitat, or scene type, while the model may describe those things inconsistently across files.

This phase adds a controlled vocabulary, synonym mapping, a metadata-affinity graph, proximity-weighted local consensus, limited global batch backstops, user-supplied session context, normalized write plans, and normalization reports. It remains command-line only.

Phase 3 is the policy and decision layer. It does not replace Phase 2's sidecar engine. It prepares normalized terms and provenance, then hands the write plan to the same `MetadataWriteEngine` and `OwnedXMPSidecarEngine` used by `aisidecar write-xmp`.

## 2. Builds Upon Phase 2

Phase 3 shall reuse, from `AISidecarCore`:

- scanner, identity, and batch-processing modules;
- Phase 1 whole-image and subject-isolated model runs through `AnalyzePipeline`;
- raw JSON sidecar reading, schema-evolution handling, and source verification;
- candidate extraction records with ordinal confidence bands, evidence strings, input role, source field, model-run index, and source provenance;
- keyword text normalization and export policy from Phase 2 where applicable;
- same-base-name group planning and `--pair-scope <union|raw-only|jpeg-only>` behavior;
- XMP target naming and `--output-dir` staging behavior;
- dry-run change planning;
- export progress logs, export reports, and human-readable summaries;
- `MetadataWriteEngine` with the required `OwnedXMPSidecarEngine` implementation;
- `XMPDocumentParser`, `XMPDocumentWriter`, `XMPKeywordReader`, `XMPKeywordMerger`, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`;
- semantic XMP merge, backup, restore, validation, and failure behavior.

Phase 3 shall not contain a separate XMP writer. Any normalization-specific export behavior must be expressed as a normalized write plan consumed by Phase 2's owned sidecar engine.

## 3. Scope

Phase 3 shall normalize tags across images in a batch, folder, explicit file list, or existing set of Phase 1 `.ai.json` sidecars.

It shall solve these first-order problems:

```text
Model says "egret" on one frame and "white heron" on another.
Model says "marsh" on one frame and "wetland" on another.
Model says "bird" on several frames and "Great Blue Heron" on a few stronger frames.
The user knows the folder subject and wants consistent tags applied across the set.
The model produces redundant flat tags that should map into one controlled hierarchy.
A RAW+JPEG pair shares one XMP sidecar and must receive one normalized write plan.
```

Phase 3 shall not treat a folder as one flat voting pool. A real folder may contain multiple local sequences, subjects, lenses, locations, or time blocks. Cross-image normalization shall therefore be local-first, with stronger influence between images that are close in time, space, filename sequence, file-list adjacency, and camera/lens context.

It shall not implement a GUI review workflow, face recognition, individual identity tracking, automated species certainty, OCR/text extraction, embedded metadata writing, or direct Lightroom/Capture One catalog manipulation.

## 4. Command-Line Interface Requirements

Required command shapes:

```bash
# Full pipeline: analyze images, normalize, write session + XMP
aisidecar normalize <folder> --recursive --mode both

# Build a normalization session from existing Phase 1 sidecars without model runs
aisidecar normalize --from-json <json-folder> --recursive --source-root <image-root>

# Build from an explicit newline-delimited source-image list
aisidecar normalize --file-list <image-list.txt> --mode both

# Build a normalization session only; defer XMP export
aisidecar normalize <folder> --session-only

# Write XMP from a previously produced session file, no model runs
aisidecar apply-session <normalization-session-file>

# Write from a session into a staged XMP tree rather than beside source images
aisidecar apply-session <normalization-session-file> --output-dir <xmp-staging-root>
```

Accepted project-wide flags in analyze-and-normalize mode:

```text
--mode <whole|subject|both>
--existing <skip|overwrite|fail>
--recursive
--output-dir <path>
--model <tag>
--model-endpoint <url>
--profile <name>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
--debug-derivatives
--clear-derivative-cache-on-start
--clear-derivative-cache-after-success
--model-response-repair-attempts <n>
--gps-context <off|coarse|exact>
```

Accepted project-wide flags in `normalize --from-json` mode:

```text
--recursive
--output-dir <path>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
```

Accepted project-wide flags in `apply-session` mode:

```text
--output-dir <path>
--config <path>
--log-level <error|warn|info|debug>
--log-format <text|json>
--dry-run
```

Model, rendering, subject-isolation, derivative-cache, and model-response-repair flags are invalid with `apply-session` because no model or image-analysis work occurs. They are also invalid with `normalize --from-json` because existing Phase 1 sidecars are the input. Passing invalid flags shall fail as `E_CONFIG_INVALID` rather than being silently ignored.

Phase 2 analysis/export flags accepted by `normalize`:

```text
--from-json <path>
--source-root <path>
--source-verification <fail|warn|skip>
--write-flat-keywords / --no-write-flat-keywords
--write-hierarchical-keywords / --no-write-hierarchical-keywords
--backup-sidecars / --no-backup-sidecars
--xmp-conflict-policy <fail|merge|backup-and-merge>
--min-confidence <low|medium|high>
--allow-specific-tags
--pair-scope <union|raw-only|jpeg-only>
--write-ai-json / --no-write-ai-json
```

Write-safety and relocation flags accepted by `apply-session`:

```text
--source-root <path>
--source-verification <fail|warn|skip>
--backup-sidecars / --no-backup-sidecars
--xmp-conflict-policy <fail|merge|backup-and-merge>
--allow-stale
```

`apply-session` consumes stored normalization decisions. It shall not accept `--from-json`, `--file-list`, `--mode`, `--model`, `--profile`, `--min-confidence`, `--allow-specific-tags`, `--pair-scope`, `--normalization-mode`, `--affinity-mode`, `--affinity-profile`, `--min-affinity-for-consensus`, `--consensus-threshold`, `--session-subject`, `--session-habitat`, `--session-event`, `--allow-session-subject-propagation`, `--allow-session-habitat-propagation`, `--allow-session-event-propagation`, `--unknown-session-context-policy`, `--session-only`, `--write-ai-json`, or `--no-write-ai-json`.

Phase 3-specific flags:

```text
--file-list <path>
--vocabulary <path>
--normalization-mode <off|single-image|batch-conservative>
--session-subject <text>
--session-habitat <text>
--session-event <text>
--consensus-threshold <float 0..1>
--affinity-mode <off|metadata-weighted>
--affinity-profile <conservative|balanced|aggressive>
--min-affinity-for-consensus <float 0..1>
--allow-session-subject-propagation
--allow-session-habitat-propagation
--allow-session-event-propagation
--unknown-session-context-policy <reject|write-unnormalized>
--session-only
--write-report <path>
--allow-stale
```

Except for `--allow-stale`, Phase 3-specific flags are `normalize` flags. `--allow-stale` is valid only with `apply-session`.

Defaults:

```text
--normalization-mode              batch-conservative
--min-confidence                  medium
--consensus-threshold             0.6
--affinity-mode                   metadata-weighted
--affinity-profile                conservative
--min-affinity-for-consensus      0.35
--unknown-session-context-policy  reject
--allow-session-subject-propagation disabled
--allow-session-habitat-propagation disabled
--allow-session-event-propagation disabled
--source-verification             fail
--write-flat-keywords             enabled
--write-hierarchical-keywords     enabled
--backup-sidecars                 enabled
--xmp-conflict-policy             backup-and-merge
--pair-scope                      union
--allow-stale                     disabled
```

FR3-CLI-001 - `--from-json`, `--file-list`, and positional image input are mutually exclusive for `normalize`.

FR3-CLI-002 - `--source-root` is valid only with `normalize --from-json` and `apply-session` when the session was produced from staged or moved sidecars. It resolves recorded source-relative paths back to current source images.

FR3-CLI-003 - `--write-ai-json` is meaningful only in analyze-and-normalize mode. With `normalize --from-json` or `apply-session`, explicit use shall fail as `E_CONFIG_INVALID`.

FR3-CLI-004 - In `normalize`, `--existing` governs raw `.ai.json` output produced by analysis. Existing XMP sidecars are governed by `--xmp-conflict-policy`.

FR3-CLI-005 - `--session-only` suppresses XMP writing but shall still produce the normalization session file and report. It shall not create, modify, back up, or validate `.xmp` files.

FR3-CLI-006 - The v0.1 `batch-folder-context` mode remains removed. The name is reserved for a future revision that defines folder-level co-occurrence as weak evidence for mid-specificity tags.

FR3-CLI-007 - `--require-review-specific-tags` shall not exist. Review requirements are vocabulary policy through `requires_review`, not invocation policy.

FR3-CLI-008 - `--file-list <path>` is valid only with `normalize`. The file shall be UTF-8 text with one source-image path per line. Blank lines and lines beginning with `#` are ignored. Relative paths are resolved relative to the file-list document. Duplicates after path normalization shall be collapsed with a report warning.

FR3-CLI-009 - `apply-session` shall be model-free, render-free, analysis-free, and normalization-decision-free. Any flag that would require re-analysis or re-normalization shall fail as `E_CONFIG_INVALID`.

FR3-CLI-010 - `--affinity-mode` is valid only with `normalize`. `off` disables affinity scoring and uses the legacy global batch-conservative behavior only where explicitly required for comparison. `metadata-weighted` builds the metadata-affinity graph and is the default.

FR3-CLI-011 - `--affinity-profile` selects a named weight/decay preset. Detailed profile values may be overridden by JSON configuration, but CLI profile selection shall be restricted to `conservative`, `balanced`, and `aggressive` for MVP usability.

FR3-CLI-012 - `--min-affinity-for-consensus` overrides only the minimum edge score used for local consensus eligibility. It shall not change vocabulary policy, `requires_review`, `auto_apply_allowed`, `direct_apply_policy`, `propagation_scope`, `specificity`, or source verification.

FR3-CLI-013 - `--unknown-session-context-policy` governs unmatched `--session-subject`, `--session-habitat`, and `--session-event` values. There shall be no separate subject-only unknown-context flag in v0.7.

FR3-CLI-014 - `--allow-session-subject-propagation`, `--allow-session-habitat-propagation`, and `--allow-session-event-propagation` are independent normalize-only flags. Supplying one shall not authorize propagation of the others.

FR3-CLI-015 - Detailed affinity privacy controls are JSON-configuration only in Phase 3. They shall not be exposed as CLI flags in the MVP; accepted values are `standard` and `debug-exact`, with `standard` as the built-in default.

FR3-CLI-016 - `--allow-specific-tags` is inherited only for Phase 2-style fallback behavior: `--normalization-mode off` and unmatched unnormalized direct terms when no controlled vocabulary entry is available. It shall not override a vocabulary entry's `requires_review`, `direct_apply_policy`, `auto_apply_allowed`, `propagation_scope`, `specificity`, mutual-exclusion policy, affinity thresholds, or user-session conflict rules.

FR3-ERR-001 - Phase 3 adds `E_VOCABULARY_INVALID` for vocabulary schema or integrity failures and `E_SESSION_STALE` for `apply-session` source identity mismatches. It inherits `E_CONFIG_INVALID`, `E_SCHEMA_UNSUPPORTED`, `E_SOURCE_MISSING`, `E_SOURCE_IDENTITY_MISMATCH`, `E_XMP_PARSE_FAILED`, `E_XMP_UNSUPPORTED_RDF`, and `E_VALIDATION_FAILED` from earlier phases.

## 4.1 Normalization Decision Order Requirements

FR3-ORD-001 - Phase 3 shall execute normalization decisions in this order. Tests may exercise individual stages, but production execution shall not reorder them without a schema/versioned policy change:

1. resolve invocation mode, configuration, and output artifact locations;
2. resolve source inputs from positional paths, `--from-json`, or `--file-list`;
3. resolve same-base-name RAW/JPEG groups and `--pair-scope`;
4. verify source identities according to the selected source-verification policy;
5. read or produce Phase 1 raw sidecar records;
6. extract Phase 2 candidate observations and apply `--min-confidence`;
7. normalize candidate text and reject pipe-bearing raw model terms;
8. load and validate the vocabulary, including derived defaults;
9. match candidates and user session context to vocabulary entries;
10. create direct per-asset decisions under `direct_apply_policy`, plus flat-only model-species fallback decisions for unmatched eligible species common names;
11. build affinity input records and the metadata-affinity graph when enabled;
12. compute hierarchy-aware local weighted consensus;
13. apply local propagation under affinity, support, conflict, and vocabulary gates;
14. compute and apply global backstop propagation only for entries explicitly allowed to use it;
15. apply user session context under the session-context rules;
16. run final conflict resolution and deterministic tie-breaking;
17. produce normalized per-asset write plans;
18. write the normalization session and reports;
19. export XMP through Phase 2 `MetadataWriteEngine` / `OwnedXMPSidecarEngine` unless suppressed by `--dry-run` or `--session-only`;
20. validate XMP readback, source non-modification, and semantic preservation when XMP is written.

FR3-ORD-002 - Direct observations and explicit user session context are evaluated before model-evidence propagation. Propagation may add broad or mid entries under policy, but it shall not remove a valid direct decision unless final conflict resolution requires withholding one of two mutually exclusive entries.

FR3-ORD-003 - All per-asset decisions shall record the stage that first created them: `direct_model_observation`, `user_session_context`, `local_affinity_propagation`, `global_backstop_propagation`, or `phase2_fallback`.

FR3-ORD-004 - When two candidate decisions conflict and neither is explicit user context, tie-breaking shall prefer: direct target observation over propagated evidence; higher local weighted agreement; higher support mass; higher maximum supporting affinity; lower specificity when this avoids overclaiming; lexical `canonical_path` order only as the final deterministic tie-break.

FR3-ORD-005 - User session context can override model conflicts only when it is explicit, matched to the vocabulary or accepted under the unknown-session-context policy, and recorded as user evidence. The report shall still list the model conflict rather than hiding it.

## 5. Controlled Vocabulary Requirements

FR3-001 - The program shall support a local controlled vocabulary file.

FR3-001a - If `--vocabulary` is omitted, the program shall load a bundled read-only starter vocabulary from project resources. The bundled vocabulary shall use the same loader, schema validation, SHA-256 identity, synonym collision checks, hierarchy checks, and default policy rules as a user-supplied vocabulary.

FR3-001b - The bundled starter vocabulary is not an exhaustive taxonomy. It shall contain enough conservative entries to validate Phase 3 behavior for broad subjects, wildlife/bird hierarchy, habitat, scene, behavior, and workflow terms. Users may replace it with a richer JSON vocabulary through `--vocabulary`.

FR3-001c - If an explicit `--vocabulary` path is missing, unreadable, unsupported, or invalid, the session shall fail before model runs, session writing, XMP planning, or XMP writing.

FR3-002 - The vocabulary format shall be JSON, validated against a published JSON Schema shipped with the project. YAML shall not be supported.

FR3-002a - The vocabulary file shall carry its own `schema_version` (`ai-sidecar-vocabulary/1.0`) governed by PW-011/PW-012.

FR3-002b - Loaders shall compute a SHA-256 content hash of the vocabulary file after canonical byte reading. This hash is the vocabulary identity recorded in sessions and reports.

FR3-003 - Each vocabulary entry shall support:

```text
canonical_path                e.g. "Wildlife|Birds|Herons and Egrets|Great Egret"
flat_keyword                  exported flat form, e.g. "Great Egret"
namespace                     one of the FR3-004 namespaces
parent_path                   null for root entries; otherwise an existing canonical_path
synonyms                      array of strings
requires_review               default: true for Species/Taxonomy, People,
                              Location Type entries naming exact places,
                              rare species, exact-location implications;
                              false otherwise
direct_apply_policy           one of allow|withhold|flat_only|user_only;
                              governs direct model observations and user context
auto_apply_allowed            propagation gate only; default false for entries
                              with requires_review
propagation_scope             one of none|direct_only|local|global;
                              governs propagation, not direct observations
specificity                   one of broad|mid|specific;
                              default derived from namespace and hierarchy depth
mutually_exclusive_group      optional string; entries sharing a group value
                              cannot both be true of one image
export_flat_keyword           default: true
export_hierarchical_keyword   default: true
notes                         optional text
```

FR3-003a - Canonical paths shall be unique across the vocabulary. Violations shall fail loading with `E_VOCABULARY_INVALID`.

FR3-003b - A synonym shall map to exactly one canonical path. A synonym appearing under two entries, or a string that is both a canonical term of one entry and a synonym of another, shall fail loading with `E_VOCABULARY_INVALID` and a listing of the collisions.

FR3-003c - The hierarchy implied by `parent_path` shall be a strict tree: no cycles and no orphans. Every non-root `parent_path` must exist.

FR3-003d - Primary text folding for synonym matching shall use Unicode NFC, case folding, and whitespace collapsing. Diacritics shall not be folded, and stemming shall not be performed.

FR3-003d-1 - After primary matching fails, vocabulary lookup may use ambiguity-guarded fallback keys that normalize punctuation separators, compatibility quotes/dashes, apostrophe possessives, and ampersands as `and`, and may try simple final-token singular/plural variants. Fallback matches must be ignored when a fallback key maps to more than one canonical path, must preserve canonical output spelling, and must not relax raw pipe rejection, diacritic policy, or stemming policy.

FR3-003e - Matching preserves and outputs the canonical spelling and casing of the vocabulary entry.

FR3-003f - `canonical_path` uses `|` as the vocabulary hierarchy separator. Empty path levels are invalid. Individual path levels may not contain literal `|` after parsing.

FR3-003g - Raw model candidates containing `|` remain invalid for direct export under Phase 2 rules. Phase 3 may export hierarchical keywords containing `|` only when the separator is introduced by a valid controlled-vocabulary `canonical_path` or by user session context matched to that vocabulary.

FR3-003h - `flat_keyword` shall not contain `|`. If a vocabulary entry violates this, loading fails with `E_VOCABULARY_INVALID`.

FR3-003i - `propagation_scope` governs propagation only: `none` means never propagate; `direct_only` means never propagate from other assets but may still be written from direct evidence under `direct_apply_policy`; `local` means eligible for metadata-affinity local propagation; `global` means eligible for whole-batch backstop propagation only under the stricter global threshold.

FR3-003j - `specificity` governs default propagation thresholds. `broad` entries may use broad local thresholds, `mid` entries require stronger support, and `specific` entries shall not propagate from model evidence by default.

FR3-003k - `direct_apply_policy` governs direct observations and explicit user context: `allow` permits normal flat and hierarchical export when the entry is directly observed or supplied by the user; `withhold` records the evidence but exports nothing automatically; `flat_only` permits only `flat_keyword` export and suppresses hierarchy for that decision; `user_only` withholds model-only direct observations but permits explicit user session context for that entry.

FR3-003l - `auto_apply_allowed` means propagation permission only. It shall not be interpreted as permission to write direct model observations, and it shall not override `direct_apply_policy`, `requires_review`, or namespace-specific policy.

FR3-003m - The loader shall reject any vocabulary entry whose `direct_apply_policy`, `propagation_scope`, or `specificity` value is outside the enumerated set with `E_VOCABULARY_INVALID`.

FR3-004 - The vocabulary shall support at least these namespaces:

```text
Subject
Species / Taxonomy
Habitat
Behavior
Scene
Location Type
Lighting
Composition
Technical Quality
Event
People
Objects
Text / Signage
Workflow
```

FR3-005 - Vocabulary defaults shall be conservative. Entries in `Species / Taxonomy`, `People`, named-place `Location Type`, rare-species, exact-location, and named-event areas shall default to `requires_review = true`, `direct_apply_policy = withhold`, `auto_apply_allowed = false`, `propagation_scope = none`, and `specificity = specific` unless explicitly overridden by the vocabulary file.

FR3-005a - If `propagation_scope` is omitted, the loader shall derive a conservative default: `none` for review-required entries, named people, named events, exact named places, rare species, and exact-location implications; `direct_only` for species/taxonomy leaf entries and technical/composition/lighting terms; `local` for broad taxonomy ancestors, generic subject, habitat, scene, behavior, object, and generic location-type entries; and `global` only for explicitly configured broad workflow or session-context entries.

FR3-005b - If `specificity` is omitted, the loader shall derive a conservative default from namespace and hierarchy position. Broad ancestors such as `Wildlife`, `Birds`, `Outdoor`, `Wetland`, and `Portrait` are `broad`; habitat, scene, behavior, and generic location subtypes are usually `mid`; species leaves, named places, named people, named events, rare-species entries, and exact-location implications are `specific`.

FR3-005c - If `direct_apply_policy` is omitted, the loader shall derive a conservative default: `withhold` for review-required model-evidence entries, named people, named exact places, named events, rare species, exact-location implications, and scientific binomial entries; `user_only` for entries safe only when explicitly supplied by the user; `flat_only` for unmatched or sensitive user-supplied context accepted under the unknown-session-context policy; and `allow` for broad generic subjects, habitat, scene, behavior, objects, workflow, and non-sensitive taxonomy ancestors.

FR3-005d - `requires_review = true` shall imply `auto_apply_allowed = false` unless the vocabulary file explicitly sets a different value and the entry is not in a prohibited model-propagation class. Even when explicitly overridden, `requires_review = true` entries shall not propagate from model evidence under FR3-014.

FR3-006 - The normalizer shall expose a vocabulary loader API usable by both CLI and GUI targets. The GUI may edit vocabulary files later, but Phase 3 owns the validation and canonicalization semantics.

FR3-007 - The program shall support user-supplied session context through `--session-subject`, `--session-habitat`, and `--session-event`.

FR3-008 - User-supplied session context shall be treated as user evidence, not model evidence, throughout aggregation, provenance, and reporting.

## 6. Batch Normalization Requirements

FR3-009 - The program shall create one batch normalization session for each folder, explicit file list, or `.ai.json` sidecar collection.

FR3-010 - The session shall aggregate eligible candidates from all images before writing final XMP sidecars unless `--normalization-mode single-image` is selected.

FR3-010a - `--normalization-mode off` shall disable vocabulary mapping, affinity scoring, and batch propagation. It still creates a Phase 3 session/report and uses Phase 2 candidate extraction/export policy. This mode exists for baseline comparison and for diagnosing normalization effects.

FR3-010b - `--normalization-mode single-image` shall apply vocabulary matching and synonym collapse independently per asset or same-base-name group. It shall not compute affinity edges and shall not propagate batch-level tags from other assets.

FR3-010c - `--normalization-mode batch-conservative` shall perform per-asset vocabulary matching, metadata-affinity graph construction, hierarchy-aware local weighted consensus, conflict checks, global backstop statistics, and conservative propagation under FR3-013 through FR3-016 and FR3-AFF-001 through FR3-AFF-022.

FR3-011 - For each canonicalized candidate, the session shall compute global supporting image count, eligible image count, agreement frequency, confidence-band distribution, source-field distribution, and contributing input roles. In `batch-conservative` mode with `--affinity-mode metadata-weighted`, it shall also compute per-target local weighted agreement, support mass, eligible mass, supporting-neighbor count, and maximum supporting-neighbor affinity. Agreement frequency and local weighted agreement are the primary consensus signals; confidence bands are secondary filters and tiebreakers. Self-reported model confidence shall never outrank cross-image agreement in a decision rule.

FR3-011a - Confidence bands are ordinal filters, not numeric weights. After `--min-confidence` filtering, each surviving direct observation contributes one unit of direct support for its own entry and hierarchy ancestors. The confidence band, source field, and input role are stored for provenance and tie-breaking only. Whole-image and subject-isolated observations shall not receive numeric multipliers in the MVP.

FR3-011b - Direct model observations may be written only under the matched vocabulary entry's `direct_apply_policy` and export controls. A direct observation of a `withhold` entry shall be recorded in decisions and reports but omitted from XMP. A direct observation of a `flat_only` entry may write only `dc:subject`. A direct observation of a `user_only` entry shall be withheld unless the same entry is supplied as explicit user session context.

FR3-011c - An unmatched model candidate from the Phase 1 `species` field may produce a `model_species_fallback` decision when it passes text, confidence, coordinate/GPS evidence, and Phase 2 specific-tag fallback filtering. The fallback shall normalize equivalent model species strings across the batch, write only a flat `dc:subject` keyword for images with direct model species evidence, record `direct_apply_policy = flat_only`, leave `canonical_path` and hierarchical output empty, and shall not participate in hierarchy-aware support or local/global propagation.

FR3-012 - The session shall distinguish per-image tags from batch-level tags.

FR3-013 - Broad tags with high agreement, such as `Bird`, `Wildlife`, `Outdoor`, `Wetland`, or `Portrait`, may be propagated conservatively through metadata-affinity local consensus. Whole-batch propagation is permitted only for entries whose vocabulary `propagation_scope = global`.

FR3-013a - Local propagation rule: a candidate is locally propagatable when, after `--min-confidence` filtering of per-image observations, the vocabulary entry has `auto_apply_allowed = true`, `requires_review = false`, `propagation_scope = local`, the target asset has no direct conflicting observation, the local neighborhood has no blocking conflict mass, and the local weighted agreement, support mass, supporting-neighbor count, and maximum supporting-neighbor affinity meet the thresholds for the entry's `specificity`.

FR3-013b - Counting is hierarchy-aware. An observation of a descendant supports every ancestor on its canonical path. A frame tagged `Great Blue Heron` counts as support for `Herons and Egrets`, `Birds`, and `Wildlife`.

FR3-013c - `--min-confidence` filters observations before frequency counting, not after.

FR3-013d - The normalizer shall compute global agreement over eligible images and local weighted agreement over eligible high-affinity neighbors. Images with model failure, unsupported format, source-verification failure, or no usable Phase 1 sidecar are excluded from denominators and listed in the report.

FR3-013e - Global batch propagation is a backstop, not the default. It shall require `propagation_scope = global`, `auto_apply_allowed = true`, `requires_review = false`, no local conflict, global agreement at or above the profile's global threshold, global eligible asset count at or above the profile minimum, and global supporting asset count at or above the profile minimum. It shall not apply species leaves, named people, named places, named events, or other `specific` entries from model evidence.

FR3-013f - The default global backstop minimums are: conservative profile requires at least five eligible assets and three supporting assets; balanced requires at least four eligible assets and three supporting assets; aggressive requires at least three eligible assets and two supporting assets. Percentages alone are insufficient.

FR3-014 - Specific tags — entries with `requires_review = true` — shall not be propagated automatically from model evidence regardless of agreement level.

FR3-015 - When `--session-subject`, `--session-habitat`, or `--session-event` is supplied, the program may apply that context to non-conflicting eligible images only when the corresponding propagation flag is set: `--allow-session-subject-propagation`, `--allow-session-habitat-propagation`, or `--allow-session-event-propagation`.

FR3-016 - Any value propagated from session context shall record `source = user_session_context`, never `source = model`, and shall preserve its context role of `subject`, `habitat`, or `event`.

FR3-017 - The normalizer shall collapse duplicate and synonymous candidates into a single canonical path.

FR3-017a - The model-species fallback shall collapse direct species observations by folded model text, separator-insensitive punctuation variants, possessive variants, and final-token singular/plural variants. This collapse is only a flat keyword display normalization and shall not infer taxonomy or synonyms outside the observed model strings.

FR3-018 - The normalizer shall remove redundant flat keywords that merely repeat canonical hierarchy nodes, according to each vocabulary entry's export rules.

FR3-019 - The normalizer shall avoid destructive simplification. Mapping upward to a defensible ancestor is allowed (`white heron` -> `Herons and Egrets`). Mapping sideways or downward to a more specific node (`white heron` -> `Great Egret`) is forbidden unless a vocabulary synonym/rule or user session context explicitly supports it.

FR3-020 - The normalizer shall maintain separate provenance records for whole-image observations, subject-isolated observations, normalized local context, normalized global context, and user session context.

## 7. Metadata Affinity and Local Weighted Consensus Requirements

FR3-AFF-001 - In `--normalization-mode batch-conservative` with `--affinity-mode metadata-weighted`, Phase 3 shall build an asset-affinity graph before cross-image propagation. Each node represents one source asset or one same-base-name group as resolved under Phase 2 group policy. A RAW+JPEG same-base-name group shall be one normalization node and shall not receive double voting power.

FR3-AFF-002 - Each edge shall carry an affinity score in `[0.0, 1.0]`. A high score means the two nodes are likely part of the same local photographic sequence. A low score means same-folder membership alone is weak or irrelevant normalization evidence.

FR3-AFF-003 - Primary affinity components are capture-time proximity, GPS/spatial proximity, filename sequence proximity, and explicit file-list adjacency. Camera/lens agreement is a reinforcing component only. Gear match alone shall never create propagation eligibility.

FR3-AFF-003a - Affinity input sources shall be explicit by workflow. Analyze-and-normalize reads capture time, GPS, camera/lens identity, filename, and relative directory from the current source image metadata and Phase 1 source records when available. `normalize --from-json` reads Phase 1 sidecar provenance first, then current resolved source-image metadata when the source path exists and source verification permits it. `normalize --file-list` reads current source-image metadata and records the list index as possible adjacency evidence. `apply-session` uses stored decisions and stored audit scores only; it shall not recompute affinity or change propagation decisions.

FR3-AFF-003b - Affinity metadata extraction is read-only. It may inspect image metadata and sidecar provenance but shall not write EXIF, XMP non-keyword fields, source files, raw sidecars, or application catalogs.

FR3-AFF-004 - Affinity scoring shall be deterministic and testable. The default scoring function for a component is:

```text
decay(value, half_life, cutoff):
  if value is missing:
      return missing
  if value > cutoff:
      return 0.0
  return pow(0.5, value / half_life)
```

Missing primary components are omitted from the available-weight denominator. Present-but-distant primary components score near zero and therefore reduce affinity.

FR3-AFF-005 - The default `conservative` profile's decay, gear, edge-storage, neighbor, and global-backstop parameter values are the `conservative` column of the FR3-AFF-006 profile table, which is the single source of profile numbers. The conservative profile shall additionally use these primary component weights:

```text
Primary component weights:
  time_score       0.45
  gps_score        0.35
  filename_score   0.20
```

FR3-AFF-006 - The named profiles shall have these default values unless overridden by JSON configuration:

```text
Parameter                         conservative   balanced   aggressive
time_half_life                    2 min          5 min      15 min
time_cutoff                       30 min         2 hr       6 hr
gps_half_distance                 25 m           75 m       200 m
gps_cutoff                        250 m          1000 m     3000 m
filename_half_gap                 5              10         25
filename_cutoff                   30             100        250
gear_boost_max                    0.20           0.30       0.40
min_affinity_for_consensus        0.35           0.25       0.15
min_affinity_to_store_edge        0.15           0.10       0.05
max_neighbors_per_asset           30             50         100
global_consensus_threshold        0.80           0.75       0.70
global_min_eligible_assets        5              4          3
global_min_supporting_assets      3              3          2
```

FR3-AFF-007 - Capture-time score shall use absolute capture-time delta in seconds:

```text
time_score = decay(abs(capture_time_A - capture_time_B), time_half_life_seconds, time_cutoff_seconds)
```

Prefer EXIF `DateTimeOriginal` with offset data when available. If capture time has no timezone and files are from different camera models, cap `time_score` at `0.70` unless GPS or filename proximity also supports the relationship. File modification time shall not be used by default.

FR3-AFF-008 - GPS score shall use Haversine distance in meters:

```text
gps_score = decay(haversine(assetA.gps, assetB.gps), gps_half_distance_meters, gps_cutoff_meters)
```

If either file lacks GPS, GPS is missing, not zero. If both files have usable GPS and are far apart, the component is present and scores near zero. GPS coordinates remain internal affinity evidence only and shall not become exported keywords by themselves.

FR3-AFF-009 - Filename score shall use numeric sequence gap when compatible camera-style stems can be parsed in the same relative directory:

```text
filename_score = decay(abs(sequence_A - sequence_B), filename_half_gap, filename_cutoff)
```

The parser shall handle ordinary stems such as `_DSC1234`, `DSC_1234`, `IMG_1234`, and `P1234567`. If sequence numbers are not parseable, the component is missing unless `--file-list` supplies explicit adjacency.

FR3-AFF-010 - Explicit file-list adjacency may supply filename/list proximity when sequence numbers are absent. Adjacent list entries may be treated as sequence gap `1`; larger list-index gaps may use the same filename decay parameters. File-list adjacency is primary evidence only for that invocation and shall be recorded as `explicit_file_list_adjacency`.

FR3-AFF-011 - Gear score shall be computed from body and lens signals:

```text
body_score:
  1.00  same body serial or stable body identity
  0.75  same make/model, serial unavailable
  0.25  same make only
  0.00  mismatch or unavailable

lens_score:
  1.00  same normalized lens identity
  0.80  same lens model string, no stronger ID available
  0.40  same focal-length range and max aperture only
  0.00  mismatch or unavailable

gear_score = (0.35 * body_score) + (0.65 * lens_score)
```

FR3-AFF-012 - The final edge score shall be:

```text
primary_available_weight = sum(weights for available primary components)

if primary_available_weight == 0:
    primary_score = 0.0
else:
    primary_score = weighted_sum(available primary scores) / primary_available_weight

affinity = min(1.0, primary_score * (1.0 + gear_boost_max * gear_score))
```

If only time is usable, cap `primary_score` at `0.85`; if only GPS is usable, cap it at `0.80`; if only filename/list adjacency is usable, cap it at `0.70`. These caps prevent a single signal from overstating certainty.

FR3-AFF-013 - Edges below `min_affinity_to_store_edge` may be omitted from the session edge list for size control, but their absence shall not change deterministic decisions. Edges below `min_affinity_for_consensus` shall not contribute to local propagation.

FR3-AFF-013a - Configuration shall enforce `min_affinity_to_store_edge <= min_affinity_for_consensus`. If a future configuration permits otherwise, every edge that contributes to a decision shall still be stored even when below the configured storage threshold. The audit trail must never omit decision-contributing edges.

FR3-AFF-013b - For batches above 500 normalization nodes, graph construction shall use deterministic candidate-neighbor generation before scoring rather than an unbounded all-pairs pass. Candidate neighbors shall be drawn from time windows, GPS windows or grid buckets, same relative directory and filename-sequence windows, explicit file-list adjacency windows, and same-base-name groups. After scoring, retain at most `max_neighbors_per_asset` neighbors per asset by descending affinity, then ascending target asset ID as the final tie-breaker. Smaller batches may use all-pairs scoring only when tests prove identical retained edges.

FR3-AFF-013c - Stored affinity scores and component scores shall be rounded to six decimal places in JSON artifacts. Sorting shall be stable: edges by `from_asset_id`, descending affinity, `to_asset_id`; local-consensus records by `target_asset_id`, descending local weighted agreement, descending support mass, then `canonical_path`. Score bands shall be deterministic: `very_strong >= 0.75`, `strong >= 0.55`, `moderate >= 0.35`, `weak >= 0.15`, and `ignored < 0.15`.

FR3-AFF-014 - Local weighted agreement for target asset `A` and canonical tag `T` shall be:

```text
neighbors(A) = eligible assets B where affinity(A, B) >= min_affinity_for_consensus
eligible_mass(A) = sum(affinity(A, B)) for neighbors(A)
support_mass(A, T) = sum(affinity(A, B)) for neighbors that directly observe T or a descendant of T
local_weighted_agreement(A, T) = support_mass(A, T) / eligible_mass(A)
```

If `eligible_mass(A) == 0`, local weighted agreement is undefined and no local model-evidence propagation occurs for that target.

FR3-AFF-015 - Direct evidence on the target asset remains stronger than neighbor evidence. A direct target observation may be written under vocabulary policy even if local agreement is low. A direct conflicting observation on the target asset blocks neighbor propagation.

FR3-AFF-016 - Default local propagation thresholds by specificity shall be:

```text
Broad tags:
  local_weighted_agreement       >= 0.60
  support_mass                   >= 0.75
  supporting_neighbor_count      >= 1
  max_supporting_affinity        >= 0.55

Mid-specific tags:
  local_weighted_agreement       >= 0.70
  support_mass                   >= 1.25
  supporting_neighbor_count      >= 2
  max_supporting_affinity        >= 0.55

Specific tags:
  model-only propagation         never by default
```

FR3-AFF-017 - `requires_review` entries shall not propagate from model evidence, even inside a high-affinity local cluster. `specific` entries shall be `direct_only` or `none` unless vocabulary or user session context explicitly overrides them.

FR3-AFF-017a - Local conflict mass shall be computed for any candidate tag `T` with vocabulary siblings under the same `parent_path` or members of the same `mutually_exclusive_group`. For target asset `A`:

```text
conflict_support_mass(A, T) = sum(affinity(A, B)) for neighbors that directly observe a conflicting entry
conflict_weighted_agreement(A, T) = conflict_support_mass(A, T) / eligible_mass(A)
```

FR3-AFF-017b - Local propagation of `T` shall be blocked when the target asset has a direct conflicting observation, or when `conflict_weighted_agreement >= 0.35` and `conflict_support_mass >= 0.75` under the conservative profile. Balanced and aggressive profiles may lower the agreement threshold to `0.30` and `0.25` respectively, but shall not ignore direct target conflicts. Reports shall distinguish `blocked_direct_conflict` from `blocked_local_conflict_mass`.

FR3-AFF-018 - The affinity graph may be used to derive local clusters for reporting and audit. Clustering is explanatory only; propagation decisions are governed by edge scores, local weighted agreement, vocabulary policy, and conflict checks.

FR3-AFF-019 - Phase 3 shall not export capture time, GPS coordinates, camera identity, lens identity, filename, or file-list adjacency as inferred XMP keywords merely because they were used for affinity scoring.

FR3-AFF-020 - Normal reports shall store derived affinity facts rather than raw sensitive metadata: time deltas or quality flags instead of exact capture timestamps, Haversine distances instead of exact GPS coordinates, camera/lens match classes instead of raw camera serial numbers, and asset IDs or relative paths instead of absolute paths where possible.

FR3-AFF-021 - Normalization sessions may store exact source paths and source identity hashes because `apply-session` requires them, but they shall not store exact GPS coordinates, exact camera serial strings, or exact capture timestamps unless an explicit debug/audit configuration key is enabled. That key shall default to disabled and shall be recorded in the session.

FR3-AFF-022 - Camera serials used for affinity shall be hashed before session/report persistence. The hash shall be stable within one session for comparison but shall not be used as an exported metadata value.

## 8. User Session Context Requirements

FR3-021 - Same-subject, same-habitat, and same-event assumptions shall be activated only by explicit user flags, never hidden inference.

FR3-022 - `--session-subject`, `--session-habitat`, and `--session-event` accept plain text and shall be matched against the vocabulary using FR3-003d folding. Subject values should match `Subject` or `Species / Taxonomy`; habitat values should match `Habitat`, `Scene`, or generic `Location Type`; event values should match `Event` or `Workflow`. Cross-namespace matches are allowed only when the folded text maps to exactly one vocabulary entry and the report records the namespace used.

FR3-023 - If any `--session-subject`, `--session-habitat`, or `--session-event` value cannot be matched to a vocabulary entry, `--unknown-session-context-policy` governs:

```text
reject              default; fail the session before any model run or write
write-unnormalized  record and export it as a flat user keyword with
                    source = user_session_context and no hierarchy
```

The default is `reject` because session context important enough to apply across a folder is important enough to canonicalize first.

FR3-024 - Folder-level session context propagation shall warn when individual model observations conflict with the supplied subject, habitat, or event.

FR3-024a - Conflict definition: image observations conflict with session context when they support, at or above `--min-confidence`, a vocabulary entry that is either (a) a sibling of the session context entry, meaning same `parent_path` and different leaf, or (b) a member of the same `mutually_exclusive_group`. Mere absence of support is not conflict.

FR3-025 - The session report shall list images that did not support each supplied session context value at or above the minimum band, and separately, images that conflicted under FR3-024a. Conflicted images shall not receive the conflicting propagated context. Weakly supporting or absent images may receive user context only when the relevant propagation gate permits it, with weak or absent model support noted in provenance.

FR3-026 - Phase 3 makes no claim of individual animal or person identity tracking. Same-subject behavior is batch-context normalization, not biometric or individual identity recognition.

FR3-026a - `--session-subject` may apply to all non-conflicting assets only when `--allow-session-subject-propagation` is supplied. This extra gate remains required because subject propagation can overclaim the content of a frame.

FR3-026b - `--session-habitat` may apply to all non-conflicting assets only when `--allow-session-habitat-propagation` is supplied. It shall be recorded as `source = user_session_context` with `context_type = habitat`.

FR3-026c - `--session-event` may apply to all non-conflicting assets only when `--allow-session-event-propagation` is supplied. It shall be recorded as `source = user_session_context` with `context_type = event`.

FR3-026d - Session context supplied under `write-unnormalized` may write only flat keywords, shall use `direct_apply_policy = flat_only` for that decision, and shall not create hierarchy, propagation eligibility, or vocabulary synonyms.

FR3-026e - A vocabulary entry with `direct_apply_policy = withhold` shall not be exported from session context unless the vocabulary file explicitly marks it `user_only` or `allow`. `requires_review` does not block explicit user context by itself, but the report shall mark the decision as user-supplied and review-sensitive.

FR3-026f - Session context shall not create GPS-derived named place keywords. A habitat such as `Wetland` may be user-supplied or vocabulary-matched. A named place inferred from coordinates shall not be created by Phase 3.

FR3-026g - Session context values shall be included in the session file under a structured `session_context` array with original text, folded text, matched canonical path when any, context type, unknown-policy result, direct-apply policy, propagation gate, conflict count, and export result.

## 9. Normalization Session File Requirements

FR3-027 - The program shall write a normalization session file before any XMP export. Dry-run and session-only modes shall still write a session file unless a future schema explicitly defines a report-only mode.

FR3-027a - The session file schema identifier shall be `ai-sidecar-normalization/1.0`.

FR3-027b - The session file shall be valid JSON and shall be governed by PW-011/PW-012.

Minimum structure:

```json
{
  "schema_version": "ai-sidecar-normalization/1.0",
  "session": {
    "normalization_mode": "batch-conservative",
    "created_at": "ISO-8601",
    "scan_root": "string or null",
    "source_root": "string or null",
    "output_dir": "string or null"
  },
  "vocabulary": {
    "path": "string",
    "sha256": "string",
    "schema_version": "ai-sidecar-vocabulary/1.0"
  },
  "resolved_configuration": {},
  "session_context": [],
  "privacy": {
    "exact_affinity_inputs_persisted": false,
    "camera_serials_hashed": true,
    "gps_coordinates_persisted": false
  },
  "xmp_writer": {
    "engine": "OwnedXMPSidecarEngine",
    "engine_version": "string",
    "writer_recipe_version": "string"
  },
  "source_ai_sidecars": [],
  "source_assets": [],
  "same_base_name_groups": [],
  "affinity": {
    "mode": "metadata-weighted",
    "profile": "conservative",
    "component_weights": {},
    "decay": {},
    "nodes": [],
    "edges": [],
    "clusters": []
  },
  "batch_candidates": [],
  "local_consensus": [],
  "per_asset_decisions": [],
  "xmp_write_plans": [],
  "warnings": [],
  "errors": []
}
```

FR3-028 - The session file shall record the vocabulary SHA-256 content hash. The human-readable version string is a label; the hash is the identity.

FR3-029 - The session file shall record normalization mode, global and local thresholds, affinity mode, affinity profile, session-subject inputs, pair scope, source-verification policy, output-dir behavior, and export flags — the complete resolved configuration per PW-008.

FR3-030 - The session file shall be usable as input to `apply-session` without re-running the vision model.

FR3-030a - Each `per_asset_decisions` entry shall bind to the asset's source identity hash, not only its path. `apply-session` shall verify identities before writing. A mismatch fails that asset with `E_SESSION_STALE` and continues the batch.

FR3-030b - `--allow-stale` may force an `apply-session` write despite source identity mismatch. The report shall record the override per asset. This flag shall not be available by configuration file default; it must be explicit on the invocation.

FR3-030c - A normalization session shall not store a stale copy of the current XMP sidecar as the source of truth for later writeback. `apply-session` must read the current sidecar at write time and merge against current disk content.

FR3-030d - The session may store the planned XMP target path, but `apply-session` shall be able to recompute target paths from current source resolution and `--output-dir`. Recomputed paths shall be reported when they differ from stored paths.

FR3-030e - The session file shall record affinity mode, profile, component weights, decay parameters, edge thresholds, node records, stored affinity edges, component scores, score bands, basis labels, local clusters when emitted, and local weighted consensus records sufficient to audit decisions without rerunning analysis.

FR3-030f - Each stored affinity edge shall include final affinity, band, time/GPS/filename/body/lens/gear component scores where available, and basis labels such as `capture_time`, `gps`, `filename_sequence`, `file_list_adjacency`, and `camera_lens`.

FR3-030g - Each propagated per-asset decision shall record local weighted agreement, support mass, eligible mass, supporting-neighbor count, maximum supporting affinity, rule name, supporting neighbor IDs retained within session size limits, and whether the decision used local affinity, global consensus, or user session context.

FR3-030h - `apply-session` shall consume stored decisions and shall not rerun model analysis, re-extract candidates, reload the vocabulary to change decisions, or recompute affinity to change propagation decisions unless a future schema explicitly defines that behavior.

FR3-030i - The session file shall record deterministic policy metadata: score rounding precision, score-band thresholds, edge sorting order, neighbor truncation rule, decision tie-break order, and whether exact affinity input persistence was enabled.

FR3-030j - The session file shall record artifact outputs and planned outputs in a stable `artifacts` object: session path, report path, summary path, progress path, dry-run change-plan path or stream, and XMP target root. This object is required even when some artifacts are intentionally suppressed.

FR3-030k - The session file shall record local conflict mass for propagated candidates when a conflict group exists: conflict support mass, conflict weighted agreement, conflicting canonical paths, and the resulting block or allow rule.

## 10. XMP Export Requirements

FR3-031 - Phase 3 shall use the Phase 2 `MetadataWriteEngine`, `OwnedXMPSidecarEngine`, backup, restore, semantic validation, and same-base-name group behavior unchanged.

FR3-031a - Phase 3 shall not invoke ExifTool or any other external metadata command-line tool for required runtime behavior.

FR3-032 - Phase 3 shall write only normalized tags approved by policy under FR3-013 through FR3-016 and FR3-AFF-014 through FR3-AFF-022.

FR3-033 - Phase 3 shall write flat `XMP-dc:Subject` and Lightroom-style hierarchical `XMP-lr:HierarchicalSubject` per vocabulary entry export rules and Phase 2 export flags.

FR3-033a - For flat export, Phase 3 writes each entry's `flat_keyword`.

FR3-033b - For hierarchical export, Phase 3 writes the entry's `canonical_path` using `|` separators. This is controlled-vocabulary output and is the only Phase 3 source of multi-level hierarchical keywords.

FR3-033c - If `export_flat_keyword = false`, the entry shall not contribute to `dc:subject`. If `export_hierarchical_keyword = false`, the entry shall not contribute to `lr:HierarchicalSubject`.

FR3-033d - `write-unnormalized` session context may write only a flat keyword. It shall not invent a hierarchy.

FR3-034 - Existing sidecar metadata shall be preserved semantically as Phase 2 specifies. Validation shall use the owned parser, `XMPMetadataSnapshot`, and `XMPUnmanagedContentFingerprint`, excluding only the managed keyword fields intentionally changed.

FR3-034a - Malformed XMP sidecars shall fail as `E_XMP_PARSE_FAILED`. Unsupported but well-formed RDF/XMP shapes that cannot be safely merged shall fail as `E_XMP_UNSUPPORTED_RDF`. In both cases the source image file and existing sidecar shall be left unchanged.

FR3-034b - The batch shall continue after per-sidecar export failures. Failures shall be written to the progress log, session report, and export report.

FR3-034c - Phase 3 export reports shall record the owned XMP engine name/version and writer recipe version for every run.

FR3-035 - Phase 3 shall write a batch normalization report explaining, per tag and per asset: what was canonicalized from what, what was propagated and under which rule, what affinity basis and local weighted consensus supported or blocked propagation, what was skipped and why, what conflicts were detected, which images were weakly supported, what XMP target was planned, and what XMP validation result occurred.

FR3-036 - Report skip, propagation, and block reason codes shall include at least:

```text
below_confidence_threshold
unmatched_vocabulary
requires_review
consensus_below_threshold
blocked_low_affinity
blocked_low_support_mass
blocked_low_supporting_neighbor_count
blocked_direct_conflict
blocked_local_conflict_mass
blocked_requires_review
blocked_gear_only_affinity
blocked_missing_primary_affinity
conflict
contains_hierarchy_separator
specific_tag_policy
source_missing
source_identity_mismatch
session_stale
xmp_parse_failed
xmp_unsupported_rdf
xmp_validation_failed
disabled_flat_export
disabled_hierarchical_export
duplicate
gps_missing_used_time_filename_fallback
gps_present_but_distant
filename_unparseable
capture_time_missing
camera_lens_match_insufficient
direct_apply_withheld
direct_apply_flat_only
user_context_unmatched_rejected
user_context_written_unnormalized
global_min_support_not_met
global_min_eligible_not_met
privacy_redacted
```

FR3-037 - Folder runs shall produce:

```text
normalization-session-<ISO-8601-timestamp>.json
normalization-report-<ISO-8601-timestamp>.json
normalization-summary-<ISO-8601-timestamp>.md
normalization-progress-<ISO-8601-timestamp>.jsonl
```

These files shall be written under `--output-dir` when supplied, otherwise beside the scan root, JSON scan root, or session file as appropriate.

`aisidecar cleanup` may remove normalization progress/report/summary artifacts from a selected folder, but it shall retain normalization session JSON because that file is the durable input for `apply-session`. Cleanup also shall not remove XMP sidecars, backups, source images, or derivative cache artifacts.

FR3-038 - The report schema identifier shall be `ai-sidecar-normalization-report/1.0`.

FR3-039 - Dry-run mode shall build the full normalization session and XMP change plans, but shall not create, modify, back up, restore, or validate XMP sidecars on disk.

FR3-040 - Output artifact behavior shall follow this truth table. `yes` means the artifact is created or updated; `plan-only` means an in-memory or JSON plan is produced without disk sidecar changes; `no` means the artifact is not created and existing files are not modified.

```text
Invocation state                         session   report   summary   progress   xmp sidecars   backups/restore   xmp validation
normal normalize write                   yes       yes      yes       yes        yes            yes              yes
normalize --session-only                 yes       yes      yes       yes        no             no               no
normalize --dry-run                      yes       yes      yes       yes        plan-only      no               no
normalize --dry-run --session-only       yes       yes      yes       yes        no             no               no
apply-session normal write               read      yes      yes       yes        yes            yes              yes
apply-session --dry-run                  read      yes      yes       yes        plan-only      no               no
```

FR3-041 - `--output-dir` affects XMP target staging and default artifact placement. If `--write-report` overrides the report path, the session and summary shall still record the report path and effective XMP target root.

FR3-042 - A `read` session entry in FR3-040 means `apply-session` reads an existing session file and shall not rewrite it as the authoritative decision artifact. It may write a separate apply report and summary.

## 11. Acceptance Criteria

AC3-001 - The program can process a folder of images and produce Phase 1 AI JSON sidecars, a Phase 3 session file, normalized Phase 2 XMP sidecars, and a normalization report in one invocation.

AC3-002 - Synonyms map to one canonical keyword path with canonical spelling preserved.

AC3-003 - Duplicate tags are not exported repeatedly.

AC3-004 - A broad tag observed directly or via descendants propagates to a target asset only when vocabulary policy permits it and local weighted agreement, support mass, supporting-neighbor count, and maximum supporting affinity meet the configured thresholds. The same tag below local threshold or in a low-affinity part of the folder does not propagate.

AC3-005 - A `requires_review` tag never propagates from model evidence alone, at any agreement level.

AC3-006 - Session context propagates only when the relevant value and propagation flag are both supplied: `--session-subject` with `--allow-session-subject-propagation`, `--session-habitat` with `--allow-session-habitat-propagation`, or `--session-event` with `--allow-session-event-propagation`; propagated context is recorded as `user_session_context`.

AC3-007 - `apply-session` writes from an existing session file without model runs, rendering, subject isolation, or raw sidecar rewrites, and refuses assets whose identity hash changed unless `--allow-stale` is explicit.

AC3-008 - A vocabulary with a duplicated synonym, duplicated canonical path, orphan parent, pipe-bearing flat keyword, or hierarchy cycle is rejected at load with a precise error listing.

AC3-009 - Existing XMP sidecar metadata remains semantically preserved, verified by the owned parser, metadata snapshot comparison, and unmanaged-content fingerprint.

AC3-010 - The session report explains what was normalized, propagated, and skipped, with the governing rule named in each case.

AC3-011 - An unmatched session subject, habitat, or event value is rejected by default and exported only as an unnormalized flat user keyword under `write-unnormalized`.

AC3-012 - Hierarchy-aware counting demonstrably increases an ancestor's agreement frequency when descendants are observed.

AC3-013 - Normalized hierarchical output uses vocabulary `canonical_path` values and never exports raw model text containing `|`.

AC3-014 - A malformed existing XMP sidecar fails closed as `E_XMP_PARSE_FAILED`; an unsupported but well-formed RDF/XMP shape fails closed as `E_XMP_UNSUPPORTED_RDF`; neither failure modifies the existing sidecar or source image.

AC3-015 - Exported normalized sidecars can be read back by the owned XMP parser, and release smoke checks confirm Lightroom Classic and Capture One can import the written flat keywords.

AC3-016 - Phase 3 does not require, invoke, package, or report an ExifTool runtime dependency.

AC3-017 - `--session-only` produces a valid session and report while creating or modifying no `.xmp` files.

AC3-018 - Same-base-name RAW+JPEG groups produce exactly one normalized XMP write plan per target sidecar, respecting `--pair-scope`.

AC3-019 - When `--vocabulary` is omitted, the bundled starter vocabulary loads through the same validation and hashing path as an explicit vocabulary file.

AC3-020 - `--normalization-mode off`, `single-image`, and `batch-conservative` produce distinguishable, tested behavior: baseline Phase 2-style export policy, per-image canonicalization without propagation, and conservative hierarchy-aware batch propagation respectively.

AC3-021 - `--file-list` accepts a newline-delimited source-image list, resolves relative paths predictably, collapses duplicates with a warning, and rejects invalid combinations with positional input or `--from-json`.

AC3-022 - `apply-session` rejects normalization-decision flags and writes only from stored session decisions, subject to explicit relocation, source-verification, conflict-policy, backup, dry-run, and stale-session overrides.

AC3-AFF-001 - Two files close in capture time, GPS, filename sequence, and camera/lens produce a strong edge at or above `0.75` under the conservative profile.

AC3-AFF-002 - Two files in the same folder with the same camera/lens but distant capture time, distant GPS, and distant filename sequence produce an edge below the propagation threshold.

AC3-AFF-003 - Camera/lens match alone never creates propagation eligibility.

AC3-AFF-004 - Missing GPS does not fail affinity scoring; time and filename/list adjacency can still create a strong edge, and the report records GPS as missing.

AC3-AFF-005 - Present but distant GPS lowers affinity rather than being ignored.

AC3-AFF-006 - A broad auto-apply tag propagates to a high-affinity neighbor when local weighted agreement and supporting evidence thresholds are met.

AC3-AFF-007 - The same broad tag does not propagate to a low-affinity same-folder file.

AC3-AFF-008 - A mid-specific tag requires stronger local evidence than a broad tag.

AC3-AFF-009 - A `requires_review` tag does not propagate from model evidence even inside a strong local cluster.

AC3-AFF-010 - Direct conflicting evidence on the target asset blocks neighbor propagation.

AC3-AFF-011 - RAW+JPEG same-base-name groups are collapsed to one normalization node and do not double-count support.

AC3-AFF-012 - The normalization session records affinity inputs, edge scores, component scores, score bands, local weighted agreement, support mass, eligible mass, supporting-neighbor counts, and governing decision rules.

AC3-AFF-013 - `apply-session` uses stored normalization decisions and source identity verification; it does not rerun model analysis, re-extract candidates, or recompute affinity.

AC3-AFF-014 - GPS coordinates, capture times, camera/lens identifiers, filenames, and file-list adjacency are never exported as inferred XMP keywords solely because they were used for affinity scoring.

AC3-AFF-015 - Decision-contributing affinity edges are always auditable. Configuration either enforces the storage threshold at or below the consensus threshold or stores every edge that affected a decision.

AC3-AFF-016 - Local conflict mass blocks propagation when the configured mass and agreement thresholds are met, and the report distinguishes target direct conflicts from neighborhood conflict mass.

AC3-AFF-017 - Affinity score rounding, score bands, edge sorting, neighbor pruning, and tie-breaks are deterministic across repeated runs over the same fixtures.

AC3-AFF-018 - Batches above the scalability threshold use deterministic candidate-neighbor generation and pruning rather than requiring an unbounded all-pairs graph.

AC3-023 - The ordered normalization decision pipeline is implemented and tested so direct observations, local propagation, global backstops, user context, final conflicts, session writing, and XMP export occur in the specified order.

AC3-024 - `direct_apply_policy` and `auto_apply_allowed` are tested independently: direct model observations obey direct policy, while propagation obeys auto-apply and propagation-scope policy.

AC3-025 - `--session-habitat` and `--session-event` match vocabulary entries, handle unknown values under `--unknown-session-context-policy`, record user provenance, apply only to non-conflicting assets, and do not infer named locations from GPS.

AC3-026 - `--allow-specific-tags` cannot override controlled vocabulary `requires_review`, `direct_apply_policy`, `auto_apply_allowed`, `propagation_scope`, `specificity`, or conflict rules.

AC3-027 - Dry-run, session-only, and apply-session modes produce exactly the artifacts specified in FR3-040 and do not create backups, modify sidecars, or run XMP validation when the truth table says they must not.

AC3-028 - Confidence bands are ordinal filters only. After thresholding, surviving observations contribute one unit of support; confidence, source field, and input role are recorded for provenance and tie-breaking.

AC3-029 - Global backstop propagation requires threshold percentage, minimum eligible asset count, and minimum supporting asset count; a tiny folder cannot satisfy global propagation by percentage alone.

AC3-030 - The bundled starter vocabulary contains the minimum entries and sample policy fields listed in Appendix A, loads through the same validation path as user JSON, and is sufficient for the Phase 3 fixture suite.

AC3-031 - Normal reports and sessions redact or derive sensitive affinity metadata by default: no exact GPS coordinates, exact capture timestamps, or raw camera serial strings are persisted unless explicit debug/audit configuration is enabled.

## 12. Appendix A - Bundled Starter Vocabulary Minimum Set

The bundled starter vocabulary is deliberately small. It exists to make Phase 3 useful out of the box and to provide stable fixture targets. It is not a complete taxonomy and shall not pretend to settle rare-species, named-person, or exact-location review policy.

Minimum required canonical paths:

```text
Subject|Wildlife
Subject|Wildlife|Birds
Subject|Wildlife|Birds|Herons and Egrets
Subject|Wildlife|Birds|Raptors
Subject|Wildlife|Mammals
Subject|Wildlife|Reptiles and Amphibians
Subject|Plants
Subject|Plants|Flowers
Subject|Architecture
Subject|Landscape
Subject|People
Habitat|Wetland
Habitat|Beach
Habitat|Forest
Habitat|Urban
Habitat|Garden
Scene|Outdoor
Scene|Indoor
Behavior|Flying
Behavior|Perching
Behavior|Feeding
Behavior|Resting
Objects|Vehicle
Objects|Building
Workflow|Needs Review
Workflow|AI Suggested
```

Representative entry shape:

```json
{
  "canonical_path": "Subject|Wildlife|Birds",
  "flat_keyword": "Birds",
  "namespace": "Subject",
  "parent_path": "Subject|Wildlife",
  "synonyms": ["bird", "avian"],
  "requires_review": false,
  "direct_apply_policy": "allow",
  "auto_apply_allowed": true,
  "propagation_scope": "local",
  "specificity": "broad",
  "mutually_exclusive_group": null,
  "export_flat_keyword": true,
  "export_hierarchical_keyword": true,
  "notes": "Broad starter taxonomy ancestor; safe for local affinity propagation."
}
```

Review-sensitive example:

```json
{
  "canonical_path": "People|Named Person",
  "flat_keyword": "Named Person",
  "namespace": "People",
  "parent_path": "People",
  "synonyms": [],
  "requires_review": true,
  "direct_apply_policy": "withhold",
  "auto_apply_allowed": false,
  "propagation_scope": "none",
  "specificity": "specific",
  "mutually_exclusive_group": null,
  "export_flat_keyword": true,
  "export_hierarchical_keyword": true,
  "notes": "Placeholder demonstrating that named people are never auto-exported from model evidence."
}
```

Starter vocabulary acceptance fixture requirements:

1. At least one synonym collision fixture must fail with `E_VOCABULARY_INVALID`.
2. At least one hierarchy orphan and one cycle fixture must fail with `E_VOCABULARY_INVALID`.
3. At least one broad local-propagation fixture must use `Subject|Wildlife|Birds`.
4. At least one habitat session-context fixture must use `Habitat|Wetland`.
5. At least one direct-apply withheld fixture must use a review-sensitive placeholder.

## 13. Future Groundwork

Phase 3 establishes the decision layer the GUI consumes directly:

- JSON vocabulary format, schema, integrity rules, and hash identity;
- synonym canonicalization with defined folding;
- controlled hierarchical paths safe for XMP export;
- per-image versus batch-level candidate distinction with hierarchy-aware and metadata-affinity-weighted statistics;
- affinity graph records over capture time, GPS, filename sequence, file-list adjacency, and camera/lens metadata;
- metadata-affinity graph construction, scalable candidate-neighbor generation, proximity-weighted local consensus, local conflict mass, and global-consensus backstop policy;
- provenance-aware normalization separating model evidence from user evidence;
- session files openable by the GUI and bound to asset identities;
- normalized XMP write plans consumed by `OwnedXMPSidecarEngine`;
- policy-driven direct apply and propagation via `direct_apply_policy`, `auto_apply_allowed`, propagation scopes, specificity classes, and affinity thresholds;
- conflict detection via siblings and mutual-exclusion groups;
- semantic XMP validation outcomes suitable for GUI display;
- batch-level reports and summaries.

Phase 4 shall turn this into an interactive review and correction workflow over the same engine.

## 14. Appendix B - Document Traceability Expectations

The companion `agent_docs/cli-implementation-notes.md` shall maintain a traceability matrix mapping requirement families to their primary implementation modules, milestones, and automated test families. This appendix makes that traceability expectation part of the requirements, while `cli-implementation-notes.md` carries the detailed matrix.

Minimum coverage:

```text
FR3-CLI-*            command/config validation and invocation tests
FR3-ORD-*            normalization decision-order tests and integration fixtures
FR3-001..008         vocabulary model, loader, validator, direct-apply, and starter-vocabulary tests
FR3-009..020         candidate observation, canonicalization, consensus, and decision-engine tests
FR3-AFF-*            affinity input, scorer, graph, local-consensus, conflict-mass, privacy, and graph-scaling tests
FR3-021..026         subject/habitat/event session-context resolver tests
FR3-027..030         session schema, stale-session, privacy, and apply-session tests
FR3-031..040         XMP plan adapter, report, dry-run/session-only/output-artifact, and export tests
AC3-* / AC3-AFF-*    end-to-end acceptance fixtures and release smoke evidence
```

When future revisions add, remove, or rename requirement IDs, the traceability matrix in `agent_docs/cli-implementation-notes.md` shall be updated in the same documentation pass.

## Reference Basis

This document incorporates the Reference Basis of Phase 1 v0.4 and Phase 2 v0.5. Items load-bearing for this phase specifically:

- Adobe XMP specifications: https://developer.adobe.com/xmp/docs/xmp-specifications/
- W3C RDF/XML syntax and RDF container vocabulary: https://www.w3.org/TR/rdf-syntax-grammar/
- Apple Foundation XML document processing: https://developer.apple.com/documentation/foundation/xmldocument
- IPTC Photo Metadata Standard 2025.1, Keywords implemented as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic XMP sidecar behavior and metadata actions: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html and https://helpx.adobe.com/lightroom-classic/help/advanced-metadata-actions.html
- Capture One XMP sidecar behavior and Auto Sync Sidecar XMP settings: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
