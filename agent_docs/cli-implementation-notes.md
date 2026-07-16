# CLI Implementation Notes (Phases 1–3)

Durable implementation details extracted from the archived Phase 1–3 implementation plans (agent_docs/archive/). Requirements live in docs 01/02/03; invariants in invariants.md; module map in architecture-map.md. This file holds what the archived plans uniquely documented: the one open work item (Milestone 9), shipped defaults, conventions, boundary rules, and the live Phase 3 traceability matrix.

## Open item: Milestone 9 calibration and quality review

**This is the only open Phase 1–3 work item.** It gates overall release signoff (README:24): either the Milestone 9 evidence is archived, or an explicit release note documents each deferred check with reason and residual risk. Everything else in Phases 1–3 (Phase 1 M0–9a, Phase 2 M0–10, Phase 3 M0–11) is complete — do not reopen it (invariant 17).

The remaining evidence: full benchmark matrix, final profile/`keep_alive`/`stage_concurrency` defaults, foreground-mask failure classification, tag-quality review, multi-subject instance-selection spot checks, rights-cleared format coverage or documented deferral, and final AC1-001 through AC1-015 acceptance evidence.

Benchmark axes (Phase 1 plan §13):

1. Whole-image render time by file type (NEF, RAF, JPEG, HEIC, TIFF).
2. Two-resolution isolation chain cost vs the rejected single-resolution chain, by image size.
3. Model runtime per input role; `keep_alive` on vs off (per-image reload tax).
4. Thinking off vs on: latency and tag-quality delta — confirming the FR1-030c default with data rather than assertion.
5. Effective input resolution: tag quality at long edges 1024 / 1536 / 2048 (and higher if accepted) for both roles, testing the hypothesis that whole-image quality saturates while subject-isolated quality keeps improving — the empirical case for the two-pass design.
6. Foreground-mask failure rate by subject class: distant birds, birds in flight, small wildlife, cluttered scenes, low-contrast subjects (quantifying the FR1-026/027 failure path).
7. Instance-selection accuracy on multi-subject frames (manual spot check against recorded instances).
8. JSON validity, repair success rate, and schema-violation rates at temperature 0 with the `format` schema active.
9. Memory pressure and stage-concurrency sweep on the target M4 Pro 48 GB machine: render concurrency 2/4/6/8 against the serialized model stage.
10. Source-hash policy cost: `sha256` vs `fast` across a 2,000-image folder.

Output layout:

```text
benchmarks/milestone9a-YYYY-MM-DD-HHMMSS/
  benchmark-results-YYYY-MM-DD-HHMMSS.md
  benchmark-results-YYYY-MM-DD-HHMMSS.json
```

The harness is `aisidecar benchmark` (Milestone 9a, implemented): it builds `.build/release/aisidecar`, invokes `analyze` per spec, aggregates sidecar/model-run timings, verifies no `.xmp` files were produced, and removes scratch inputs and per-spec derivative caches. Calibration updates the default `ModelInputProfile`, the default `keep_alive`, and the default stage concurrency in the shipped configuration.

## Shipped defaults

Default model input profile (to be justified empirically in Milestone 9, not assumed — vision-language models tile and downsample internally, so effective input resolution may sit below these ceilings):

```json
{
  "name": "gemma4-26b-default",
  "max_long_edge": 2048,
  "max_total_pixels": 4194304,
  "color_space": "sRGB",
  "preferred_whole_image_format": "jpeg",
  "jpeg_quality": 0.9,
  "preferred_subject_format": "jpeg-neutral-matte",
  "matte_rgb": [128, 128, 128],
  "allow_upscale_subject_by_default": false
}
```

Derivative cache: default path `~/Library/Caches/aisidecar/derivatives` (see architecture-map.md artifacts table), default cap **20 GiB**, manifest-backed LRU eviction, keys `<source-sha256>-<recipe-version>-<role>.<ext>`. Overridable via `derivative_cache_dir` / `derivative_cache_size_bytes` config or `AISIDECAR_*` env. Only model-input roles (`whole_image`, `subject_isolated`) are cached; the cache index manifest is excluded from role artifacts. `clear_derivative_cache_on_start` / `clear_derivative_cache_after_success` are resolvable via config, env, and CLI flags; post-success clearing runs only when the invocation has no failed records and was not interrupted. The CLI and GUI coordinate through a persistent flock file. Encode/hash is staged outside that flock; final rename and manifest mutation occur under it. Returned artifacts carry shared inode leases, so cross-process eviction and purge skip active inputs and the configured cap is restored at consumer teardown.

Model run option defaults: temperature 0, recorded seed, thinking explicitly disabled and recorded, `keep_alive`
30m refreshed per request, timeout 180 s, 2 additional attempts on timeout/transport/HTTP 5xx errors, and
`response_repair_attempts` 1. Timeout and retry limit resolve through CLI > environment > config > built-in default;
HTTP 4xx fails immediately and a malformed HTTP-success envelope has its own single decode retry.

## Image-quality assessment contract

`analyze --assess-quality` selects the v1.6.0 combined tagging-and-quality
contract; the analyze-and-write shape of `write-xmp` accepts the same flag.
`quality_assessment` resolves through the normal CLI > environment > config >
built-in precedence chain, and the resulting raw sidecar always records
`run_configuration.task_profile` (`tagging` or `tagging_with_quality`). An
absent flag preserves v1.5.0 tagging. This selection never makes `analyze`
write XMP; `write-xmp` remains the only command shape here that can export XMP.
The standalone `quality_only` profile and `assess-quality` subcommand belong to
the quality-only pipeline. `aisidecar assess-quality <input>` reuses the render,
subject-isolation, model-runtime, interruption, and raw-sidecar guardrails from
`AnalyzePipeline`, forces `task_profile = quality_only`, suppresses GPS/model
input context, and writes `.quality.ai.json` sidecars. Folder runs use
`quality-progress-*` and `quality-summary-*` artifacts. Tagging sidecars for the
same source are separate and are never treated as existing quality output.

## Implementation conventions

- **Subject-cache keys include isolation settings.** Subject derivative cache keys include the render recipe plus `subject_crop_margin_fraction`, `subject_merge_dominance_threshold`, and matte RGB, so config changes can never reuse stale crops.
- **Prompt hashing** is the SHA-256 of the exact LF-normalized prompt text with one trailing newline; `PromptRegistry` parses `PROMPT_VERSION` from the same text.
- **Model-stage role ordering** is `whole_image` then `subject_isolated`; model calls are serialized single-flight while render/isolation preparation runs in a bounded task group.
- **`stage_concurrency = 1` selects a lower-memory serial path** that avoids rendering the next source while the current model request is active. Default is physical performance cores with an active-processor fallback; the resolved value is recorded in sidecar provenance.
- **Derivative-cache reads are leased.** Every `cachedRecord`/`store` result must be released after its model/export consumer finishes, and every owning pipeline must call `releaseRetained()` at teardown. Never delete an artifact or mutate the manifest outside `DerivativeCache`; purge/eviction require a nonblocking exclusive lock on the artifact inode.

## Boundary rules

- **One extraction path, one write path.** Analyze-and-write (and analyze-and-normalize) call the existing `AnalyzePipeline` and feed the same export planner used by `--from-json`. There are never two candidate-extraction stacks or two XMP write stacks; Phase 3 output is a write plan consumed by the Phase 2 engine (invariants 1 and 4 cover the write-path guarantee).
- **No XML/RDF details in policy modules.** Candidate extraction, grouping, keyword policy, and every `Normalization/` module produce terms, decisions, provenance, and plans only. XML parsing and writing stay behind `MetadataWriteEngine`, so policy behavior is provable with a mock engine and preservation behavior with focused owned-engine fixtures.
- **The owned engine never becomes a general metadata library.** `OwnedXMPSidecarEngine` is limited to `.xmp` sidecar files and the two managed keyword fields (`dc:subject`, `lr:hierarchicalSubject`); it preserves unmanaged content semantically and fails closed on unsupported shapes. Embedded metadata or broader XMP authoring requires new requirements. ExifTool is never a runtime dependency.
- **Keyword safety is a final-boundary rule.** `KeywordSafetyPolicy` distinguishes coordinate/GPS location metadata from a visibly depicted GPS device. Candidate extraction, session preflight, review edits, and final normalized planning all use it; the planner is the independent last guard for imported or hand-edited sessions.
- **Normalization-off is a Phase 2 baseline.** It applies no session context and performs no vocabulary lookup for context values; supplied context is retained only as an `ignored_normalization_off` audit record.
- **Same-major session tolerance fails closed per decision.** Direct per-asset decision enum raw values and unknown JSON fields are preserved through `NormalizationSessionWriter`; review and planning ignore affected decisions. Nested observation/provenance and audit-only enums are still strict decoding boundaries, so a future writer must not add such values within schema major 1 until lossless adapters land.

## Interruption invariant

After any interruption (SIGINT/SIGTERM), an in-flight XMP target is exactly one of: **unchanged**, **fully written and validated**, or **restored from backup** — never partially replaced. Progress JSONL flushes after each completed target; reruns are governed by `--xmp-conflict-policy` with no separate checkpoint format; backups from interrupted runs are listed in the report when one can be written.

Phase 3 extends this to sessions: normalization aggregation and plan construction complete before any XMP write begins (no interleaving per-image analysis, normalization, and per-member writes to the same target); interrupted `--dry-run` and `--session-only` runs leave no `.xmp` files, backups, restores, or partial normalization artifacts; and progress records identify the stage where interruption occurred (input resolution, analysis, vocabulary load, affinity scoring, normalization, plan construction, backup, write, validation, restore, or report writing).

## Owned-engine behavior notes

Fail-closed classification (Phase 2 plan §8):

- Malformed XML → `E_XMP_PARSE_FAILED`.
- Unsupported RDF shapes → `E_XMP_UNSUPPORTED_RDF`: managed keywords expressed as attributes, duplicate managed properties, managed fields split across multiple `rdf:Description` elements, or managed keyword content that is not an `rdf:Bag`.
- Both map to structured errors with bounded diagnostic excerpts; neither modifies source files or existing sidecars.

Write pattern: engine writes go through `AtomicFileWriter.writeFile` — the merged sidecar is written to a temporary file, **validated as readable before** atomic replacement of the target. The parser accepts either an `x:xmpmeta` wrapper or a direct `rdf:RDF` root; the merger preserves existing keyword spelling/order, appends planned terms in plan order, and de-duplicates case-insensitively. With multiple writable descriptions, selection is managed-field owner → exact decoded source-filename `rdf:about` → empty `rdf:about` → first description; raw suffix matching is forbidden.

## Provenance without retained raw sidecars

Under `--no-write-ai-json`, extraction may use in-memory raw sidecar records, but `CandidateProvenance` carries model, model digest, runtime, runtime version, prompt version, prompt hash, and response schema version — so XMP export reports remain fully auditable even when the `.ai.json` is not retained. Derivative-cache clear-after-success is deferred until **both** analysis and XMP export succeed; XMP failure must not delete derivatives when the overall invocation failed.

## Phase 3 traceability matrix (live copy)

Doc 03 Appendix B mandates this matrix be maintained; this file is its home. Maintenance rule (from the archived plan): when a requirement ID is added or renamed after v0.7, this matrix shall be updated in the same commit as the requirement change.

```text
Requirement family        Primary modules                                           Primary tests                                      Milestone
FR3-CLI / FR3-ERR         NormalizeCommand, ApplySessionCommand, input resolver       NormalizationInvocationTests, FileListInputResolverTests  M0/R4
FR3-001..008              VocabularyLoader, VocabularyEntry, DirectApplyPolicy       VocabularyLoaderTests, DirectApplyPolicyTests     M1
Appendix A / AC3-030      DefaultVocabulary, bundled Vocabularies resource           StarterVocabularyTests                            M1
FR3-ORD-001..005          CandidateCanonicalizer, BatchConsensusEngine               BatchConsensusEngineTests, CandidateCanonicalizerTests  M2-M5
FR3-009..020              CandidateCanonicalizer, VocabularyIndex                    CandidateCanonicalizerTests, VocabularyIndexTests  M3-M5
FR3-AFF-003a/b            AssetAffinityInputExtractor                               AssetAffinityInputTests                           M4
FR3-AFF-004..012          Affinity scorers, AssetAffinityProfile                    AssetAffinityScorerTests                          M4
FR3-AFF-013a/c            AffinityScoreFormatter, AssetAffinityGraph                AssetAffinityGraphTests                           M4
FR3-AFF-013b              CandidateNeighborGenerator                                AffinityNeighborCandidateTests                    M4
FR3-AFF-014..016          BatchConsensusEngine (local weighted consensus)            LocalWeightedConsensusTests                       M4
FR3-AFF-017a/b            BatchConsensusEngine (local conflict mass)                 LocalConflictMassTests                            M4
FR3-013e/f                BatchConsensusEngine (global backstop)                     GlobalBackstopConsensusTests                      M4
FR3-AFF-020..022          AssetAffinityInputExtractor redaction, session privacy record  NormalizationSessionTests, NormalizationReportTests  M4/M6
FR3-021..026g             CandidateCanonicalizer, BatchConsensusEngine, KeywordSafetyPolicy  SessionContextPolicyTests, CandidateCanonicalizerTests  M4/R4
FR3-027..030k             NormalizationSessionReader/Writer, SessionReview           NormalizationSessionTests, SessionReviewTests      M2/M7/R4
FR3-031..039              NormalizedXMPChangePlanner, XMPExportPipeline reuse        NormalizedXMPChangePlanTests, NormalizeAndWritePipelineTests  M5-M8/R4
FR3-040..042              NormalizationArtifactPlanner                              NormalizationArtifactPlannerTests                 M6-M7
AC3-AFF-001..018          Affinity graph, consensus, conflict, privacy modules      Affinity and consensus fixture suite              M4/M10
Compatibility evidence    OwnedXMPSidecarEngine through Phase 2 writer path         Smoke checklist and release evidence              M11
```

## Design rationale (merged from the three plans' Risks sections)

- **Digest, not tag, is model identity.** Ollama tags are mutable references; the model digest and runtime version are recorded in provenance so "same tag, different model" is detectable after the fact.
- **Confidence bands are ordinal, never numeric.** Bands are a schema field, not an architecture — widening the enum is an additive minor-version change. Phase 3 uses them only as filters/tie-breakers and never introduces numeric model confidence.
- **Two-pass (whole + subject) design is an empirical hypothesis**, to be confirmed by Milestone 9 axis 5: whole-image quality saturates with resolution while subject-isolated quality keeps improving.
- **The model stage is serialized** — unlikely to underutilize a 26B-class model on 48 GB, and stage concurrency is configurable if data says otherwise. The Ollama capability preflight also stays serial (invariant 15).
- **Memory is bounded by construction:** native full-resolution renders live in memory only for the active worker, no full-res TIFF is cached, and `stage_concurrency` caps concurrent workers.
- **Recorded-fixture runners catch drift:** structured-output or thinking-mode behavior shifts across Ollama/model updates surface in fixture tests before real batches.
- **Foreground-mask failures are structured and quantified**, not silently substituted: per-image error, whole-image mode unaffected, failure rate measured by subject class in Milestone 9.
- **XMP preservation is semantic, not byte-for-byte.** Tests compare parsed metadata meaning and unmanaged-content fingerprints, never textual equality — owned XML serialization is free to change formatting or prefix order.
- **Specific-tag conservatism:** common-name species terms export by default; binomials, named places/people/events, and non-species exact IDs require `--allow-specific-tags` (a Phase 2 heuristic replaced by Phase 3 vocabulary policy, which `--allow-specific-tags` cannot override).
- **Source identity verification defaults to `fail`** so `--from-json` never tags an image that changed after analysis; `warn`/`skip` are explicit, recorded choices.
- **RAW+JPEG groups get exactly one plan and one write per target XMP**, resolved before writing, so pairs cannot overwrite each other's sidecar.
- **Phase 2 writes one-level hierarchical mirrors only** — it never invents parent paths; controlled hierarchy construction is Phase 3 vocabulary territory (only vocabulary `canonical_path` values may introduce `|`).
- **Local-first affinity, not folder voting:** propagation defaults to metadata-affinity local consensus with support-mass/agreement/neighbor thresholds and conflict-mass blocks, so a wrong tag cannot sweep an unrelated part of a folder.
- **Gear is a boost only.** Camera/lens match without a primary signal (time, GPS, filename sequence, file-list adjacency) yields zero affinity and `blocked_gear_only_affinity`.
- **The global backstop needs minimum eligible/supporting counts**, not just a percentage, so it cannot fire in a tiny folder.
- **Vocabulary matching is exact-first with guarded fallbacks** (invariant 10) — no stemming, no diacritic folding — so synonyms cannot map sideways/downward to false specificity. Ambiguous primary aliases terminate lookup; punctuation or singular/plural fallback cannot rescue them. Separator-fold collisions count canonical, flat, and synonym owners equally.
- **`apply-session` is deliberately narrow:** stored decisions are authoritative; it verifies source identity (stale fails by default, `--allow-stale` is invocation-only and recorded), recomputes target paths only, and merges against the current on-disk XMP at write time — never a stale session copy, and never recomputing vocabulary, extraction, affinity, or consensus.
- **Privacy by default in artifacts:** sessions/reports persist derived distances/scores and hashed camera serials; exact GPS coordinates and raw serials require explicit debug/audit configuration.
- **Fixture-first milestone ordering:** each phase implemented its from-json/offline path before live-model integration, keeping the first half of every phase deterministic and offline.

## Phase 3 Normalization subsystem map (condensed)

architecture-map.md's `Normalization/` row lists the key types; this adds the per-subsystem file breakdown the archived plan carried. All files live in `Sources/AISidecarCore/Normalization/` unless noted.

| Subsystem | Files | Responsibility |
|---|---|---|
| Vocabulary | `VocabularyDocument`, `VocabularyEntry`, `DirectApplyPolicy`, `VocabularyLoader`, `VocabularyValidator`, `VocabularyIndex`, `VocabularyTextFolder`, `DefaultVocabulary` (bundled `Vocabularies/` resource) | `ai-sidecar-vocabulary/1.0` load + SHA-256 identity; integrity checks (uniqueness, tree acyclicity, collisions); NFC/case/whitespace folding with ambiguity-guarded fallback aliases; direct-apply vs propagation policy defaults |
| Session & inputs | `NormalizationInputResolver`, `NormalizationSessionDocument`, `NormalizationSourceAsset`, `Reporting/NormalizationSchemaIdentifiers`, `NormalizationArtifactPlanner` | folder/file-list/from-json input resolution with symlink-resolved physical identity; `ai-sidecar-normalization/1.0` session bound to source identity hashes; dry-run/session-only/apply-session artifact truth table |
| Affinity | `AssetAffinityInputs`, `AssetAffinityInputExtractor` (incl. redaction/hashing), `AssetAffinityProfile`, `CaptureTimeAffinityScorer`, `GPSAffinityScorer`, `FilenameSequenceAffinityScorer`, `CameraLensAffinityScorer`, `AssetAffinityGraph`, `CandidateNeighborGenerator`, `AffinityScoreFormatter` | metadata extraction with redaction/hashing; named profiles (conservative/balanced/aggressive); deterministic decay scorers; bounded neighbor windows for large batches; six-decimal rounding, score bands, stable ordering |
| Consensus & decisions | `CandidateObservation`, `CandidateCanonicalizer`, `PerAssetNormalizationDecision`, `LocalWeightedConsensusRecord`, `BatchConsensusEngine` (FR3-ORD stage ordering, local weighted consensus, conflict mass, global backstop, session-context application) | observation extraction and canonicalization; support/eligible mass, local agreement, conflict-mass blocks; hierarchy-aware counts and global backstop minimums; user session subject/habitat/event evidence; explanatory clusters (audit-only) |
| Plan & apply | `NormalizedXMPChangePlanner`; `Pipeline/NormalizePipeline`, `NormalizeAndWritePipeline`, `ApplySessionPipeline` (incl. session staleness checks), `AnalyzeAndNormalizePipeline`, `NormalizationXMPExecutionRecorder`; `Reporting/NormalizationProgressLog`, `NormalizationReport`, `NormalizationSummary` | adapt approved decisions into Phase 2 `XMPChangePlan`s; session staleness checks; pipeline entry points (see architecture-map.md); JSONL progress, `ai-sidecar-normalization-report/1.0`, Markdown summary |
