# CameraVision

CameraVision is a local macOS utility for generating AI-assisted image metadata for photo workflows. The long-term goal is to support Lightroom and Capture One sidecar workflows, but the current implementation is in Phase 1: generating auditable raw AI JSON sidecars before any XMP writeback exists.

## Current State

Milestone 4.5 of Phase 1 is implemented.

The repository currently contains:

- A Swift Package Manager project targeting macOS 15 and Swift 6.
- `AISidecarCore`, the shared library where reusable project logic lives.
- `aisidecar`, the command-line executable.
- `aisidecar analyze` command wiring with the Phase 1 shared flag surface.
- Configuration resolution with precedence: CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default.
- The frozen Phase 1 structured error taxonomy.
- Text and JSON log rendering.
- File and folder scanning with supported-extension filtering, hidden/system/sidecar exclusion, relative path recording, and source identity hashing.
- `aisidecar analyze ... --dry-scan` JSON output.
- Raw `.ai.json` sidecar writing with extension-preserving names and mirrored output trees.
- Model input profile resolution for the built-in `gemma4-26b-default` profile.
- Whole-image rendering with EXIF orientation baking, sRGB output, full-resolution render retention, and profile-conforming JPEG derivatives.
- Content-addressed derivative caching with manifest-backed LRU eviction and configurable cache directory/size.
- Subject isolation with Apple Vision foreground masks, deterministic instance selection/merge policy, full-resolution crop/matte compositing, and `subject_isolated` derivative provenance.
- Diagnostic model-input export via `--export-model-inputs` for reviewing the exact images that future model calls will receive.
- JSON/env configuration for subject crop margin and merge dominance threshold.
- Atomic writes for sidecars and batch summaries.
- `--existing skip|overwrite|fail` handling.
- Optional `--debug-derivatives` copies beside source images.
- Folder-run JSONL progress logs and derived batch summaries.
- SIGINT/SIGTERM-aware interruption handling for the analyze shell pipeline.
- Offline XCTest coverage for config resolution, validation, logging, error serialization, scanning, source identity, sidecar naming/writing, rendering, derivative cache behavior, subject-isolation geometry/pipeline behavior, progress logs, summaries, and the shell pipeline.

Not implemented yet:

- Ollama model calls.
- XMP output of any kind.

## Repository Layout

```text
Sources/
  AISidecarCore/       Shared engine code for all phases.
    Configuration/     Config defaults, validation, and precedence.
    Errors/            Frozen Phase 1 structured error taxonomy.
    FileScanning/      Input discovery and source image records.
    Identity/          Source content identity hashing.
    Rendering/         Model input profiles, render recipes, renderer, and derivative cache.
    Pipeline/          Analyze shell pipeline and diagnostic model-input export.
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
swift run aisidecar analyze <folder> --recursive --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode subject --debug-derivatives --output-dir <tmp-output>
swift run aisidecar analyze <image-or-folder> --mode both --export-model-inputs <tmp-output>
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar analyze --help
```

## Current Analyze Behavior

`aisidecar analyze` currently performs the Milestone 4 shell pipeline. It scans inputs, computes source identities, renders full-resolution and whole-image derivatives, optionally isolates foreground subjects for `--mode subject|both`, writes schema-versioned `.ai.json` sidecars with model input profile, derivative provenance, and subject-isolation provenance, records recoverable per-file errors, and writes batch progress/summary artifacts for folder runs. It does not call Ollama or write XMP.

For pre-model visual validation, `--export-model-inputs <folder>` switches `analyze` into the Milestone 4.5 diagnostic export path. It renders through the same cache and subject-isolation pipeline, mirrors source relative paths under the export folder, writes only `whole_image` and/or `subject_isolated` model-input files, and writes a timestamped `model-input-export-*.json` manifest. It does not write `.ai.json` sidecars, progress logs, batch summaries, XMP, or model output. `--dry-run` and `--debug-derivatives` are rejected in this mode because export mode writes only to the requested export folder.

## Next Steps

The next planned implementation unit is Phase 1 Milestone 5: Ollama vision model client.

Milestone 5 should preserve the existing boundaries: reusable logic belongs in `AISidecarCore`, the executable stays limited to argument handling and command wiring, and tests must remain offline with no Ollama or network dependency.
