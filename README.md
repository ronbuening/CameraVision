# CameraVision

CameraVision is a local macOS utility for generating AI-assisted image metadata for photo workflows. The long-term goal is to support Lightroom and Capture One sidecar workflows, but the current implementation is in Phase 1: generating auditable raw AI JSON sidecars before any XMP writeback exists.

## Current State

Milestone 2 of Phase 1 is implemented.

The repository currently contains:

- A Swift Package Manager project targeting macOS 15 and Swift 6.
- `AISidecarCore`, the shared library where reusable project logic lives.
- `aisidecar`, the command-line executable.
- `aisidecar analyze` command scaffolding with the Phase 1 shared flag surface.
- Configuration resolution with precedence: CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default.
- The frozen Phase 1 structured error taxonomy.
- Text and JSON log rendering.
- File and folder scanning with supported-extension filtering, hidden/system/sidecar exclusion, relative path recording, and source identity hashing.
- `aisidecar analyze ... --dry-scan` JSON output.
- Raw `.ai.json` sidecar shell writing with extension-preserving names and mirrored output trees.
- Atomic writes for sidecars and batch summaries.
- `--existing skip|overwrite|fail` handling.
- Folder-run JSONL progress logs and derived batch summaries.
- SIGINT/SIGTERM-aware interruption handling for the Milestone 2 shell pipeline.
- Offline XCTest coverage for config resolution, validation, logging, error serialization, scanning, source identity, sidecar naming/writing, progress logs, summaries, and the shell pipeline.

Not implemented yet:

- RAW/JPEG rendering and derivative caching.
- Apple Vision subject isolation.
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
    Pipeline/          Current analyze shell pipeline.
    Reporting/         CLI logs, JSONL progress logs, batch summaries.
    Sidecars/          Raw JSON sidecar naming and atomic shell writes.
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
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar analyze --help
```

## Current Analyze Behavior

`aisidecar analyze` currently performs the Milestone 2 shell pipeline. It scans inputs, computes source identities, writes minimal schema-versioned `.ai.json` sidecars, records recoverable per-file errors, and writes batch progress/summary artifacts for folder runs. It does not render images, isolate subjects, call Ollama, or write XMP.

## Next Steps

The next planned implementation unit is Phase 1 Milestone 3: rendering and derivative cache. It should add model input profiles, render recipes, EXIF orientation baking, sRGB conversion, full-resolution render retention, content-addressed derivative cache keys, and focused offline tests.

Milestone 3 should preserve the existing boundaries: reusable logic belongs in `AISidecarCore`, the executable stays limited to argument handling and command wiring, and tests must remain offline with no Ollama or network dependency.
