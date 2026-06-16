# CameraVision

CameraVision is a local macOS utility for generating AI-assisted image metadata for photo workflows. The current implementation generates auditable raw AI JSON sidecars, exports accepted Phase 1 candidates into safe XMP sidecars through `aisidecar write-xmp`, and can build normalized Phase 3 sessions before writing normalized XMP sidecars through the same owned writer; those sidecars have been smoke-verified as readable by Lightroom Classic and Capture One.

## Current State

Phase 1 Milestones 0-8, the Milestone 9a benchmark harness, Phase 2 Milestones 0-10, the pre-Phase-3 GPS context milestone, and Phase 3 Milestones 0-8 are implemented. Phase 1 commands still produce only auditable raw AI JSON sidecars and remain XMP-silent. Phase 2 can resolve raw sidecars, extract candidate keywords, reject coordinate/GPS-only export candidates, plan XMP targets, group same-base-name sources, merge existing XMP sidecars through the owned engine, create deterministic backups, validate semantic preservation, restore on validation failure, write export reports, run analyze-and-write through the same export planner, and produce XMP keyword sidecars readable by Lightroom Classic and Capture One. Phase 3 currently provides executable `normalize` and `apply-session` paths, controlled-vocabulary loading and validation, file-list and raw-sidecar input resolution, privacy-aware normalization session schema records, source identity binding, same-base-name group skeletons, Phase 2 candidate observation capture, per-asset vocabulary canonicalization, direct-apply policy decisions, metadata-affinity graph scoring, hierarchy-aware batch counts, local weighted consensus, local conflict mass, global backstop propagation, session-context propagation gates, `off`/`single-image`/`batch-conservative` normalization behavior, unknown session-context policy handling, normalized XMP change-plan adaptation with decision provenance, `normalize --dry-run` change-plan output, `normalize --session-only` session/report/summary/progress artifact writes without XMP sidecar creation, normal `normalize --from-json`/`--file-list` writes through the Phase 2 owned writer, analyze-and-normalize execution with default raw `.ai.json` preservation and `--no-write-ai-json`, and model-free `apply-session` writes/dry-runs from stored decisions through the Phase 2 XMP writer path.

The repository currently contains:

- A Swift Package Manager project targeting macOS 15 and Swift 6.
- `AISidecarCore`, the shared library where reusable project logic lives.
- `aisidecar`, the command-line executable.
- `aisidecar analyze` command wiring with the Phase 1 shared flag surface, `aisidecar write-xmp` Phase 2 XMP export, `aisidecar normalize` Phase 3 session/dry-run/write/analyze-and-normalize execution, `aisidecar apply-session` Phase 3 session application, `aisidecar benchmark` for Milestone 9a timing/validity runs, and `aisidecar purge` for derivative cache maintenance.
- A reusable `AISidecarCore/Benchmarking` harness for benchmark specs, result documents, sidecar metric aggregation, no-XMP checks, scratch cleanup, and offline self-test.
- Configuration resolution with precedence: CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default.
- The frozen Phase 1 structured error taxonomy.
- Text and JSON log rendering.
- File and folder scanning with supported-extension filtering, hidden/system/sidecar exclusion, relative path recording, and source identity hashing.
- `aisidecar analyze ... --dry-scan` JSON output.
- Raw `.ai.json` sidecar writing with extension-preserving names and mirrored output trees.
- Model input profile resolution for the built-in `gemma4-26b-default` profile.
- Whole-image rendering with EXIF orientation baking, sRGB output, and profile-conforming JPEG derivatives.
- Content-addressed derivative caching with manifest-backed LRU eviction, configurable cache directory/size, opt-in start/success cache clearing, and explicit purge command.
- Subject isolation with Apple Vision foreground masks, deterministic instance selection/merge policy, in-memory native-resolution crop/matte compositing, and `subject_isolated` derivative provenance.
- Diagnostic model-input export via `--export-model-inputs` for reviewing the exact images that model calls receive.
- Read-only EXIF GPS capture context for model prompts via `--gps-context off|coarse|exact`, defaulting to coarse context and recorded only in raw sidecar provenance.
- Versioned whole-image and subject-isolated prompts plus bundled v1.4 response schemas.
- A reusable Ollama vision model runtime layer with tag/digest verification, runtime provenance, `/api/chat` request encoding, response parsing, schema validation, schema-constrained response repair, retry/error classification, and mock/recorded-fixture runners.
- Full `aisidecar analyze` model execution with populated `model_runs` records, optional model input context provenance, prompt/schema provenance, model digest/runtime provenance, raw response preservation, parsed JSON when valid, and optional per-attempt response provenance when repair is used.
- `aisidecar write-xmp --from-json` raw sidecar scanning, source resolution, source verification policy, candidate extraction, `<base>.xmp` naming, same-base-name RAW/JPEG group planning, `--pair-scope`, and `--dry-run` change-plan JSON.
- Owned XMP sidecar parsing, keyword merge, atomic write, backup/restore, post-write validation, source hash recheck, progress JSONL, JSON export report, and Markdown summary artifacts.
- Phase 3 starter vocabulary resources plus normalization artifacts for `--from-json`, `--file-list`, and analyze-and-normalize inputs, including source identity bindings, same-base-name group records, candidate observations, candidate skip reasons, direct/propagated per-asset decisions, metadata-affinity edges, local consensus records, normalized XMP write plans with per-term decision provenance, normal-write execution reports, model-free apply-session source staleness checks, current-target recomputation, current-XMP merge execution, privacy defaults, deterministic policy metadata, JSON reports, Markdown summaries, and JSONL progress logs.
- Analyze-and-write integration that reuses `AnalyzePipeline`, preserves `.ai.json` sidecars by default, supports `--no-write-ai-json`, and passes successful analysis results into the shared XMP export path.
- Bounded render/isolation preparation through `stage_concurrency`, feeding a serialized single-flight model stage.
- JSON/env configuration for subject crop margin and merge dominance threshold.
- JSON/env/CLI configuration for `stage_concurrency`, model response repair attempts, GPS context, and derivative cache clearing.
- Atomic writes for sidecars and batch summaries.
- `--existing skip|overwrite|fail` handling.
- Optional `--debug-derivatives` copies beside source images.
- Folder-run JSONL progress logs and derived batch summaries.
- SIGINT/SIGTERM-aware interruption handling for the full analyze pipeline.
- Offline XCTest coverage for config resolution, validation, logging, error serialization, scanning, source identity, sidecar naming/writing, schema-evolution sidecar rewrites, rendering, derivative cache behavior and purge resolution, subject-isolation geometry/pipeline behavior, GPS context extraction/provenance, model-runtime behavior including repair success/failure, progress logs, summaries, diagnostic export, golden sidecars, no-XMP guards, the shell pipeline, the full analyze pipeline, and Phase 2 `write-xmp` planning, writeback, reporting, validation, interruption, and analyze-and-write paths.

Still pending before release signoff:

- Phase 1 Milestone 9 calibration and quality review evidence.

## Phase 3 Gate Status

Phase 2 Milestone 10 compatibility smoke evidence is recorded in `agent_docs/release-evidence/phase-2-milestone-10-compatibility-smoke.md`. Phase 3 release work still depends on:

- Phase 1 Milestone 9 calibration and quality review evidence is archived, or remaining evidence is explicitly listed as deferred in release notes.
- The latest `swift test` and `swift run aisidecar write-xmp --help` results are recorded in `agent_docs/phase-2-cli-implementation-plan(1).md`.

Phase 3 Milestones 0-8 are now in place. The next implementation unit is Phase 3 Milestone 9: interruption, concurrency, and file-safety hardening from `agent_docs/03-cli-normalized-batch-tagger-requirements.md`.

## Repository Layout

```text
Sources/
  AISidecarCore/       Shared engine code for all phases.
    Benchmarking/      Milestone 9a benchmark runner, result documents, and aggregation.
    Configuration/     Config defaults, validation, and precedence.
    Errors/            Frozen Phase 1 structured error taxonomy.
    FileScanning/      Input discovery and source image records.
    Identity/          Source content identity hashing.
    Metadata/          Phase 2 candidate extraction, keyword policy, XMP naming, grouping, planning, owned XMP engine, backup, and validation.
    ModelRuntime/      Ollama runner, model-run records, JSON schema validation, and test runners.
    Rendering/         Model input profiles, render recipes, renderer, and derivative cache.
    Normalization/     Phase 3 vocabulary, input resolution, candidate observations, canonicalization, metadata affinity, consensus, session schema, artifact planning, and privacy-aware affinity-input records.
    Pipeline/          Full analyze pipeline, analyze shell pipeline, diagnostic model-input export, XMP export/analyze-and-write pipelines, session/dry-run/write normalize pipelines, analyze-and-normalize adapter, and apply-session pipeline.
    Reporting/         CLI logs, JSONL progress logs, batch summaries, XMP export reports/summaries, and normalization reports/summaries/progress logs.
    Sidecars/          Raw JSON sidecar naming, schema records, and atomic writes.
    SubjectIsolation/  Foreground masks, instance selection, two-resolution crops.
  AISidecarCLI/        CLI argument handling and command wiring only.
Tests/
  AISidecarCoreTests/  Offline unit tests for core behavior.
agent_docs/           Requirements, implementation plans, and agent guidance.
```

## Requirements And Planning Docs

- `agent_docs/01-cli-raw-json-sidecar-requirements.md` - Phase 1 requirements.
- `agent_docs/phase-1-cli-implementation-plan.md` - Phase 1 milestone plan.
- `agent_docs/02-cli-xmp-sidecar-requirements-updated.md` - Phase 2 requirements.
- `agent_docs/phase-2-cli-implementation-plan(1).md` - Phase 2 milestone plan.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md` - Phase 3 requirements.
- `agent_docs/phase-3-cli-implementation-plan-v0.3.md` - Phase 3 milestone plan and traceability matrix.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` - Phase 4 requirements.
- `agent_docs/commenting_guide.md` - Commenting rules for Swift source and tests.
- `agent_docs/agent-md-best-practices.md` - Guidance used for `AGENTS.md`.

## Build And Test

The project uses SwiftPM and depends on Swift ArgumentParser.

```bash
swift test
swift run aisidecar analyze --help
swift run aisidecar write-xmp --help
swift run aisidecar normalize --help
swift run aisidecar apply-session --help
swift run aisidecar benchmark --help
swift run aisidecar purge --help
swift run aisidecar benchmark --self-test
swift run aisidecar analyze <folder> --recursive --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode subject --debug-derivatives --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode both --export-model-inputs <tmp-output>
swift run aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir <tmp-output>
swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --dry-run
swift run aisidecar write-xmp --from-json <json-file-or-folder> --recursive --source-root <image-root> --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-file-or-folder> --recursive --source-root <image-root> --session-only --output-dir <tmp-output>
swift run aisidecar normalize --file-list <image-list.txt> --session-only --output-dir <tmp-output>
swift run aisidecar normalize --from-json <json-file-or-folder> --recursive --source-root <image-root> --dry-run --output-dir <tmp-output>
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar analyze --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar write-xmp --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar normalize --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar apply-session --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar benchmark --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar purge --help
```

## Current Analyze Behavior

`aisidecar analyze` currently performs the full Phase 1 analyze pipeline. It scans inputs, computes source identities, verifies the configured Ollama model tag at startup, renders `whole_image` derivatives when requested, optionally isolates foreground subjects for `--mode subject|both` from an in-memory native-resolution source render, runs the model with versioned prompts and response schemas, and writes schema-versioned `.ai.json` sidecars with model input profile, derivative provenance, subject-isolation provenance, and populated `model_runs`. When EXIF GPS exists, `--gps-context coarse` appends rounded capture coordinates to both whole-image and subject-isolated model prompts by default; `off` disables this and `exact` records the exact submitted coordinates in `model_runs[*].model_input_context.gps`. GPS context is never written to XMP and is guarded from becoming coordinate keywords. New runs write at most two cached image artifacts per source: `whole_image` when whole-image analysis is requested and `subject_isolated` when subject isolation succeeds, excluding the cache index manifest. Invalid model JSON or schema violations get one schema-constrained no-image repair attempt by default; set `model_response_repair_attempts` or `--model-response-repair-attempts 0` to disable repair. Folder runs write JSONL progress and batch summary artifacts. The render/isolation stage is bounded by `stage_concurrency`, while model requests are serialized with one in-flight request. The derivative cache is retained by default; set `clear_derivative_cache_on_start` or `clear_derivative_cache_after_success` in config, or use the matching CLI flags, to clear cache artifacts at those run boundaries.

For visual validation, `--export-model-inputs <folder>` switches `analyze` into the diagnostic export path. It renders through the same cache and subject-isolation pipeline, mirrors source relative paths under the export folder, writes only `whole_image` and/or `subject_isolated` model-input files, and writes a timestamped `model-input-export-*.json` manifest. Subject-only export does not create a cached `whole_image` artifact. It does not read or send GPS context, and it does not write `.ai.json` sidecars, progress logs, batch summaries, XMP, or model output. `--dry-run` and `--debug-derivatives` are rejected in this mode because export mode writes only to the requested export folder.

`aisidecar purge` removes derivative cache artifacts from the resolved cache directory. It honors `--config`, `--cache-dir`, `AISIDECAR_CONFIG`, and `AISIDECAR_DERIVATIVE_CACHE_DIR`; it does not contact Ollama or validate analyze-only model settings.

Cache cleanup is scoped to files owned by the derivative cache manifest or matching aisidecar's deterministic derivative names, so unrelated files in a misconfigured cache directory are not intentionally removed.

## Current Write-XMP Behavior

`aisidecar write-xmp --from-json` reads one `.ai.json` sidecar or scans a folder, resolves the recorded source image, applies source-verification policy, extracts accepted keyword candidates, derives `<base>.xmp` target paths, groups same-base-name sources into one target plan, applies `--pair-scope union|raw-only|jpeg-only`, and emits `ai-sidecar-xmp-change-plan/1.0` JSON when `--dry-run` is supplied. Non-dry-run export writes through `OwnedXMPSidecarEngine`, merges only `dc:subject` and `lr:hierarchicalSubject`, backs up existing sidecars when policy requires it, validates managed keyword additions plus unmanaged semantic preservation, restores backups on validation failure, and rechecks source image hashes.

Folder export runs write `xmp-export-progress-<timestamp>.jsonl`, `xmp-export-report-<timestamp>.json`, and `xmp-export-summary-<timestamp>.md` in the output/report directory. Single-file runs print an essential stdout summary while still returning the in-memory report through the core pipeline. `aisidecar write-xmp <image-file-or-folder>` runs Phase 1 analysis first, preserves `.ai.json` sidecars by default, honors analyze-mode `--gps-context`, and sends successful raw sidecars through the same XMP export planner; `--no-write-ai-json` removes newly created raw sidecars after extracting report-ready provenance. `write-xmp --from-json` rejects explicit `--gps-context` because the model output already exists.

## Current Benchmark Behavior

`aisidecar benchmark` runs the Phase 1 Milestone 9a benchmark matrix. It builds `.build/release/aisidecar` by default, invokes `analyze` for each selected spec, aggregates sidecar/model-run timings, verifies no `.xmp` files were created, and writes JSON plus Markdown result documents under `benchmarks/milestone9a-YYYY-MM-DD-HHMMSS/` or the requested `--output-dir`. Use repeated `--spec` flags for focused runs, and `--self-test` for the offline aggregation check. The legacy `benchmarks/run-milestone9a.swift` script remains as a wrapper around this command.

## Current Normalize And Apply-Session Behavior

`aisidecar normalize --session-only` builds a Phase 3 normalization session, JSON report, Markdown summary, and JSONL progress log from existing `.ai.json` sidecars via `--from-json`, from a UTF-8 `--file-list`, or from positional image inputs without writing XMP. For raw sidecar inputs, the session and report record Phase 2 candidate observations, skipped-candidate reasons, vocabulary-canonicalized per-asset direct decisions, `direct_apply_policy` withholding/flat-only outcomes, hierarchy-aware batch support counts, metadata-affinity edges, local weighted consensus records, local conflict blocks, global backstop decisions, session-context user evidence, and `--normalization-mode off` Phase 2 fallback decisions. `aisidecar normalize --dry-run` builds the same normalization artifacts plus Phase 2-compatible XMP change-plan JSON, with normalized flat and hierarchical terms, same-base-name target plans, backup/validation intent, selected source members, and per-term decision provenance for direct, propagated, and user-context decisions. Normal `aisidecar normalize --from-json` and `--file-list` writes execute those normalized plans through `OwnedXMPSidecarEngine`, then update the normalization report, summary, and progress log with XMP write outcomes. Normal positional `aisidecar normalize <image-or-folder>` runs Phase 1 analysis first, preserves `.ai.json` sidecars by default, supports `--no-write-ai-json` while retaining in-memory session provenance, normalizes only successful raw sidecars after partial analysis failures, and keeps GPS context limited to model prompts/provenance rather than exported keywords. Reports and summaries include vocabulary identity, owned XMP writer identity, decision and skip counts, affinity profile/edge details, local consensus support, planned/executed XMP targets, warnings/errors, and Lightroom Classic/Capture One post-export instructions. Sessions also record the loaded vocabulary identity, resolved configuration, user session context policy results, default privacy policy, owned XMP writer identity, source AI sidecars, source assets bound to identity hashes, same-base-name groups, privacy-preserving metadata/filename/list affinity inputs, deterministic policy metadata, artifact paths, warnings, and recoverable input errors. Affinity inputs persist presence flags, normalized gear classes, and hashed serials, but not exact GPS coordinates, exact capture timestamps, or raw serial values. Session-only and dry-run paths create no `.xmp` sidecars, backups, restores, or XMP validation attempts.

`aisidecar apply-session <normalization-session.json>` reads an existing `ai-sidecar-normalization/1.0` session without rerunning analysis, candidate extraction, vocabulary matching, affinity scoring, or consensus. It rebuilds XMP plans from the stored decisions, resolves current source paths from stored paths or `--source-root`, verifies source identity, fails stale selected assets as `E_SESSION_STALE` unless `--allow-stale` is explicit, recomputes target paths from current source resolution and `--output-dir`, reads current XMP sidecars at write time, and delegates merge, backup, restore, validation, and source hash checks to the Phase 2 owned XMP writer. `apply-session --dry-run` previews current writes and writes apply report/summary/progress artifacts without creating backups, modifying sidecars, or running XMP validation.

## Next Steps

The next planned work is Phase 3 Milestone 9: interruption, concurrency, and file-safety hardening. Phase 1 Milestone 9 calibration and quality review remain required before release signoff unless explicitly deferred. Follow-up work should preserve the existing boundaries: reusable logic belongs in `AISidecarCore`, the executable stays limited to argument handling and command wiring, and default tests must remain offline with no Ollama or network dependency.
