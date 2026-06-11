# Phase 1 Milestone 9a Benchmarks

Milestone 9a is timing, schema-validity, and conservative default calibration only. It does not score tag quality, foreground-mask quality, or instance-selection correctness; those axes are deferred to Milestone 9b.

## Sample Corpus

Place rights-cleared benchmark images in `benchmarks/samples/` and list them in `benchmarks/samples/manifest.json`.

For the first committed corpus, use:

- 23 JPG files from public domain US Department of the Interior imagery.
- Varied wildlife, landscape, landmark, architecture, cultural, and people-centered subjects.
- Varied dimensions, aspect ratios, and file sizes, including high-resolution images.

HEIC, TIFF, NEF, and RAF timing remain deferred/manual until rights-cleared samples are available.

## Running

Offline aggregation self-test:

```sh
swift benchmarks/run-milestone9a.swift --self-test
```

Full benchmark run with the default local model:

```sh
swift benchmarks/run-milestone9a.swift
```

Useful options:

```sh
swift benchmarks/run-milestone9a.swift --model gemma4:26b-a4b-it-qat --iterations 1
swift benchmarks/run-milestone9a.swift --samples benchmarks/samples/manifest.json --output-dir benchmarks
swift benchmarks/run-milestone9a.swift --skip-build
swift benchmarks/run-milestone9a.swift --skip-build --spec profile-gemma4-26b-benchmark-1024-whole --spec source-identity-sha256 --max-hash-copies 60
```

The script builds `.build/release/aisidecar`, runs the Milestone 9a matrix, checks that no `.xmp` files were created under each run directory, and writes date/time stamped results:

```text
benchmarks/milestone9a-YYYY-MM-DD-HHMMSS/
  benchmark-results-YYYY-MM-DD-HHMMSS.json
  benchmark-results-YYYY-MM-DD-HHMMSS.md
```

Generated `benchmarks/milestone9a-*` and self-test output directories are ignored by git because they contain machine-local timing data, copied sample inputs, sidecars, logs, and scratch caches. Each benchmark spec enables derivative cache clearing in the generated config and the script removes the per-spec cache directory after collecting metrics. The copied `input-samples/` and `hash-input-*` scratch directories are removed after the result report is written.

## Matrix

The script measures:

- Profile sweep: `gemma4-26b-benchmark-1024`, `gemma4-26b-benchmark-1536`, and `gemma4-26b-default` for `whole` and `subject` modes.
- `model_keep_alive`: `0`, `5m`, and `30m`.
- `stage_concurrency`: `2`, `4`, `6`, `8`, and the built-in default.
- Source identity cost: `sha256` and `fast` over scratch-expanded sample copies using `--dry-scan`.

## Calibration Rules

Use the benchmark output conservatively:

- Keep the 2048 default profile unless timing shows an operational failure.
- Choose the lowest `stage_concurrency` within 5% of fastest median throughput that avoids failures and memory pressure.
- Choose the smallest `model_keep_alive` that avoids reloads across the benchmark batch; otherwise keep `30m`.
- Do not use these timing-only results to claim visual quality improvements or regressions.
