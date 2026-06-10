# CameraVision

CameraVision is a local macOS utility for generating AI-assisted image metadata for photo workflows. The long-term goal is to support Lightroom and Capture One sidecar workflows, but the current implementation is in Phase 1: generating auditable raw AI JSON sidecars before any XMP writeback exists.

## Current State

Milestone 1 of Phase 1 is implemented.

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
- Offline XCTest coverage for config resolution, validation, logging, error serialization, scanning, and source identity.

Not implemented yet:

- RAW/JPEG rendering and derivative caching.
- Apple Vision subject isolation.
- Ollama model calls.
- Raw `.ai.json` sidecar writing.
- XMP output of any kind.

## Repository Layout

```text
Sources/
  AISidecarCore/       Shared engine code for all phases.
  AISidecarCLI/        CLI argument handling and command presentation only.
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
- `agent_docs/agent-md-best-practices.md` - Guidance used for `AGENTS.md`.

## Build And Test

The project uses SwiftPM and depends on Swift ArgumentParser.

```bash
swift test
swift run aisidecar analyze --help
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run aisidecar analyze --help
```

## Next Steps

The next planned implementation unit is Phase 1 Milestone 2: sidecar naming, output tree mirroring, atomic writes, progress logging, and batch summaries.

Milestone 2 should preserve the existing boundaries: reusable logic belongs in `AISidecarCore`, the executable stays limited to argument handling and presentation, and tests must remain offline with no Ollama or network dependency.
