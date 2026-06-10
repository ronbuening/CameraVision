# Implementation Plan - Phase 1 CLI Raw JSON Sidecar Generator

Version: 0.6
Date: 2026-06-10
Supersedes: 0.1, 0.2, 0.3, 0.4, 0.5
Implements: Phase 1 Requirements v0.2 (`01-cli-raw-json-sidecar-requirements.md`)
Binary: `aisidecar` (subcommand: `analyze`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15, Swift 6 strict concurrency
Default model: `gemma4:26b-a4b-it-qat` (installed locally; verified at startup per FR1-030b)
Runtime: Ollama local HTTP API, `POST /api/chat`

Traceability in this plan points at the v0.2 requirement IDs (PW-xxx, FR1-xxx). The review-finding IDs used in plan v0.2 are retired now that the findings are folded into the requirements themselves.

## 0. Current Implementation Status

Phase 1 Milestones 0-4.5 are implemented. The current `aisidecar analyze` path scans files, computes source identities, resolves raw `.ai.json` sidecar destinations, renders full-resolution and whole-image derivatives, isolates foreground subjects through the two-resolution Apple Vision/Core Image chain, records model input profile, derivative provenance, and subject-isolation provenance, applies `--existing`, writes folder-run JSONL progress logs and batch summaries, and handles interruption through the analyze shell pipeline. The diagnostic `--export-model-inputs` mode exports only the rendered model-input images into a requested folder with a manifest for visual validation before model integration. It does not yet call Ollama or write XMP.

Latest verification for this baseline:

```text
swift test                                      83 tests, 0 failures
swift run aisidecar analyze --help             passed
```

The next implementation unit is Milestone 5: Ollama Vision Model Client.

## 1. Implementation Position

The program is a Swift Package Manager project. The decisive reason is unchanged: the subject-isolation requirement needs first-class access to Apple Vision and Core Image, and the Apple image pipeline is cleaner, safer, and more maintainable in Swift than through Python wrappers.

Two structural decisions, now mandated by the requirements rather than merely recommended:

1. **Core library from the first commit** (PW-002). Every capability lives in `AISidecarCore`; the executable is argument handling and nothing else. Phase 4's shared-engine requirement is satisfied by construction because the engine never exists in any other shape.
2. **One binary, subcommands per phase** (PW-001). Phase 1 ships `aisidecar analyze`; Phase 2 adds `write-xmp`; Phase 3 adds `normalize` and `apply-session`. Shared flags are defined once (PW-004/005) in a `SharedOptions` type that every subcommand composes.

The model runtime stays behind the `VisionModelRunner` protocol (FR1-031), with mock and recorded-fixture runners implemented in the same milestone as the live runner so nothing downstream is ever blocked on, or untested without, a live Ollama instance.

macOS 15 minimum (PW-003) means the modern Swift Vision API (`GenerateForegroundInstanceMaskRequest` and `ImageProcessingRequest`-style async APIs) is used directly; no `VN`-prefixed compatibility paths are written.

## 2. Technical Stack

```text
Language:
  Swift 6, strict concurrency, async/await throughout

Project system:
  Swift Package Manager
  Targets: AISidecarCore (library), aisidecar (executable), AISidecarCoreTests

CLI parsing:
  Swift ArgumentParser; subcommand structure with composed SharedOptions

Image loading/rendering:
  Foundation, Image I/O, Core Image
  CIRAWFilter for RAW formats (FR1-016)
  Orientation baking and sRGB conversion in RenderRecipe (FR1-016a/b)

Subject isolation:
  Vision foreground instance mask request (macOS 15 Swift API)
  Core Image blend-with-mask, crop, matte compositing (FR1-019/021a-d)

Model runtime:
  URLSession against Ollama:
    POST /api/chat   (base64 images, format = JSON Schema)   FR1-030a
    GET  /api/tags   (startup tag verification)              FR1-030b
    GET  /api/version (runtime provenance)                   PW-013

Hashing:
  CryptoKit SHA-256: source identity (FR1-006a), derivatives (FR1-017),
  prompts (FR1-046), cache keys (FR1-018a)

Serialization:
  Codable JSON; JSONL progress log (FR1-012a)

Configuration:
  JSON config + AISIDECAR_* env + flags, precedence per PW-007

Testing:
  XCTest; MockVisionModelRunner; RecordedFixtureRunner; golden sidecars
```

## 3. Repository Layout

This section separates the current Milestone 4 layout from planned Phase 1
additions so file names remain accurate while the later milestones stay visible.

```text
CameraVision/
  Package.swift
  Sources/
    AISidecarCore/
      Configuration/
        AppConfig.swift                 // PW-006/007 resolution + validation
        ConfigurationResolver.swift
        RunConfiguration.swift          // PW-008: resolved values for provenance
      Errors/
        SidecarError.swift              // PW-009/010 enumerated codes
      FileScanning/
        ImageScanner.swift              // FR1-001..005, relative paths FR1-006b
        SupportedImageType.swift
        SourceImage.swift
      Identity/
        SourceIdentity.swift            // FR1-006a sha256 / fast policies
      Rendering/
        ImageRenderer.swift             // full-res render retention FR1-017a
        RenderRecipe.swift              // orientation + sRGB FR1-016a/b
        ModelInputProfile.swift
        DerivativeCache.swift           // FR1-018a content-addressed, LRU
      SubjectIsolation/
        SubjectIsolationService.swift   // two-resolution chain FR1-021a-d
        InstanceSelectionPolicy.swift   // FR1-019a-c selection + merge
        AppleVisionForegroundMaskProvider.swift
        MaskGeometry.swift
        SubjectIsolationTypes.swift
      Sidecars/
        RawJSONSidecar.swift            // FR1-039..045
        RawJSONSidecarWriter.swift      // atomic writes FR1-012d, --existing FR1-010
        SidecarNaming.swift             // FR1-008/009 tree mirroring + collisions
        AtomicFileWriter.swift           // shared temp-file + rename helper
      Reporting/
        ProgressLog.swift               // FR1-012a JSONL
        BatchSummary.swift              // FR1-012 derived from log
        Logger.swift                    // text + json formats
      Pipeline/
        AnalyzeShellPipeline.swift      // scanner -> renderer -> isolation -> sidecar path
        InterruptionMonitor.swift       // SIGINT/SIGTERM interruption state
    AISidecarCLI/
      AISidecarCommand.swift
      SharedOptions.swift               // PW-004 glossary, composed by all subcommands
      AnalyzeCommand.swift
  Tests/
    AISidecarCoreTests/                 // suite in Section 12
```

Planned Phase 1 additions:

```text
Sources/AISidecarCore/
  ModelRuntime/
    VisionModelRunner.swift             // protocol, FR1-031
    OllamaVisionRunner.swift            // FR1-030a-f
    MockVisionModelRunner.swift
    RecordedFixtureRunner.swift
    ModelRunOptions.swift               // temp, seed, thinking, keep_alive, timeout
    PromptRegistry.swift                // FR1-046 versioned + hashed prompts
    ResponseSchemas.swift               // FR1-045 two schemas as format payloads
  Pipeline/
    AnalyzePipeline.swift               // PW-015 staged concurrency
Fixtures/
  model-responses/                      // recorded real responses incl. malformed
  golden-sidecars/
  README.md
```

## 4. Milestone 0 - Project Scaffold (Implemented)

Tasks:

1. Create the Swift package: `AISidecarCore` library, `aisidecar` executable, test target; macOS 15 platform; Swift 6 strict concurrency.
2. Implement ArgumentParser subcommand wiring with `SharedOptions` carrying the PW-004 glossary (`--mode`, `--existing`, `--recursive`, `--output-dir`, `--model`, `--model-endpoint`, `--profile`, `--config`, `--log-level`, `--log-format`, `--dry-run`, `--debug-derivatives`).
3. Implement the error taxonomy (PW-009/010) as a Swift error type with stable string codes and `stage`/`recoverable` metadata.
4. Implement `Logger` with `text` and `json` output formats; JSON log records share field names with the progress log so the Phase 4 GUI consumes both with one decoder.
5. Implement configuration resolution (PW-006/007) with validation failing as `E_CONFIG_INVALID`; `ResolvedRunConfiguration` snapshots the outcome for provenance (PW-008).
6. CI-runnable `swift test` with zero network dependencies — a property maintained through every later milestone, enforced by the mock/fixture runners.

Exit criteria: `aisidecar analyze --help` prints valid usage; config precedence and error-code serialization have passing unit tests.

## 5. Milestone 1 - Scanner and Source Identity (Implemented)

Tasks:

1. `ImageScanner`: file-or-folder input, `--recursive`, extension filtering (FR1-003), hidden/system/sidecar exclusion (FR1-005), structured `E_UNSUPPORTED_FORMAT` entries (FR1-004).
2. Relative-path recording from the scan root (FR1-006b) — the input to tree mirroring in Milestone 2.
3. `SourceIdentity` (FR1-006a): default `sha256` of full content; `fast` policy (size + mtime + SHA-256 of first/last 4 MiB) selectable in config; policy name recorded with the hash. Hashing runs inside the bounded concurrent stage so it overlaps I/O across files.
4. `--dry-scan`: machine-readable scan listing with identities and relative paths.

```swift
struct SourceImage: Codable, Sendable {
    let path: String
    let relativePath: String
    let fileName: String
    let fileExtension: String
    let fileSize: Int64
    let modifiedAt: Date
    let detectedType: SupportedImageType
    let identity: SourceIdentity   // { policy, sha256 }
}
```

Exit criteria: `aisidecar analyze <folder> --recursive --dry-scan` is correct against a fixture tree containing duplicate basenames in different subfolders, hidden files, and unsupported types.

## 6. Milestone 2 - Sidecar Naming, Output Tree, Progress Log (Implemented)

Tasks:

1. Extension-preserving `.ai.json` naming (FR1-008).
2. `--output-dir` relative-tree mirroring (FR1-009); pre-write collision detection including case-insensitive filesystem collisions, failing affected files with `E_SIDECAR_COLLISION` without aborting the batch (FR1-009a).
3. `--existing <skip|overwrite|fail>` (FR1-010).
4. Atomic writes everywhere: temp file in destination directory, rename (FR1-012d).
5. Minimal raw sidecar record (FR1-039 structure) written before any model integration exists.
6. `ProgressLog` (FR1-012a): append-only JSONL, one flushed record per completed file; `BatchSummary` derived from the log at run end, named `batch-summary-<ISO-timestamp>.json` (FR1-012).
7. Signal handling for the interruption contract (FR1-012b): in-flight sidecar complete or absent, never partial; summary carries `E_INTERRUPTED` when writable. `--existing skip` is thereby the resume mechanism (FR1-012c) with no extra machinery.

Exit criteria: a recursive run over the duplicate-basename fixture tree produces a mirrored raw-sidecar tree, progress log, and summary; `kill -INT` mid-run leaves no partial JSON; an immediate re-run with `--existing skip` touches only the remainder.

Implemented notes:

1. `AnalyzeShellPipeline` was introduced in Milestone 2 for the durable scan/write layer, extended in Milestone 3 through whole-image rendering, and extended in Milestone 4 through subject isolation.
2. Folder runs write `batch-progress-<ISO-timestamp>.jsonl` and `batch-summary-<ISO-timestamp>.json` in `--output-dir` when supplied, otherwise beside the scan root.
3. Single-file runs write only the per-image sidecar and log user-facing status; progress and summary artifacts remain folder-run outputs.
4. `--dry-run` reports intended sidecar actions without writing sidecars, progress logs, or summaries.
5. `SIGINT`/`SIGTERM` are converted into interruption state; completed records are preserved, current writes remain atomic, and the summary records `E_INTERRUPTED` when writable.

## 7. Milestone 3 - Rendering and Derivative Cache (Implemented)

Tasks:

1. `RenderRecipe` implementing the two hard rules:
   - orientation baked into pixels for every derivative, applied value recorded, explicit orientation passed wherever an unbaked image reaches Vision (FR1-016a);
   - sRGB conversion with embedded profile, target space a profile field with sRGB the only shipped default (FR1-016b).
2. `ImageRenderer` producing, per source: the **full-resolution render** retained in cache (FR1-017a) and the model-profile whole-image derivative downsized from it (FR1-013/014). `CIRAWFilter` for RAW; Image I/O elsewhere (FR1-016).
3. Derivative provenance: recipe version, format, dimensions, color space, orientation, SHA-256 (FR1-017).
4. `DerivativeCache` (FR1-018a): keys `<source-sha256>-<recipe-version>-<role>.<ext>`; configurable cap, default 20 GiB, LRU eviction; eviction of full-resolution renders is always safe because they are regenerable from source plus recipe. `--debug-derivatives` copies beside the source (FR1-018).

Default model input profile (calibrated in Milestone 9):

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

Calibration note: vision-language models tile and downsample internally, so the model's *effective* input resolution may sit below these ceilings. The profile is justified empirically in Milestone 9, not assumed.

Exit criteria: a NEF and a JPEG in each of the 8 EXIF orientations produce orientation-correct, sRGB-tagged, profile-conforming derivatives; a second run reuses cached full-resolution renders; cache eviction has tests.

Implemented notes:

1. The sidecar now records the resolved `model_input_profile` object and derivative provenance for `full_resolution` and `whole_image` roles.
2. The derivative cache defaults to `~/Library/Caches/aisidecar/derivatives`, supports `derivative_cache_dir` and `derivative_cache_size_bytes` config/env overrides, and uses a manifest-backed LRU policy.
3. Offline tests cover generated JPEG/PNG/TIFF rendering, all 8 EXIF orientation values, sRGB/profile checks, cache reuse, cache corruption misses, LRU eviction, debug derivative copies, render failure sidecars, and existing-skip render avoidance.
4. RAW/NEF verification remains a manual smoke check unless legally shareable RAW fixtures are added.

## 8. Milestone 4 - Subject Isolation (Two-Resolution Chain, Implemented)

Implements FR1-019 through FR1-027. The chain, in order:

1. Run the Vision foreground instance mask request at analysis resolution — the whole-image derivative is suitable; masking does not need full resolution (FR1-021a).
2. Apply `InstanceSelectionPolicy` (FR1-019a): largest mask area, tie-broken by centroid proximity to frame center. Apply the merge rule (FR1-019b): instances merge when the selected instance's box dominates the union box at the configured ratio (default ≥ 80%) — bodies segmented apart from tails or wingtips are one subject.
3. Map the selected mask and bounding box to the full-resolution render with recorded scale factors (FR1-021b).
4. Expand the box by the margin (default 8% of the longer box side, clamped; FR1-022); crop, blend-with-mask, and composite onto the neutral matte on the full-resolution render (FR1-021c).
5. Downsize to the profile (FR1-021d). Never upscale by default; native-size submission is recorded when the crop is smaller than the profile allows (FR1-024).
6. Record in the sidecar: `instance_count`, selected indices, merge flag, per-instance normalized boxes, analysis resolution, scale factors, margin, matte color, final dimensions (FR1-019c and provenance).

Failure behavior: `--mode subject` writes `E_SUBJECT_ISOLATION_NO_FOREGROUND` with no whole-image substitution (FR1-026); `--mode both` completes the whole-image run and records the failure (FR1-027).

Exit criteria: AC1-005 demonstrated — a fixture frame whose subject occupies ≤ 10% of the long edge yields a subject derivative with measurably more native subject pixels than a crop of the 2048 px derivative could contain; AC1-006 demonstrated on a multi-bird fixture.

Implemented notes:

1. `SubjectIsolationService` runs on the cached whole-image derivative for analysis, maps selected masks and boxes back to the cached full-resolution render, composites onto the profile matte, and writes a cached `subject_isolated` JPEG derivative.
2. `ForegroundMaskProvider` keeps tests deterministic: production uses `AppleVisionForegroundMaskProvider`, while XCTest injects exact mask fixtures. Automated tests therefore remain offline and do not depend on Apple Vision detecting synthetic subjects.
3. Subject derivative cache keys include the render recipe plus subject-isolation settings (`subject_crop_margin_fraction`, `subject_merge_dominance_threshold`, and matte RGB) so config changes cannot reuse stale crops.
4. `subject_crop_margin_fraction` and `subject_merge_dominance_threshold` are available through JSON config and `AISIDECAR_*` environment overrides, validated as finite values in `(0, 1]`, and recorded in `run_configuration`.
5. `RawJSONSidecar.subject_isolation` now decodes to `SubjectIsolationRecord` when isolation runs and encodes `{}` when isolation was not attempted, preserving the Phase 1 top-level schema slot.
6. `--mode subject` records `E_SUBJECT_ISOLATION_NO_FOREGROUND` as a failed per-file result with no whole-image substitution; `--mode both` writes the whole-image derivative set and records the isolation error as recoverable sidecar/progress provenance.
7. Offline tests cover instance selection, merge threshold behavior, edge-clamped margins, no-upscale behavior, no-foreground errors, both-mode recovery, debug derivative copies, and the AC1-005 two-resolution small-subject case. A real-photo Apple Vision smoke check remains recommended before evaluating production mask quality.

## 8.5. Milestone 4.5 - Model Input Export (Implemented)

Purpose: inspect exactly what Milestone 5 will send to the model without writing raw `.ai.json` sidecars or calling Ollama.

Command:

```bash
aisidecar analyze <image-or-folder> --mode both --recursive --existing overwrite --export-model-inputs <destination-folder>
```

Implemented notes:

1. `AnalyzeCommand` routes `--export-model-inputs` to `ModelInputExportPipeline`; `--dry-scan` still exits after scanning, and export mode rejects `--dry-run` and `--debug-derivatives` with `E_CONFIG_INVALID`.
2. Export mode reuses the scanner, `ImageRenderer`, derivative cache, `SubjectIsolationService`, resolved model input profile, `--mode`, `--recursive`, `--existing`, profile, cache, and subject-isolation configuration.
3. The export directory mirrors source relative paths and writes only model-input roles: `whole_image` and/or `subject_isolated`. Full-resolution TIFF renders remain cache-only.
4. A timestamped `model-input-export-<ISO-8601-timestamp>.json` manifest records schema version `ai-sidecar-model-input-export/1.0`, run inputs, resolved profile, per-source export status, output provenance, subject-isolation records, structured errors, and summary counts.
5. `--existing overwrite` replaces export files atomically, `skip` leaves existing export files untouched and records `skipped_existing`, and `fail` records `E_SIDECAR_EXISTS` before rendering affected sources.
6. No XMP, raw JSON sidecars, progress logs, batch summaries, or model runs are written by export mode.
7. Offline tests cover single-file export, recursive tree mirroring, subject-only export, no-foreground subject and both-mode behavior, existing policies, and incompatible flag rejection.

## 9. Milestone 5 - Ollama Vision Model Client

Tasks:

1. `VisionModelRunner` protocol plus `MockVisionModelRunner` and `RecordedFixtureRunner` first (FR1-031) — the live runner is the third implementation, not the first.
2. `OllamaVisionRunner` against `POST /api/chat`: base64 image in the user message's `images` array, response JSON Schema via `format`, one image and one prompt per request (FR1-030a, FR1-032).
3. Startup verification (FR1-030b): resolve `gemma4:26b-a4b-it-qat` (or the configured tag) against `GET /api/tags`; fail fast with `E_MODEL_TAG_NOT_FOUND` listing installed vision-capable tags. Record the model digest and the `GET /api/version` result in provenance (PW-013/014) — the digest, not the tag, is the durable identity even when the tag is known-installed, because tags are mutable references.
4. `ModelRunOptions` (FR1-030c-f): temperature 0, recorded seed, **thinking explicitly disabled** and recorded, `keep_alive` default `30m` refreshed per request, timeout 180 s, 2 retries on timeout/transport errors only — never on JSON or schema failures.
5. Response handling (FR1-041): capture raw text always; strip Markdown fences before parsing (fenced-but-valid JSON is a routine local-model artifact, not an error); classify `E_MODEL_INVALID_JSON` vs `E_MODEL_SCHEMA_VIOLATION`; set `json_valid` accordingly with raw text preserved in both cases.

Interface:

```swift
protocol VisionModelRunner: Sendable {
    func analyze(
        image: DerivativeRef,
        inputRole: AnalysisInputRole,
        prompt: VersionedPrompt,
        schema: JSONSchema,
        options: ModelRunOptions
    ) async throws -> ModelRunResult
}
```

Exit criteria: a derivative round-trips through the live local runner and through the recorded-fixture runner producing identical sidecar `model_runs` entries modulo timing; a deliberately wrong tag fails fast with the installed-tag list (AC1-014).

## 10. Milestone 6 - Prompts and Response Schemas

Tasks:

1. `PromptRegistry` (FR1-046): prompts as versioned resources, each carrying a semantic version and SHA-256 of its text, both recorded per run.
2. Whole-image prompt per FR1-034; subject-isolated prompt per FR1-035/036, stating that background has been removed and must not be inferred.
3. The two response schemas of FR1-045, authored as complete JSON Schema documents — item object shapes, required fields, bounded array and string lengths — because they are the literal `format` payloads: API contracts, not documentation. Candidates carry ordinal bands and evidence (FR1-044); the subject-isolated schema **omits** `scene_context` and `habitat_or_setting`, enforcing FR1-036 structurally.
4. Uncertainty rules in both prompts: prefer the broader correct term over the narrower guess; genuinely uncertain identifications go to `uncertainty_notes`, not `proposed_keywords`.
5. Schema validation tests including fixtures violating each constraint, and the band vocabulary (`high|medium|low`) enforced by enum in the schema.

Exit criteria: both prompts produce schema-valid JSON on representative fixtures via the live runner; the subject-isolated schema structurally rejects habitat fields (AC1-013); prompt hashes appear in sidecars.

## 11. Milestone 7 - Full Analyze Command and Pipeline

Tasks:

1. `AnalyzePipeline` wiring scanner → renderer → isolation → model runner → sidecar writer.
2. Concurrency per PW-015: rendering, isolation, and hashing in a bounded task group (default = physical performance cores, configurable); model requests serialized through a single-flight stage while the render stage works ahead; model kept resident via `keep_alive`.
3. `--mode whole|subject|both`; in `both`, two runs per image with distinct `input_role` values (FR1-033).
4. Per-file console status, JSONL progress records, derived batch summary.
5. Interruption and resume per the Milestone 2 contract, now exercised against the full pipeline.

Example commands:

```bash
aisidecar analyze ./_DSC1234.NEF --mode both

aisidecar analyze ./Birds --recursive --mode both

aisidecar analyze ./Birds --recursive --mode subject --output-dir ./ai-json --existing skip
```

Exit criteria: a mixed RAW/JPEG folder yields one sidecar per processable image, mirrored under `--output-dir`, two model runs per image in `both` mode (AC1-004, AC1-008); interrupt-and-resume completes only the remainder (AC1-011).

## 12. Milestone 8 - Tests and Fixtures

```text
ScannerTests              extension filtering, recursion, hidden-file exclusion,
                          relative-path correctness
SourceIdentityTests       sha256 and fast policies; policy recorded with hash
SidecarNamingTests        extension-preserving naming, tree mirroring,
                          case-insensitive collision detection, --existing behaviors
ModelInputProfileTests    aspect-preserving resize, long-edge and total-pixel
                          enforcement, no-upscale default
RenderRecipeTests         all 8 EXIF orientations baked correctly,
                          sRGB conversion and profile embedding
InstanceSelectionPolicyTests
                          largest-area selection, center tiebreak, merge-rule
                          dominance ratio, multi-instance recording
SubjectIsolationServiceTests
                          deterministic mask fixtures for two-resolution crop
                          mapping, edge-clamped margins, no foreground,
                          no-upscale default, and subject cache separation
JSONSidecarTests          schema version, provenance completeness (digest,
                          runtime version, prompt hash, seed, thinking flag),
                          error-object serialization, unknown-field preservation
                          on rewrite (PW-012)
PromptSchemaTests         both schemas validate; subject schema rejects habitat
                          fields; band enum and bounds enforced
ResponseParsingTests      fence stripping; E_MODEL_INVALID_JSON vs
                          E_MODEL_SCHEMA_VIOLATION; raw-text preservation
GoldenSidecarTests        full pipeline against RecordedFixtureRunner produces
                          byte-stable sidecars (timing fields normalized)
ProgressLogTests          append-only integrity; summary derivation;
                          interruption leaves no partial sidecar
ConfigResolutionTests     flag > env > file > default precedence; E_CONFIG_INVALID
DerivativeCacheTests      content-addressed reuse, LRU eviction at cap,
                          debug-derivative copy semantics
ImageRendererTests        generated JPEG/PNG/TIFF rendering, orientation
                          provenance, cache reuse, decode failure errors
```

Fixture policy: recorded model responses (including malformed and fenced cases) and synthetic or public-domain images live in the repository; private photographs are used only locally and never committed. No test requires a network or a live Ollama instance.

## 13. Milestone 9 - Benchmarking and Calibration

Benchmark axes:

1. Whole-image render time by file type (NEF, RAF, JPEG, HEIC, TIFF).
2. Two-resolution isolation chain cost vs the rejected single-resolution chain, by image size.
3. Model runtime per input role; `keep_alive` on vs off (per-image reload tax).
4. Thinking off vs on: latency and tag-quality delta — confirming the FR1-030c default with data rather than assertion.
5. Effective input resolution: tag quality at long edges 1024 / 1536 / 2048 (and higher if accepted) for both roles, testing the hypothesis that whole-image quality saturates while subject-isolated quality keeps improving — the empirical case for the two-pass design.
6. Foreground-mask failure rate by subject class: distant birds, birds in flight, small wildlife, cluttered scenes, low-contrast subjects (quantifying the FR1-026/027 failure path).
7. Instance-selection accuracy on multi-subject frames (manual spot check against recorded instances).
8. JSON validity and schema-violation rates at temperature 0 with the `format` schema active.
9. Memory pressure and stage-concurrency sweep on the target M4 Pro 48 GB machine: render concurrency 2/4/6/8 against the serialized model stage.
10. Source-hash policy cost: `sha256` vs `fast` across a 2,000-image folder.

Outputs:

```text
benchmarks/
  benchmark-results-YYYY-MM-DD.md
  benchmark-results-YYYY-MM-DD.json
```

Calibration updates the default `ModelInputProfile`, the default `keep_alive`, and the default stage concurrency in the shipped configuration.

## 14. Risks and Mitigations

Risk: the default tag, although installed on the development machine, is absent or different elsewhere, or its content changes under the same tag.
Mitigation: FR1-030b startup verification with fail-fast and installed-tag listing; digest recorded in provenance so "same tag, different model" is detectable after the fact.

Risk: Apple foreground masks fail on distant or low-contrast wildlife subjects.
Mitigation: per-image structured failure, whole-image mode unaffected; failure rate measured by subject class in Milestone 9 so the limitation is quantified, not anecdotal.

Risk: full-resolution renders inflate the cache (45 MP RAW intermediates).
Mitigation: 20 GiB LRU cap; full-resolution renders are regenerable from source plus recipe, so eviction is always safe.

Risk: structured-output or thinking-mode behavior shifts across Ollama or model updates.
Mitigation: runtime version and digest in provenance; recorded-fixture tests catch response-shape drift on upgrade before it reaches real batches.

Risk: ordinal confidence bands prove too coarse for Phase 2 filtering.
Mitigation: bands are a schema field, not an architecture; widening the enum is an additive minor-version change under PW-012.

Risk: the serialized model stage underutilizes the machine.
Mitigation: unlikely for a 26B-class model on 48 GB, but stage concurrency is configurable and the Milestone 9 sweep settles it with data.

Risk: the model profile ceiling (2048 / 4.2 MP) is above or below the model's useful input size.
Mitigation: configurable profile; Milestone 9 axis 5 calibrates it empirically.

## 15. Definition of Done

Phase 1 implementation is done when:

1. `aisidecar analyze` accepts a file or folder with `--recursive` and `--mode whole|subject|both`, defaulting to `both`.
2. All functionality lives in `AISidecarCore`; the executable contains no logic beyond argument handling (PW-002).
3. Whole-image derivatives are orientation-correct, sRGB-tagged, profile-conforming, and cached content-addressably with LRU eviction.
4. Subject-isolated derivatives are produced via the two-resolution chain where Vision finds a foreground, with instance count, selection, and merge decisions recorded.
5. The configured model tag is verified at startup; calls use `/api/chat` with base64 images and the `format` schema; thinking is disabled and recorded; seed, digest, and runtime version are in provenance; the model stays resident via `keep_alive`.
6. One `.ai.json` sidecar per source image, mirrored correctly under `--output-dir`, written atomically, with per-candidate confidence bands and evidence in parsed output and raw text always preserved.
7. Errors carry enumerated codes; folder runs produce a JSONL progress log and derived batch summary; interruption never leaves a partial sidecar; `--existing skip` resumes.
8. The full pipeline runs offline via mock and recorded-fixture runners; golden sidecar tests pass; `swift test` requires no network.
9. All sixteen acceptance criteria of the Phase 1 requirements v0.2 (AC1-001 through AC1-015) pass, including AC1-015: no XMP file is created or modified.
10. Milestone 9 benchmarks exist and have calibrated the shipped defaults for profile, `keep_alive`, and stage concurrency.

## Reference Basis

This plan shares the Reference Basis of the Phase 1 requirements v0.2, incorporated by reference. Items the plan leans on directly:

- Ollama API: `/api/chat` with base64 `images` and `format` JSON Schema; `/api/tags`; `/api/version`: https://docs.ollama.com/api
- Ollama structured outputs: https://docs.ollama.com/capabilities/structured-outputs
- Ollama Gemma 4 listing (multimodal, configurable thinking mode): https://ollama.com/library/gemma4 — `gemma4:26b-a4b-it-qat` is installed on the target machine; FR1-030b guards portability.
- Apple Vision foreground instance masking (macOS 15 Swift API), multi-instance support: https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest
- WWDC23 subject lift with Vision + Core Image; Core Image masking preserves input dynamic range: https://developer.apple.com/videos/play/wwdc2023/10176/
- Apple Core Image `CIRAWFilter`: https://developer.apple.com/documentation/coreimage/cirawfilter
