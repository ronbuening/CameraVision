# Sample_Data_Versioned

Archived sidecar outputs from running the same 18-image public-domain test set
(`TestingFileSet/PublicDomainDOI`, gemma4:26b-a4b-it-qat via local Ollama,
seed 0 / temperature 0, so same-configuration runs are deterministic) against
different program versions and quality configurations. Used as cross-version
regression evidence; each sidecar's `run_configuration` block records the
authoritative provenance (`task_profile`, `quality_scan_mode`, prompt versions).

Always verify a run's `run_configuration` before comparing — folder names are
labels, not provenance.

| Run | Program | Configuration | Notes |
|---|---|---|---|
| `0.1.0-beta3/260719_run0` | 0.1.0-beta3 | `tagging` (prompt 1.5.0) | Pre-quality baseline. |
| `0.2.0-beta1/260719_run0` | 0.2.0-beta1 | `tagging` (prompt 1.5.0) | Parsed model outputs bit-identical to the 0.1.0-beta3 run — no cross-version regression. |
| `0.2.0-beta1/260719_run1` | 0.2.0-beta1 | `tagging_with_quality`, combined (prompt 1.6.0) | Inline `quality_assessment`. Vs run0: ~55% keyword overlap, secondary subjects thinned 42→29, and subject-quality concerns include isolation/masking artifacts. |
| `0.2.0-beta1/260719_run2` | 0.2.0-beta1 | `tagging_with_quality`, combined | Accidental replay of run1's configuration (sequential mode was not enabled); parsed outputs bit-identical to run1. Kept as a determinism demonstration. |
| `0.2.0-beta1/260719_run3` | 0.2.0-beta1 | `tagging_with_quality`, **sequential** | First sequential (`--quality-scan-mode sequential`) archive: paired `.ai.json` + `.quality.ai.json`. Tagging pass bit-identical to run0 across all 26 model runs; dedicated quality pass shows no masking-artifact false positives, rates focus on 10/18 whole-image (vs 6 in run1), confidence high 26/26; ~1.8× model wall clock vs combined. |
| `0.2.0-beta1/260719_run4` | 0.2.0-beta1 | `tagging_with_quality`, **sequential** | Maintainer-generated sequential run, same paired layout as run3. |
