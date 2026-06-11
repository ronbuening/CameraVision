# Phase 1 Requirements - CLI Raw JSON Sidecar Generator

Version: 0.2
Date: 2026-06-10
Supersedes: 0.1
Binary: `aisidecar` (subcommand: `analyze`)
Core library: `AISidecarCore`
Minimum deployment target: macOS 15
Default vision model: `gemma4:26b-a4b-it-qat` (verified against the local Ollama install at startup)
Primary output artifact: raw AI JSON sidecar file, not XMP

## 0. Changes from v0.1

This revision integrates the findings of the 2026-06-10 requirements review. The substantive changes are:

1. A single `aisidecar` binary with per-phase subcommands replaces the per-phase binaries; all logic lives in a shared `AISidecarCore` library from day one (Section 1.1).
2. Project-wide conventions — flag glossary, error taxonomy, schema evolution, configuration resolution, provenance principles — are defined here and are normative for all later phases (Section 1.2-1.7).
3. The model response schema now requires per-candidate ordinal confidence bands and evidence strings; bare keyword arrays are removed (FR1-044/045).
4. Subject isolation is specified as a two-resolution chain so small subjects retain native pixels (FR1-021a-d), with a defined instance-selection policy for multi-subject frames (FR1-019a-c).
5. Output naming under `--output-dir` mirrors the relative scan tree to eliminate collisions (FR1-009).
6. Rendering mandates EXIF-orientation baking and sRGB conversion (FR1-016a/b); a content-addressed derivative cache with a lifecycle is required (FR1-018a).
7. The Ollama client contract is pinned: `/api/chat`, base64 images, `format` JSON Schema, startup tag verification, model digest provenance, thinking mode disabled, `keep_alive`, timeouts and bounded retries (FR1-030a-f).
8. Batch runs produce an append-only JSONL progress log with a defined interruption and resume contract (FR1-012a-c).
9. Source images carry a content-identity hash (FR1-006a).

## 1. Project-Wide Conventions

The conventions in this section are established in Phase 1 and are binding on Phases 2-4. Later phase documents reference them rather than restating them.

### 1.1 Binary and Library Structure

PW-001 - The project shall ship one command-line binary, `aisidecar`, with one subcommand per phase: `analyze` (Phase 1), `write-xmp` (Phase 2), `normalize` and `apply-session` (Phase 3). The Phase 4 GUI is a separate application target.

PW-002 - All functionality shall live in a library target, `AISidecarCore`. Executable and GUI targets shall contain no logic beyond argument handling and presentation. FR4-002 (shared engine) is thereby satisfied by construction: the engine never exists in any other shape.

PW-003 - The minimum deployment target shall be macOS 15. This permits the modern Swift Vision API, Swift 6 strict concurrency throughout, and removes compatibility testing that has no user. The project shall use Swift 6 language mode with strict concurrency from the first commit.

### 1.2 Flag Glossary

PW-004 - The following flags shall have identical names, types, and semantics in every subcommand that accepts them:

```text
--mode <whole|subject|both>          Analysis mode. Default: both.
--existing <skip|overwrite|fail>     Policy for pre-existing output files. Default: skip.
--recursive                          Recurse into subfolders. Default: off.
--output-dir <path>                  Redirect outputs; mirrors the relative scan tree.
--model <tag>                        Ollama model tag. Default: gemma4:26b-a4b-it-qat.
--model-endpoint <url>               Ollama endpoint. Default: http://localhost:11434.
--profile <name>                     Model input profile name.
--config <path>                      Alternate configuration file.
--log-level <error|warn|info|debug>  Default: info.
--log-format <text|json>             Default: text. JSON logs are stable for machine consumption.
--dry-run                            Report intended actions without writing outputs.
--debug-derivatives                  Copy derivatives beside the source for inspection.
--clear-derivative-cache-on-start    Clear derivative cache artifacts before an analyze invocation uses them.
--clear-derivative-cache-after-success
                                      Clear derivative cache artifacts after a successful analyze invocation.
--model-response-repair-attempts <n> Schema-constrained repair attempts after invalid model JSON or schema failure. Default: 1.
```

PW-005 - Enum-valued flags shall be used instead of families of mutually exclusive boolean flags. The v0.1 triplets (`--whole-only/--subject-only/--both`, `--skip-existing/--overwrite/--fail-existing`) are replaced by `--mode` and `--existing` and shall not reappear in later phases.

### 1.3 Configuration Resolution

PW-006 - Persistent defaults shall be read from a JSON configuration file at `~/Library/Application Support/aisidecar/config.json`, overridable with `--config`. YAML shall not be supported anywhere in the project.

PW-007 - Resolution precedence shall be: CLI flag > environment variable (`AISIDECAR_*`) > configuration file > built-in default.

PW-008 - Provenance shall record the resolved values, never the source of resolution.

### 1.4 Error Taxonomy

PW-009 - Errors shall be recorded as structured objects with enumerated codes:

```json
{
  "code": "E_RENDER_FAILED",
  "stage": "scan | render | isolate | model | normalize | write",
  "message": "human-readable detail",
  "recoverable": true
}
```

PW-010 - The initial code set is frozen in Phase 1 and is additive-only thereafter:

```text
E_UNSUPPORTED_FORMAT            E_DECODE_FAILED
E_RENDER_FAILED                 E_ORIENTATION_UNRESOLVED
E_SUBJECT_ISOLATION_NO_FOREGROUND
E_SUBJECT_ISOLATION_FAILED
E_MODEL_ENDPOINT_UNREACHABLE    E_MODEL_TAG_NOT_FOUND
E_MODEL_TIMEOUT                 E_MODEL_INVALID_JSON
E_MODEL_SCHEMA_VIOLATION
E_SIDECAR_EXISTS                E_SIDECAR_COLLISION
E_WRITE_FAILED                  E_VALIDATION_FAILED
E_SCHEMA_UNSUPPORTED            E_VOCABULARY_INVALID
E_SESSION_STALE                 E_CONFIG_INVALID
E_EXIFTOOL_MISSING              E_INTERRUPTED
```

`E_MODEL_INVALID_JSON` means the final response was not parseable JSON. `E_MODEL_SCHEMA_VIOLATION` means it parsed but failed the response schema. Both preserve raw response text, including attempted repair responses when repair is enabled.

### 1.5 Schema Evolution

PW-011 - All artifact schemas (`ai-sidecar-json/x.y`, `ai-sidecar-normalization/x.y`, the vocabulary schema, and the GUI database schema) shall carry a major.minor version.

PW-012 - Readers shall accept any file sharing their major version, shall preserve unknown fields verbatim on rewrite, and shall refuse files with a higher major version with `E_SCHEMA_UNSUPPORTED`. Minor-version changes shall be strictly additive.

### 1.6 Provenance Principles

PW-013 - Reproducibility is defined as recorded configuration, not promised bit-identical output. Temperature 0 narrows sampling but does not guarantee identical text across runtime versions, quantizations, or MoE routing. Every model run shall therefore record: model tag, model digest, runtime name and version, sampling options, seed, thinking-mode setting, prompt version and prompt content hash, response schema version, and input-derivative hash.

PW-014 - Model tags are mutable references; the model digest reported by the runtime is the durable identity and shall always be recorded alongside the tag.

### 1.7 Concurrency Model

PW-015 - Batch pipelines shall run rendering and subject isolation in a bounded-concurrency stage (default: number of physical performance cores; configurable) feeding a serialized model stage with exactly one in-flight model request. The model shall be kept resident across the batch via `keep_alive` rather than reloading per image. Stage concurrency is a configuration value and a benchmarking axis.

## 2. Purpose

Phase 1 shall create the `aisidecar analyze` subcommand: it accepts a single image file or a folder of image files, renders model-ready analysis images, optionally isolates the foreground subject using the Apple image pipeline, runs the configured local vision model, and writes a raw JSON sidecar containing the model output and processing provenance.

This phase is deliberately not responsible for XMP metadata writeback, tag normalization, review workflows, or Lightroom/Capture One compatibility. Its job is to prove the local image-analysis path and create auditable raw model output.

## 3. Relationship to Later Phases

Phase 1 establishes the reusable foundation for all later phases, now guaranteed structurally by PW-001/002:

- file and folder scanning with source identity;
- RAW/JPEG/TIFF/PNG/HEIC/DNG render handling;
- whole-image derivative rendering;
- subject-isolated derivative rendering (two-resolution chain);
- model input sizing by profile;
- Ollama-compatible model calls behind an adapter protocol;
- structured JSON prompting with per-candidate confidence;
- raw response capture;
- deterministic sidecar naming with tree mirroring;
- batch-safe error reporting with enumerated codes;
- JSONL progress logging and resume semantics;
- reusable provenance fields.

Phase 2 shall consume this phase's raw JSON output and transform extracted candidates into XMP sidecars. Phase 3 shall add normalization on top of the same raw observations. Phase 4 shall wrap the same `AISidecarCore` modules in a GUI.

## 4. Scope

The subcommand shall support three analysis modes via `--mode <whole|subject|both>`:

```text
whole      Analyze only the full rendered image.
subject    Analyze only the isolated subject derivative.
both       Run the model twice: once on the full image and once on the isolated subject.
```

The default mode shall be `both`.

## 5. Input Requirements

FR1-001 - The program shall accept either one image file path or one folder path.

FR1-002 - Folder input shall support recursive scanning with `--recursive` and non-recursive scanning by default.

FR1-003 - Supported extensions shall include at least `NEF`, `NRW`, `CR3`, `CR2`, `ARW`, `RAF`, `ORF`, `RW2`, `DNG`, `JPG`, `JPEG`, `TIF`, `TIFF`, `HEIC`, and `PNG`, subject to macOS decoder support.

FR1-004 - Unsupported files shall be skipped with a structured `E_UNSUPPORTED_FORMAT` error entry rather than crashing the batch.

FR1-005 - Hidden files, macOS resource forks, `.DS_Store`, and existing `.ai.json` and `.xmp` sidecar files shall be ignored by default.

FR1-006 - The program shall process each input image independently. It shall not try to merge RAW+JPEG pairs in Phase 1.

FR1-006a - Each scanned image shall record a source content identity: by default the SHA-256 of the full file content. A `fast` policy (file size + mtime + SHA-256 of the first and last 4 MiB) may be selected in configuration for very large batches; the policy name shall be recorded alongside the hash. This identity is what later phases use to detect that an image changed after analysis.

FR1-006b - For folder input, each scanned image shall record its path relative to the scan root.

## 6. Output Requirements

FR1-007 - For each source image, the program shall write one raw JSON sidecar.

FR1-008 - The sidecar name shall include the original extension to avoid RAW+JPEG collisions:

```text
_DSC1234.NEF -> _DSC1234.NEF.ai.json
_DSC1234.JPG -> _DSC1234.JPG.ai.json
_DSC1234.RAF -> _DSC1234.RAF.ai.json
```

FR1-009 - When `--output-dir` is used with folder input, the sidecar tree shall mirror the relative path of each source from the scan root: the sidecar for `<root>/2026/06/_DSC1234.NEF` shall be written to `<output-dir>/2026/06/_DSC1234.NEF.ai.json`. Flattening is forbidden because Nikon-style 4-digit frame counters make basename collisions a certainty in real archives.

FR1-009a - Residual collisions (including case-insensitive filesystem collisions) shall be detected before writing and shall fail the affected files with `E_SIDECAR_COLLISION` without aborting the batch.

FR1-010 - Pre-existing sidecars shall be governed by `--existing <skip|overwrite|fail>` with default `skip`.

FR1-011 - The sidecar shall contain raw model output, parsed output when available, source-file details including identity, derivative-image details, model details and digest, prompt version and hash, runtime details, analysis mode, timing, and structured errors.

FR1-012 - Folder runs shall write a batch summary JSON named `batch-summary-<ISO-8601-timestamp>.json` in the output directory (or beside the scan root when no `--output-dir` is given).

FR1-012a - Folder runs shall additionally write an append-only JSONL progress log (one self-contained record per completed file, flushed before the batch advances). The batch summary shall be derived from this log.

FR1-012b - Interruption contract: on `SIGINT`/`SIGTERM`, the in-flight file's sidecar shall be either complete or absent — never partial — by virtue of atomic writes; the progress log shall reflect everything finished; the summary, when writable, shall carry `E_INTERRUPTED`.

FR1-012c - Re-running an interrupted batch with `--existing skip` shall process only the remainder. This is the Phase 1 resume mechanism; no separate checkpoint format shall be introduced.

FR1-012d - All file writes (sidecars, summaries, logs) shall be atomic: temporary file in the destination directory, then rename.

## 7. Rendering Requirements

FR1-013 - The program shall render a whole-image derivative for `whole` and `both` modes.

FR1-014 - The whole-image derivative shall preserve the full image framing and shall be resized to fit the active model input profile.

FR1-015 - The program shall render a subject-isolated derivative for `subject` and `both` modes.

FR1-016 - RAW rendering shall use the native macOS image pipeline. Core Image / `CIRAWFilter` shall be the RAW rendering path.

FR1-016a - EXIF orientation shall be baked into the pixels of every derivative before any analysis or model submission. The applied orientation value shall be recorded in derivative provenance. Wherever an unbaked image is handed to Vision, the orientation shall be passed explicitly.

FR1-016b - All model-input derivatives shall be converted to sRGB with the profile embedded. The target color space is a `ModelInputProfile` field, not a hard-coded constant, but sRGB is the default and no other default shall ship in Phase 1. Wide-gamut or untagged derivatives shift the model's color vocabulary, which matters when the desired tags include plumage colors.

FR1-017 - The renderer shall record the render recipe version, output format, width, height, color space, applied orientation, and SHA-256 hash of each derivative.

FR1-017a - The renderer shall produce and retain (in cache) a full-resolution render of the source — the RAW pipeline output at native size — because the subject-isolation chain crops from it (FR1-021a-d). Full-resolution renders are regenerable from source plus recipe, so cache eviction of them is always safe.

FR1-018 - Temporary derivatives shall be stored in an application cache by default and shall not be written beside the source image unless `--debug-derivatives` is enabled, in which case they are copied (not moved) beside the source.

FR1-018a - The derivative cache shall use content-addressed keys (`<source-sha256>-<recipe-version>-<role>.<ext>`), enabling reuse across re-runs with unchanged recipes; shall enforce a configurable size cap with LRU eviction (default 20 GiB); and shall be clearable via an explicit maintenance command.

FR1-018b - Analyze shall retain derivative cache artifacts by default. It shall support opt-in clearing before the run uses the cache and after a fully successful run through JSON config, `AISIDECAR_*` environment overrides, and matching CLI flags. A run with failed per-file records or interruption shall not perform the post-success clear.

## 8. Subject Isolation Requirements

FR1-019 - The subject-isolation path shall use Apple Vision for foreground instance mask generation and Core Image for mask application, crop generation, matte/background compositing, and output rendering.

FR1-019a - The Vision foreground instance mask request returns a set of separable instances. The instance selection policy shall be: select the instance with the largest mask area, tie-broken by mask-centroid proximity to the frame center.

FR1-019b - Merge rule: if the union bounding box of multiple instances is dominated by the selected instance's bounding box (≥ 80% of the union area, configurable), the instances shall be merged into one subject mask. Bodies segmented apart from tails or wingtips are one subject.

FR1-019c - The sidecar shall record `instance_count`, the selected instance indices, whether merging occurred, and per-instance normalized bounding boxes, preserving the seam for a future multi-subject mode (N crops, N model runs) without schema change beyond a minor version.

FR1-020 - The implementation may refer to this combined path as the Apple image-isolation pipeline, but it shall not imply that Core Image alone performs semantic subject detection.

FR1-021 - Subject-isolated output shall crop to the selected subject mask bounding box plus a configurable margin.

The crop shall be taken through a two-resolution chain. Masking the already-downsized model derivative and cropping it — the v0.1 reading — caps a distant subject at a fraction of 2048 px and, with upscaling forbidden, makes FR1-023 unachievable in exactly the case that motivates subject isolation. Therefore:

FR1-021a - The foreground mask request shall run at an analysis-friendly resolution (the whole-image derivative is suitable; masking does not need full resolution).

FR1-021b - The selected mask and bounding box shall be mapped back to the full-resolution render (FR1-017a), with scale factors recorded.

FR1-021c - The crop, margin expansion, mask application, and matte compositing shall be performed on the full-resolution render.

FR1-021d - The composited crop shall then be downsized to the model input profile.

FR1-022 - The default crop margin shall be 8 percent of the longer side of the subject bounding box, clamped to the source image bounds.

FR1-023 - The subject crop shall be resized so the subject occupies as many useful pixels as possible within the active model input profile.

FR1-024 - The program shall not upscale the subject crop beyond native rendered crop resolution by default. If the native crop is smaller than the profile permits, it shall be submitted at native size and that fact recorded. A future `--allow-upscale-subject` flag may permit interpolation; the output shall record that upscaling occurred.

FR1-025 - Subject-isolated derivatives shall composite onto a neutral matte background (default mid-gray, RGB 128/128/128, configurable per profile). Transparent PNG output may be supported later, but neutral matte is the compatibility default because some vision-model pipelines ignore or mishandle alpha channels.

FR1-026 - If no foreground subject is found and the user selected `--mode subject`, the program shall write a sidecar with `E_SUBJECT_ISOLATION_NO_FOREGROUND` and shall not silently substitute the whole image.

FR1-027 - If no foreground subject is found and the user selected `--mode both`, the program shall still complete the whole-image run and shall record the subject-isolation failure.

## 9. Model Requirements

FR1-028 - The default model tag shall be `gemma4:26b-a4b-it-qat`.

FR1-029 - The model tag shall be configurable with `--model` and in the configuration file.

FR1-030 - The initial runtime target shall be Ollama over the local HTTP API.

FR1-030a - The client shall use `POST /api/chat` with the image supplied as base64 in the user message's `images` array and the response JSON Schema supplied via the `format` field. One image and one prompt per request.

FR1-030b - At startup, the configured tag shall be resolved against `GET /api/tags`. An unresolvable tag shall fail fast with `E_MODEL_TAG_NOT_FOUND` and a listing of locally installed vision-capable tags. The runtime version from `GET /api/version` and the model digest shall be recorded in provenance (PW-013/014).

FR1-030c - Thinking mode shall be explicitly disabled for tagging runs and the setting recorded in `request_options`. Reasoning traces multiply latency across large batches and can interfere with strict structured output; tagging is not a reasoning workload.

FR1-030d - `keep_alive` shall default to a duration that keeps the model resident for the whole batch (initial default: `30m`, refreshed per request), avoiding a per-image reload tax.

FR1-030e - Requests shall have a timeout (default 180 s) and bounded transport retries (default 2), retrying only on timeout and transport errors. `E_MODEL_INVALID_JSON` and `E_MODEL_SCHEMA_VIOLATION` shall not be silently accepted; by default the runtime performs one no-image, schema-constrained repair call using the original raw output and validation error, then records the final failure if repair still does not produce schema-valid JSON. `model_response_repair_attempts = 0` preserves the strict one-shot behavior.

FR1-030f - Request options shall record temperature, seed, thinking setting, `keep_alive`, and any context override, per PW-013.

FR1-031 - The model client shall be implemented behind a `VisionModelRunner` protocol so later phases can support other Ollama tags, llama.cpp, MLX, or a direct library backend. A mock runner and a recorded-fixture replay runner shall be implemented alongside the live runner so the full pipeline is testable without a network.

FR1-032 - The model call shall pass one image and one prompt per request.

FR1-033 - In `both` mode, the program shall perform two separate model runs: `input_role = whole_image` and `input_role = subject_isolated`.

FR1-034 - The whole-image prompt shall emphasize scene, context, habitat, setting, background, composition, lighting, and broad subject classification.

FR1-035 - The subject-isolated prompt shall emphasize morphology, visible field marks, object details, fine subject traits, species/object candidates, and uncertainty.

FR1-036 - The subject-isolated prompt shall explicitly tell the model that background context has been removed or replaced and that it must not infer habitat, location, or scene context. The subject-isolated response schema shall additionally omit habitat and scene fields entirely, enforcing this rule structurally rather than rhetorically (FR1-045).

FR1-037 - The model request shall use structured JSON output via the runtime's schema mechanism.

FR1-038 - Sampling shall target temperature 0 with a recorded seed. Reproducibility is the recorded configuration, not a promise of identical text (PW-013).

## 10. Raw JSON Sidecar Schema Requirements

FR1-039 - The sidecar shall use the versioned schema identifier `ai-sidecar-json/1.0`, governed by PW-011/012.

Minimum top-level structure:

```json
{
  "schema_version": "ai-sidecar-json/1.0",
  "source": {},
  "run_configuration": {},
  "model_input_profile": {},
  "derivatives": [],
  "subject_isolation": {},
  "model_runs": [],
  "errors": [],
  "created_at": "ISO-8601 timestamp"
}
```

FR1-040 - Each `model_runs` entry shall include:

```json
{
  "input_role": "whole_image | subject_isolated",
  "model": "gemma4:26b-a4b-it-qat",
  "model_digest": "sha256:...",
  "runtime": "ollama",
  "runtime_version": "string",
  "prompt_version": "string",
  "prompt_sha256": "string",
  "response_schema_version": "string",
  "request_options": {},
  "raw_response_text": "string",
  "parsed_response_json": {},
  "json_valid": true,
  "duration_ms": 0,
  "error": null,
  "response_attempts": []
}
```

FR1-041 - Invalid primary model JSON shall be preserved as raw text. When repair is attempted, `response_attempts` shall preserve the primary response, repair response, per-attempt prompt hash, request options, parsed JSON when available, and per-attempt error. The top-level `model_runs` fields represent the final accepted response or final failure. The parser shall strip Markdown code fences before parsing, since fenced-but-valid JSON is a common local-model failure mode; fence-stripped valid JSON is not an error.

FR1-042 - The sidecar shall include enough derivative provenance to reproduce which input image the model saw: derivative hash, dimensions, color space, recipe version, and the source identity (FR1-006a).

FR1-043 - The sidecar shall not include derivative image data. It shall include derivative hashes and cache paths.

FR1-044 - Model response candidates shall be objects, not bare strings. Every candidate shall carry an ordinal confidence band and, for subject candidates and proposed keywords, a short evidence string:

```json
{ "term": "string", "confidence": "high | medium | low", "evidence": "string" }
```

Ordinal bands are deliberate. Self-reported numeric confidence from a quantized local model is false precision; bands are honest, and Phase 3 makes cross-image agreement frequency — not self-reported confidence — the primary consensus signal. Numeric confidence shall not be requested from the model in any phase.

FR1-045 - Two response schemas shall exist. The whole-image schema:

```json
{
  "summary": "string",
  "main_subjects": [ { "term": "...", "confidence": "...", "evidence": "..." } ],
  "secondary_subjects": [ { "term": "...", "confidence": "...", "evidence": "..." } ],
  "scene_context": [ { "term": "...", "confidence": "..." } ],
  "habitat_or_setting": [ { "term": "...", "confidence": "..." } ],
  "behavior_or_action": [ { "term": "...", "confidence": "..." } ],
  "proposed_keywords": [ { "term": "...", "confidence": "...", "evidence": "..." } ],
  "uncertainty_notes": "string"
}
```

The subject-isolated schema is identical except that `scene_context` and `habitat_or_setting` are absent (FR1-036). Phase 1 model JSON shall not include `visible_text`; text extraction is deferred to a dedicated OCR-capable path in a later phase. Both schemas shall be fully specified JSON Schema documents — item types, required fields, bounded array and string lengths — because the schema is the literal `format` payload sent to the runtime: an API contract, not documentation.

FR1-046 - Prompts shall be versioned resources carrying a semantic version and a SHA-256 of their text; both shall be recorded per run, making "same prompt version" verifiable rather than asserted.

## 11. Command-Line Interface Requirements

Required command shape:

```bash
aisidecar analyze <file-or-folder> [--mode both]
aisidecar purge [--cache-dir <path>] [--config <path>]
```

Accepted flags: the project-wide glossary (PW-004) plus:

```text
--dry-scan        Print the scan result (with identities and relative paths) and exit.
```

Purge-specific flags:

```text
--cache-dir <path>    Override the resolved derivative cache directory for this purge.
```

`aisidecar purge` removes derivative cache artifacts from the resolved cache directory and does not contact Ollama or validate analyze-only model settings. It also accepts the project-wide `--config` flag.

Recommended examples:

```bash
aisidecar analyze /Photos/Birds/_DSC1234.NEF --mode both

aisidecar analyze /Photos/Birds --recursive --mode whole --output-dir ./ai-json

aisidecar analyze /Photos/Birds --recursive --mode subject --existing skip

aisidecar purge
```

## 12. Acceptance Criteria

AC1-001 - A single RAW file can be rendered and analyzed in whole-image mode.

AC1-002 - A single JPEG file can be analyzed in whole-image mode.

AC1-003 - A single image can produce a subject-isolated derivative when Apple Vision finds a subject.

AC1-004 - `--mode both` creates two model runs in the raw JSON sidecar.

AC1-005 - For a frame whose subject occupies ≤ 10% of the long edge, the subject-isolated derivative contains measurably more native subject pixels than a crop of the whole-image derivative would — demonstrating the two-resolution chain.

AC1-006 - A multi-subject frame records instance count and per-instance bounding boxes and applies the documented selection policy.

AC1-007 - If subject isolation fails, the sidecar records the failure with the correct code and the process continues where possible.

AC1-008 - Recursive folder scans with `--output-dir` produce a mirrored sidecar tree, one `.ai.json` per processable image, a JSONL progress log, and a batch summary; basename collisions across subfolders do not collide on disk.

AC1-009 - Existing sidecars are not overwritten unless `--existing overwrite` is given.

AC1-010 - Model failures, invalid JSON, schema violations, render failures, and unsupported files are recorded with enumerated error codes in machine-readable form.

AC1-011 - Killing a batch mid-run leaves no partial sidecar; re-running with `--existing skip` completes only the remainder.

AC1-012 - All derivatives are orientation-correct and sRGB-tagged.

AC1-013 - Parsed candidates carry confidence bands; the subject-isolated response contains no habitat or scene fields.

AC1-014 - An unresolvable model tag fails fast at startup with the installed-tag list; sidecars record the model digest and runtime version.

AC1-015 - No XMP sidecar is created in Phase 1.

## 13. Future Groundwork

Phase 1 shall keep these design seams stable for later phases:

- `ImageScanner` and `SourceIdentity` reusable by all phases;
- `ImageRenderer` and the derivative cache reusable by XMP and GUI flows;
- `SubjectIsolationService` with its instance records reusable by future multi-subject modes;
- `VisionModelRunner` adapter (live, mock, recorded-fixture) reusable for alternative runtimes;
- `ModelInputProfile` reusable for model-specific image sizing;
- versioned, hashed prompts and schemas retained for reprocessing;
- the error taxonomy, flag glossary, and schema-evolution rule binding on Phases 2-4;
- the raw JSON sidecar schema stable enough for Phase 2 to consume under PW-012.

## Reference Basis

The requirements use the following implementation and compatibility assumptions:

- Ollama vision models accept images alongside text prompts: https://docs.ollama.com/capabilities/vision
- Ollama structured outputs can enforce JSON-shaped responses, including for vision requests: https://docs.ollama.com/capabilities/structured-outputs
- Ollama API endpoints used by this project: `/api/chat` (base64 `images`, `format` schema), `/api/tags`, `/api/version`: https://docs.ollama.com/api
- Ollama's Gemma 4 listing describes Gemma 4 as multimodal with vision support and a configurable thinking mode: https://ollama.com/library/gemma4 — the default tag `gemma4:26b-a4b-it-qat` is verified present in the local install; FR1-030b guards against drift on other machines.
- Google's Gemma documentation describes the 26B A4B MoE model in the Gemma 4 family: https://ai.google.dev/gemma/docs/core
- Apple Vision foreground instance masking (`GenerateForegroundInstanceMaskRequest`, macOS 15 Swift API; `VNGenerateForegroundInstanceMaskRequest`, macOS 14) generates instance masks of noticeable foreground objects and supports multiple instances: https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest
- Apple's WWDC23 subject-lift session describes combining Vision masks with Core Image for complex pipelines and notes Core Image masking preserves input dynamic range: https://developer.apple.com/videos/play/wwdc2023/10176/
- Apple Core Image `CIRAWFilter` produces an image from RAW sensor data: https://developer.apple.com/documentation/coreimage/cirawfilter
- ExifTool is a platform-independent library and command-line application for reading, writing, and editing metadata: https://exiftool.org/
- IPTC Photo Metadata defines Keywords as terms expressing the subject and other aspects of image content, implemented in XMP as `dc:subject`: https://www.iptc.org/std/photometadata/specification/IPTC-PhotoMetadata
- Adobe Lightroom Classic supports sidecar metadata for RAW images, usually XMP sidecars stored next to the native image: https://helpx.adobe.com/lightroom-classic/help/create-xmp-acr-files.html
- Capture One can read `.XMP` sidecar files and notes that same-base-name files with different extensions can share one XMP file: https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files
