# CameraVision

CameraVision is a local macOS utility for generating AI-assisted image metadata for photo workflows. The long-term goal is to support Lightroom and Capture One sidecar workflows, but the current implementation is in Phase 1: generating auditable raw AI JSON sidecars before any XMP writeback exists.

## Current State

Phase 1 Milestones 0-8 and the Milestone 9a benchmark harness are implemented. Phase 1 still produces only auditable raw AI JSON sidecars; XMP writeback starts in Phase 2.

The repository currently contains:

- A Swift Package Manager project targeting macOS 15 and Swift 6.
- `AISidecarCore`, the shared library where reusable project logic lives.
- `aisidecar`, the command-line executable.
- `aisidecar analyze` command wiring with the Phase 1 shared flag surface, `aisidecar benchmark` for Milestone 9a timing/validity runs, and `aisidecar purge` for derivative cache maintenance.
- A reusable `AISidecarCore/Benchmarking` harness for benchmark specs, result documents, sidecar metric aggregation, no-XMP checks, scratch cleanup, and offline self-test.
- Configuration resolution with precedence: CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default.
- The frozen Phase 1 structured error taxonomy.
- Text and JSON log rendering.
- File and folder scanning with supported-extension filtering, hidden/system/sidecar exclusion, relative path recording, and source identity hashing.
- `aisidecar analyze ... --dry-scan` JSON output.
- Raw `.ai.json` sidecar writing with extension-preserving names and mirrored output trees.
- Model input profile resolution for the built-in `gemma4-26b-default` profile.
- Whole-image rendering with EXIF orientation baking, sRGB output, full-resolution render retention, and profile-conforming JPEG derivatives.
- Content-addressed derivative caching with manifest-backed LRU eviction, configurable cache directory/size, opt-in start/success cache clearing, and explicit purge command.
- Subject isolation with Apple Vision foreground masks, deterministic instance selection/merge policy, full-resolution crop/matte compositing, and `subject_isolated` derivative provenance.
- Diagnostic model-input export via `--export-model-inputs` for reviewing the exact images that model calls receive.
- Versioned whole-image and subject-isolated prompts plus bundled v1.3 response schemas.
- A reusable Ollama vision model runtime layer with tag/digest verification, runtime provenance, `/api/chat` request encoding, response parsing, schema validation, schema-constrained response repair, retry/error classification, and mock/recorded-fixture runners.
- Full `aisidecar analyze` model execution with populated `model_runs` records, prompt/schema provenance, model digest/runtime provenance, raw response preservation, parsed JSON when valid, and optional per-attempt response provenance when repair is used.
- Bounded render/isolation preparation through `stage_concurrency`, feeding a serialized single-flight model stage.
- JSON/env configuration for subject crop margin and merge dominance threshold.
- JSON/env/CLI configuration for `stage_concurrency`, model response repair attempts, and derivative cache clearing.
- Atomic writes for sidecars and batch summaries.
- `--existing skip|overwrite|fail` handling.
- Optional `--debug-derivatives` copies beside source images.
- Folder-run JSONL progress logs and derived batch summaries.
- SIGINT/SIGTERM-aware interruption handling for the full analyze pipeline.
- Offline XCTest coverage for config resolution, validation, logging, error serialization, scanning, source identity, sidecar naming/writing, schema-evolution sidecar rewrites, rendering, derivative cache behavior and purge resolution, subject-isolation geometry/pipeline behavior, model-runtime behavior including repair success/failure, progress logs, summaries, diagnostic export, golden sidecars, no-XMP Phase 1 guards, the shell pipeline, and the full analyze pipeline.

Not implemented yet:

- XMP output of any kind.

## Repository Layout

```text
Sources/
  AISidecarCore/       Shared engine code for all phases.
    Benchmarking/      Milestone 9a benchmark runner, result documents, and aggregation.
    Configuration/     Config defaults, validation, and precedence.
    Errors/            Frozen Phase 1 structured error taxonomy.
    FileScanning/      Input discovery and source image records.
    Identity/          Source content identity hashing.
    ModelRuntime/      Ollama runner, model-run records, JSON schema validation, and test runners.
    Rendering/         Model input profiles, render recipes, renderer, and derivative cache.
    Pipeline/          Full analyze pipeline, analyze shell pipeline, and diagnostic model-input export.
    Reporting/         CLI logs, JSONL progress logs, batch summaries.
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
- `agent_docs/02-cli-xmp-sidecar-requirements.md` - Phase 2 requirements.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md` - Phase 3 requirements.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` - Phase 4 requirements.
- `agent_docs/commenting_guide.md` - Commenting rules for Swift source and tests.
- `agent_docs/agent-md-best-practices.md` - Guidance used for `AGENTS.md`.

## Build And Test

The project uses SwiftPM and depends on Swift ArgumentParser.

```bash
swift test
swift run aisidecar analyze --help
swift run aisidecar benchmark --help
swift run aisidecar purge --help
swift run aisidecar benchmark --self-test
swift run aisidecar analyze <folder> --recursive --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode subject --debug-derivatives --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode both --export-model-inputs <tmp-output>
swift run aisidecar benchmark --spec source-identity-fast --max-hash-copies 1 --output-dir <tmp-output>
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar analyze --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar benchmark --help
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar purge --help
```

## Current Analyze Behavior

`aisidecar analyze` currently performs the full Phase 1 analyze pipeline. It scans inputs, computes source identities, verifies the configured Ollama model tag at startup, renders full-resolution and whole-image derivatives, optionally isolates foreground subjects for `--mode subject|both`, runs the model with versioned prompts and response schemas, and writes schema-versioned `.ai.json` sidecars with model input profile, derivative provenance, subject-isolation provenance, and populated `model_runs`. Invalid model JSON or schema violations get one schema-constrained no-image repair attempt by default; set `model_response_repair_attempts` or `--model-response-repair-attempts 0` to disable repair. Folder runs write JSONL progress and batch summary artifacts. The render/isolation stage is bounded by `stage_concurrency`, while model requests are serialized with one in-flight request. The derivative cache is retained by default; set `clear_derivative_cache_on_start` or `clear_derivative_cache_after_success` in config, or use the matching CLI flags, to clear cache artifacts at those run boundaries.

For visual validation, `--export-model-inputs <folder>` switches `analyze` into the diagnostic export path. It renders through the same cache and subject-isolation pipeline, mirrors source relative paths under the export folder, writes only `whole_image` and/or `subject_isolated` model-input files, and writes a timestamped `model-input-export-*.json` manifest. It does not write `.ai.json` sidecars, progress logs, batch summaries, XMP, or model output. `--dry-run` and `--debug-derivatives` are rejected in this mode because export mode writes only to the requested export folder.

`aisidecar purge` removes derivative cache artifacts from the resolved cache directory. It honors `--config`, `--cache-dir`, `AISIDECAR_CONFIG`, and `AISIDECAR_DERIVATIVE_CACHE_DIR`; it does not contact Ollama or validate analyze-only model settings.

Cache cleanup is scoped to files owned by the derivative cache manifest or matching aisidecar's deterministic derivative names, so unrelated files in a misconfigured cache directory are not intentionally removed.

## Current Benchmark Behavior

`aisidecar benchmark` runs the Phase 1 Milestone 9a benchmark matrix. It builds `.build/release/aisidecar` by default, invokes `analyze` for each selected spec, aggregates sidecar/model-run timings, verifies no `.xmp` files were created, and writes JSON plus Markdown result documents under `benchmarks/milestone9a-YYYY-MM-DD-HHMMSS/` or the requested `--output-dir`. Use repeated `--spec` flags for focused runs, and `--self-test` for the offline aggregation check. The legacy `benchmarks/run-milestone9a.swift` script remains as a wrapper around this command.

## Next Steps

The next planned work is completing Phase 1 Milestone 9 calibration and quality review, then starting Phase 2 XMP writeback. Milestone 9 follow-up should preserve the existing boundaries: reusable logic belongs in `AISidecarCore`, the executable stays limited to argument handling and command wiring, and default tests must remain offline with no Ollama or network dependency.
