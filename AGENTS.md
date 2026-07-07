# AGENTS.md

## Project Context

CameraVision is a Swift 6, macOS 15, SwiftPM project for local-first AI-assisted photo metadata. The single CLI executable `aisidecar` scans image folders, renders model inputs, runs a local Ollama vision model, writes auditable raw `.ai.json` sidecars (Phase 1), exports accepted keywords to XMP sidecars through a project-owned XMP engine (Phase 2), and performs vocabulary-normalized batch tagging with durable, replayable sessions (Phase 3). The SwiftUI GUI (Phase 4) is the app `CupricAspect` (`Sources/CupricAspectApp`, run via `swift run CupricAspect`): milestone M0 (scaffold, design tokens, aperture component, dual-shell skeleton) is done; feature milestones M1+ are next.

**Status:** Phase 1 Milestones 0-9a, Phase 2 Milestones 0-10, the GPS-context milestone, and Phase 3 Milestones 0-11 are implemented and released. Overall release signoff still requires Phase 1 Milestone 9 calibration evidence or an explicit deferral. Do not reopen completed milestone work without new acceptance criteria.

**The one rule to never forget:** `analyze` and all raw-sidecar paths never create or modify XMP. XMP writes happen only in `aisidecar write-xmp` and Phase 3 normalized export paths that reuse the Phase 2 export pipeline.

## Before You Change Code

1. Read `agent_docs/invariants.md` — the binding safety, compatibility, and process rules. All of them apply to every change.
2. Read `agent_docs/architecture-map.md` if you are unsure where code lives or which type is the entry point.
3. Read the phase requirements doc for the area you are changing (index below).
4. Verify with `agent_docs/testing-and-verification.md`; at minimum `swift test` must pass.

## Architecture Rules

- Reusable behavior goes in `Sources/AISidecarCore`; `Sources/AISidecarCLI` is argument parsing, command wiring, and presentation only.
- Preserve the single executable shape (`aisidecar` + subcommands), Swift 6 strict concurrency, and the macOS 15 minimum. macOS-only — no cross-platform annotations.
- Keep tests deterministic and offline (no Ollama, network, model downloads, or real images).
- Add or update focused unit tests in `Tests/AISidecarCoreTests` with every behavior change.
- Follow `agent_docs/commenting_guide.md` for substantive comments and public API docs.
- Implement one milestone or work item at a time unless the user explicitly expands scope.

## Commands

```bash
swift test                          # build + full offline test suite (must pass)
swift run aisidecar --help          # CLI wiring check
```

If XCTest is unavailable (Command Line Tools only), prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Full smoke-check commands (dry runs, benchmark self-test, per-phase manual checks) are in `agent_docs/testing-and-verification.md`.

## Documentation Index

Read only what your task touches.

**Always-relevant references**
- `agent_docs/invariants.md`: binding rules for every change.
- `agent_docs/architecture-map.md`: module map, key types, pipeline entry points, artifact locations.
- `agent_docs/testing-and-verification.md`: build, test, smoke-check, and release-evidence procedures.
- `agent_docs/commenting_guide.md`: before adding or revising substantive comments.
- `agent_docs/agent-md-best-practices.md`: before changing this file.

**Phase requirements and plans (read before changing that area)**
- `agent_docs/01-cli-raw-json-sidecar-requirements.md` + `agent_docs/phase-1-cli-implementation-plan.md`: analyze, raw sidecars, benchmark, rendering, model runtime, GPS context.
- `agent_docs/02-cli-xmp-sidecar-requirements-updated.md` + `agent_docs/phase-2-cli-implementation-plan(1).md`: XMP export pipeline and evidence.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md` + `agent_docs/phase-3-cli-implementation-plan-v0.3.md`: normalization.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md` + `agent_docs/phase-4-gui-implementation-plan.md` + `agent_docs/07-cupricaspect-gui-design.md`: GUI work (the CupricAspect app — requirements, milestones, and the binding visual design spec; the design handoff bundle lives in `agent_docs/gui-wrapper-for-cameravision/`).
- `agent_docs/05-efficiency-improvement-plan.md`: active refactoring/performance work items — pick items from here for efficiency tasks.
- `agent_docs/06-packaging-single-app-plan.md`: app bundling, signing, distribution.
- `agent_docs/release-evidence/`: recorded compatibility smoke evidence.

## Housekeeping

- `Package.resolved` is tracked for reproducible dependency resolution.
- `.vscode/` is ignored; do not commit editor-local launch settings.

## Compaction Instructions

When compacting or summarizing active work, preserve:

- The current milestone or work item and its acceptance criteria.
- The modified file list.
- The latest build and test command results.
- Any relevant `agent_docs/` files already consulted.
