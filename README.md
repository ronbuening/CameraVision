# CameraVision

CameraVision is a local-first macOS command-line tool for AI-assisted photo metadata workflows. It scans image folders, renders model inputs, asks a local Ollama vision model for metadata candidates, writes auditable `.ai.json` sidecars, and can export accepted or normalized keywords to XMP sidecars for Lightroom Classic and Capture One.

The project is CLI-only today. A GUI is planned separately.

## What It Does

- Runs local image analysis through Ollama; source images and derivatives are not uploaded by this tool.
- Writes Phase 1 raw AI sidecars as `<image-name>.<ext>.ai.json`.
- Exports keywords to safe XMP sidecars through `aisidecar write-xmp`.
- Builds Phase 3 normalization sessions with batch-aware keyword decisions through `aisidecar normalize`.
- Re-applies a saved normalization session without rerunning the model through `aisidecar apply-session`.
- Keeps analyze mode XMP-silent: only `write-xmp` and normalized export paths create or modify XMP files.

Supported scan extensions are `nef`, `nrw`, `cr3`, `cr2`, `arw`, `raf`, `orf`, `rw2`, `dng`, `jpg`, `jpeg`, `tif`, `tiff`, `heic`, and `png`.

## Current Status

Phase 1 Milestones 0-8, the Milestone 9a benchmark harness, Phase 2 Milestones 0-10, the pre-Phase-3 GPS context milestone, and Phase 3 Milestones 0-11 are implemented.

Phase 3 release work is complete. Overall release signoff still depends on Phase 1 Milestone 9 calibration and quality review evidence, or an explicit release-note deferral.

Compatibility evidence:

- Phase 2 XMP compatibility: `agent_docs/release-evidence/phase-2-milestone-10-compatibility-smoke.md`
- Phase 3 normalized XMP compatibility: `agent_docs/release-evidence/phase-3-milestone-11-compatibility-smoke.md`

## Prerequisites

- macOS 15 target environment.
- Xcode with Swift 6 / Swift Package Manager support.
- [Ollama](https://ollama.com/download) installed and running locally.
- A local Ollama model that supports image input. The [Ollama CLI docs](https://docs.ollama.com/cli) use `ollama pull <model>` for downloads, and the [Gemma 4 model page](https://ollama.com/library/gemma4) lists current multimodal tags such as `gemma4:26b`.

The code default is currently `gemma4:26b-a4b-it-qat` with model input profile `gemma4-26b-default`. If that exact tag is not available in your Ollama install, download a current vision-capable tag and pass it with `--model`, or set it in config.

## Setup

Install Ollama from the [macOS download page](https://ollama.com/download), then verify it is available:

```bash
ollama --version
ollama list
```

Download a local vision model. For a current public Gemma 4 workstation model:

```bash
ollama pull gemma4:26b
```

If you already use the project default tag and it is available to your Ollama install:

```bash
ollama pull gemma4:26b-a4b-it-qat
```

Make sure the Ollama service is running. The desktop app normally starts it; from a terminal you can also run:

```bash
ollama serve
```

Build and test the project:

```bash
swift test
swift run aisidecar --help
```

If `xcode-select` points at Command Line Tools and XCTest is unavailable, run SwiftPM through the installed Xcode developer directory:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
```

## Quick Start

Use `--output-dir` while investigating so generated sidecars and reports go into a staging folder instead of beside original photos.

First, inspect what the scanner sees:

```bash
swift run aisidecar analyze /path/to/photos --recursive --dry-scan
```

Run analysis and write raw `.ai.json` sidecars:

```bash
swift run aisidecar analyze /path/to/photos \
  --recursive \
  --mode both \
  --model gemma4:26b \
  --output-dir /tmp/aisidecar-ai
```

Preview XMP export from those raw sidecars:

```bash
swift run aisidecar write-xmp \
  --from-json /tmp/aisidecar-ai \
  --recursive \
  --source-root /path/to/photos \
  --dry-run \
  --output-dir /tmp/aisidecar-xmp-preview
```

Write XMP sidecars after reviewing the dry-run plan:

```bash
swift run aisidecar write-xmp \
  --from-json /tmp/aisidecar-ai \
  --recursive \
  --source-root /path/to/photos \
  --output-dir /tmp/aisidecar-xmp
```

Build a Phase 3 normalization session without writing XMP:

```bash
swift run aisidecar normalize \
  --from-json /tmp/aisidecar-ai \
  --recursive \
  --source-root /path/to/photos \
  --session-only \
  --output-dir /tmp/aisidecar-normalization
```

Preview normalized XMP output:

```bash
swift run aisidecar normalize \
  --from-json /tmp/aisidecar-ai \
  --recursive \
  --source-root /path/to/photos \
  --dry-run \
  --output-dir /tmp/aisidecar-normalized-preview
```

Write normalized XMP sidecars:

```bash
swift run aisidecar normalize \
  --from-json /tmp/aisidecar-ai \
  --recursive \
  --source-root /path/to/photos \
  --output-dir /tmp/aisidecar-normalized-xmp
```

Apply an existing normalization session later without model runs:

```bash
swift run aisidecar apply-session \
  /tmp/aisidecar-normalization/normalization-session-<timestamp>.json \
  --dry-run \
  --output-dir /tmp/aisidecar-apply-preview
```

## Main Commands

| Command | Purpose |
|---|---|
| `aisidecar analyze` | Scan images, render model inputs, call Ollama, and write raw `.ai.json` sidecars. |
| `aisidecar write-xmp` | Export accepted raw-sidecar candidates to XMP sidecars, or run analyze-and-write in one command. |
| `aisidecar normalize` | Build Phase 3 normalized decisions, sessions, reports, dry-run plans, or normalized XMP writes. |
| `aisidecar apply-session` | Apply stored normalization decisions without rerunning analysis or recomputing consensus. |
| `aisidecar benchmark` | Run the Phase 1 Milestone 9a benchmark harness. |
| `aisidecar purge` | Remove derivative-cache artifacts. |
| `aisidecar cleanup` | Remove owned raw sidecars and run/report artifacts from a folder. |

Every command has help:

```bash
swift run aisidecar <command> --help
```

## Common Workflows

**Analyze only**

Use this when you want auditable AI output but no XMP sidecars:

```bash
swift run aisidecar analyze /path/to/photo-or-folder --mode both --recursive --model gemma4:26b --output-dir /tmp/aisidecar-ai
```

**Analyze and write XMP in one command**

Use this after you are comfortable with the export behavior:

```bash
swift run aisidecar write-xmp /path/to/photos --recursive --mode both --model gemma4:26b --output-dir /tmp/aisidecar-xmp
```

**Analyze and normalize in one command**

Use this for the current Phase 3 batch-aware path:

```bash
swift run aisidecar normalize /path/to/photos --recursive --mode both --model gemma4:26b --output-dir /tmp/aisidecar-normalized-xmp
```

**Inspect exact model inputs**

Use this before a real model run when you want to see what the model will receive:

```bash
swift run aisidecar analyze /path/to/photos --mode both --export-model-inputs /tmp/aisidecar-model-inputs
```

**Run offline checks**

```bash
swift test
swift run aisidecar benchmark --self-test
```

## Output Files

- `.ai.json`: raw AI sidecar with source identity, model provenance, prompts/schemas, candidates, and run records.
- `.xmp`: metadata sidecar written by the owned XMP parser/writer path.
- `*-progress-*.jsonl`: JSONL progress logs for folder/batch operations.
- `*-report-*.json`: machine-readable run report.
- `*-summary-*.md`: human-readable run summary.
- `normalization-session-*.json`: durable Phase 3 session that `apply-session` can reuse.
- Derivative cache: regenerable render artifacts under `~/Library/Caches/aisidecar/derivatives` by default.

Lightroom Classic and Capture One should read generated XMP sidecars after you import/synchronize metadata according to each application's normal XMP workflow.

## Configuration

Configuration precedence is:

```text
CLI flag > AISIDECAR_* environment variable > JSON config file > built-in default
```

Default config path:

```text
~/Library/Application Support/aisidecar/config.json
```

Use `--config <path>` or `AISIDECAR_CONFIG` to point at another file.

The reference template is [aisidecar.config.example.jsonc](aisidecar.config.example.jsonc). It is commented JSONC for humans; the real loader accepts strict JSON only, so remove comments and unused keys before saving it as a config file.

Minimal example for using the current public Gemma 4 26B tag:

```json
{
  "model": "gemma4:26b",
  "model_endpoint": "http://localhost:11434",
  "profile": "gemma4-26b-default",
  "gps_context": "coarse",
  "stage_concurrency": 1
}
```

Useful knobs:

- `--model <tag>` or `"model"`: choose the installed Ollama vision model.
- `--model-endpoint <url>` or `"model_endpoint"`: point at a non-default Ollama endpoint.
- `--stage-concurrency 1`: lower memory pressure by making render/isolation preparation serial.
- `--gps-context off|coarse|exact`: control prompt-only GPS context. GPS is never exported as an XMP keyword by itself.
- `--existing skip|overwrite|fail`: choose how raw sidecar collisions are handled.
- `--pair-scope union|raw-only|jpeg-only`: choose RAW/JPEG same-base-name grouping behavior.

## Safety Notes

- `analyze` writes raw `.ai.json` only; it does not create or modify XMP.
- `--export-model-inputs` writes only rendered diagnostic inputs and a manifest. It does not call the model or write sidecars.
- `--dry-run` on XMP and normalization paths writes plans/reports but does not modify XMP sidecars.
- XMP writes use the project-owned parser/writer, deterministic backups, source hash checks, and post-write validation.
- GPS context can influence prompts and raw-sidecar provenance, but coordinates and GPS-only evidence are guarded from keyword export.
- `cleanup` does not remove source images, `.xmp` sidecars, XMP backups, model-input exports, debug derivative copies, derivative-cache files, or normalization session JSON.

## Troubleshooting

**`E_MODEL_TAG_NOT_FOUND`**

The configured model is not installed, is named differently, or is not reported by Ollama as a vision-capable model. Check installed models and pass a known tag:

```bash
ollama list
swift run aisidecar analyze /path/to/photo.jpg --model gemma4:26b --output-dir /tmp/aisidecar-ai
```

**Cannot connect to Ollama**

Start the app or run `ollama serve`, then confirm the endpoint. CameraVision defaults to `http://localhost:11434`.

**Memory pressure during analysis**

Use a smaller vision model, set `--stage-concurrency 1`, avoid `--mode both` for the first pass, and write to a staging `--output-dir`.

**XCTest unavailable**

Point SwiftPM at a full Xcode install with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Development Notes

The package layout is intentionally split:

```text
Sources/AISidecarCore/   Reusable scan, render, model, sidecar, XMP, normalization, and pipeline logic.
Sources/AISidecarCLI/    Argument parsing, command wiring, and user-facing presentation.
Tests/AISidecarCoreTests/ Offline XCTest coverage and synthetic fixtures.
agent_docs/             Requirements, implementation plans, release evidence, and agent guidance.
```

Build and verification commands:

```bash
swift test
swift run aisidecar analyze --help
swift run aisidecar write-xmp --help
swift run aisidecar normalize --help
swift run aisidecar apply-session --help
swift run aisidecar benchmark --self-test
```

## Documentation Map

- `agent_docs/01-cli-raw-json-sidecar-requirements.md`: Phase 1 raw JSON sidecar requirements.
- `agent_docs/phase-1-cli-implementation-plan.md`: Phase 1 implementation plan and benchmark context.
- `agent_docs/02-cli-xmp-sidecar-requirements-updated.md`: Phase 2 XMP export requirements.
- `agent_docs/phase-2-cli-implementation-plan(1).md`: Phase 2 implementation plan.
- `agent_docs/03-cli-normalized-batch-tagger-requirements.md`: Phase 3 normalization requirements.
- `agent_docs/phase-3-cli-implementation-plan-v0.3.md`: Phase 3 implementation plan and traceability matrix.
- `agent_docs/04-gui-sidecar-tagger-mvp-requirements.md`: Future GUI requirements.
- `agent_docs/release-evidence/`: compatibility smoke notes and release evidence.
