# AGENTS.md

## Project Context

CameraVision is a Swift 6 macOS 15 SwiftPM project for local AI-assisted photo metadata workflows. The current implemented state is Phase 1 Milestone 4: package scaffold, CLI surface, config resolution, structured errors, logging, scanner/source identity, `--dry-scan`, sidecar naming, output tree mirroring, raw JSON sidecar writes, JSONL progress logs, batch summaries, interruption handling, model input profiles, whole-image rendering, full-resolution render retention, derivative cache, subject isolation with the two-resolution Apple Vision/Core Image chain, and offline tests.

Phase 1 produces raw `.ai.json` sidecars. It must not create or modify XMP files. XMP writeback begins in Phase 2.

## Architecture Rules

- Put reusable behavior in `Sources/AISidecarCore`.
- Keep `Sources/AISidecarCLI` limited to argument parsing, command wiring, and user-facing presentation.
- Preserve the single executable shape: `aisidecar` with phase-specific subcommands.
- Preserve Swift 6 strict concurrency and macOS 15 minimum deployment.
- Keep tests deterministic and offline. Unit tests must not require Ollama, model downloads, images, or network access.

## Current Layout

- `Package.swift` defines `AISidecarCore`, `AISidecarCLI`, and `AISidecarCoreTests`.
- `Sources/AISidecarCore/Configuration` owns config defaults and precedence.
- `Sources/AISidecarCore/Errors` owns the frozen Phase 1 error code set.
- `Sources/AISidecarCore/FileScanning` owns scanner/source image records.
- `Sources/AISidecarCore/Identity` owns source content identity hashing.
- `Sources/AISidecarCore/Rendering` owns model input profiles, render recipes, whole-image rendering, and the derivative cache.
- `Sources/AISidecarCore/SubjectIsolation` owns foreground mask generation, instance selection/merge policy, two-resolution subject crops, and subject-isolation provenance.
- `Sources/AISidecarCore/Sidecars` owns raw `.ai.json` sidecar naming, schema records, and atomic writes.
- `Sources/AISidecarCore/Reporting` owns text/JSON logging, JSONL progress logs, and batch summaries.
- `Sources/AISidecarCore/Pipeline` owns the current Milestone 4 analyze shell pipeline.
- `Sources/AISidecarCLI` owns `aisidecar analyze` command wiring and shared options.
- `Tests/AISidecarCoreTests` contains offline XCTest coverage.

## Commands

- Build and test: `swift test`.
- CLI help check: `swift run aisidecar analyze --help`.
- Manual Milestone 4 smoke check: `swift run aisidecar analyze <image-or-folder> --mode subject --debug-derivatives --output-dir <tmp-output>`.
- If XCTest is missing because `xcode-select` points at Command Line Tools, run the same commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Documentation Index

- `agent_docs/01-cli-raw-json-sidecar-requirements.md`: read before Phase 1 work.
- `agent_docs/phase-1-cli-implementation-plan.md`: read before implementing any Phase 1 milestone.
- `agent_docs/02-cli-xmp-sidecar-requirements.md`: read before Phase 2/XMP work.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md`: read before Phase 3 normalization work.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md`: read before GUI work.
- `agent_docs/commenting_guide.md`: read before adding or revising substantive code comments.
- `agent_docs/agent-md-best-practices.md`: read before changing this file.

## Implementation Guidance

- Implement one milestone at a time unless the user explicitly expands scope.
- The next planned unit is Phase 1 Milestone 5: Ollama vision model client.
- Do not jump ahead to XMP writing while implementing Phase 1 work.
- Keep config precedence as CLI flag > `AISIDECAR_*` environment > JSON config file > built-in default.
- Preserve stable raw string values for public enums and error codes because later sidecars and logs depend on them.
- Follow `agent_docs/commenting_guide.md` whenever creating or updating types, methods, or substantive logic: add `///` documentation for reusable public API and inline comments for intent, constraints, requirement ties, and non-obvious domain behavior rather than restating code.
- Add or update tests with each behavior change. Prefer focused unit tests in `AISidecarCoreTests`.
- `Package.resolved` is tracked to keep dependency resolution reproducible.
- `.vscode/` is ignored; do not include editor-local launch settings in commits.

## Compaction Instructions

When compacting or summarizing active work, preserve:

- The current milestone and acceptance criteria.
- The modified file list.
- The latest build and test command results.
- Any relevant `agent_docs/` files already consulted.
