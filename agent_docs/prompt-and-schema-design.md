# Prompt and Response-Schema Design (v1.5.0 / v1.6.0)

How the Phase 1 vision prompts and response schemas work, why v1.5.0 is shaped
the way it is, and exactly what to touch when shipping the next version. Written
so an engineer who has never opened `ModelRuntime/` can do the whole job.

## Where everything lives

| Piece | Path |
| --- | --- |
| Prompts (versioned, immutable once shipped) | `Sources/AISidecarCore/Resources/ModelRuntime/Prompts/<role>_vX.Y.Z.txt` |
| Response schemas (versioned, immutable once shipped) | `Sources/AISidecarCore/Resources/ModelRuntime/Schemas/<role>_vX.Y.Z.json` |
| Active-version selection | `PromptRegistry.resourceName(for:)` and `ResponseSchemas.resourceName(for:)` |
| GPS context block | `ModelInputContext.promptBlock` (`ModelInputContext.swift`) |
| Local validator + repair loop | `JSONSchemaValidator.swift`, `OllamaVisionRunner.analyze` |
| Downstream keyword guards | `CandidateExtractor.swift` |

Roles are `whole_image` and `subject_isolated`. Old version files are never
edited or deleted (invariant 7/8) — a new version is a new pair of files plus a
registry pointer change.

## v1.6.0 and quality-only v1.0.0 contracts

`ModelTaskProfile` selects the immutable prompt/schema pair for each role. The
resolved profile is recorded as `run_configuration.task_profile` in every raw
sidecar, so a consumer can identify the contract without inferring it from a
response field. Sidecars produced before this field existed decode as
`tagging`, preserving the v1.5.0 default.

| Task profile | Whole-image contract | Subject-isolated contract | Use |
| --- | --- | --- | --- |
| `tagging` | v1.5.0 tagging | v1.5.0 tagging | Default tagging behavior. |
| `tagging_with_quality` | v1.6.0 tagging + quality | v1.6.0 tagging + quality | `analyze --assess-quality`, or the analyze-and-write form of `write-xmp --assess-quality`. |
| `quality_only` | v1.0.0 quality-only | v1.0.0 quality-only | Reserved for the later `assess-quality` pipeline. |

The pipeline passes one resolved profile to both registries, making prompt and
schema selection atomic. The combined quality flow is deliberately opt-in:
the assessment adds roughly 200–350 output tokens and about 300 prompt tokens
to measured v1.5.0 runs (median 577, p99 796 output tokens under the 2048
cap). IQ-M5 must record real-model `runtime_metrics.eval_count` evidence before
quality is considered for any default.

## The constraint that shapes everything: Ollama's grammar

Every model call sends a response schema through Ollama's `format` field,
which compiles it to a token-level grammar (llama.cpp GBNF).

**How enforcement actually works.** This is constrained *sampling*, not
post-hoc filtering: at every generation step, the grammar computes the set of
tokens that keep the output structurally valid, and every other token's
probability is zeroed before sampling. After `"confidence": ` the only legal
continuations are `"high"`, `"medium"`, or `"low"`; once the root object's
closing brace is emitted, only end-of-sequence is legal. That last property is
a diagnostic tool: output *after* a closed root object (e.g. a `#`-separated
repeated object) is proof that enforcement was off for that call, because the
grammar makes it impossible.

What the grammar can guarantee is structure. What it cannot do:

- **Force completion.** If generation stops early — the
  `model_max_response_tokens` cap or a filled context window — the result is a
  syntactically valid *prefix*, not a complete document. Truncation is the one
  invalid-JSON path that survives grammar enforcement; the repair call exists
  for it.
- **Judge semantics.** Nothing about a grammar makes a species real or an
  evidence string visual. That is the prompt's and the downstream guards' job.

The full enforcement stack, in order, so a failure at any layer is caught by
the next:

1. Grammar (wire schema via `format`) — structure, required keys, enums,
   item/length bounds, at token level.
2. `JSONSchemaValidator` — the full authoritative contract, including the
   `pattern` rules the wire schema drops.
3. Repair call — truncated/invalid responses, re-generated under the same
   grammar with no image attached.
4. `CandidateExtractor` guards — semantics (GPS evidence, coordinate terms,
   species without a biological genre) that no schema can express.

The grammar supports only a subset of JSON Schema, and **one unsupported
keyword silently disables enforcement for the whole schema**. Established by
live probing Ollama 0.30.10 + gemma4 with progressively reduced schemas
(2026-07-09):

**Enforced at generation time:** `type`, `properties`, `required`,
`additionalProperties: false`, `enum`, `items`, array `minItems`/`maxItems`,
and string `minLength`/`maxLength`.

**Poison pills — their presence anywhere degrades the entire call to
unconstrained JSON:** `$ref`/`$defs` and `pattern`. Symptoms of the fallback:
bare-string arrays, missing required keys, comma-joined keyword dumps, and
temperature-0 repetition loops that run until the context window fills.

**Silently ignored (harmless but unenforced):** `allOf`, `if`/`then`/`else`,
`not`, `contains` — any conditional or combinator logic.

Because the bundled schemas legitimately use `$defs` and `pattern`,
`OllamaWireSchema` (in `ModelRuntime/`) derives the **wire schema** actually
sent to Ollama: every `$ref` inlined; `pattern`, `description`, `$schema`,
`$id`, and `title` stripped. Local validation still runs against the full
authoritative schema, and sidecars record the authoritative version. When
editing schemas, edit the authoritative file — the wire form is derived — but
never add a construct to the authoritative schema that the transform doesn't
strip and Ollama can't enforce, without extending the transform and re-probing.

Keeping `maxLength` in the wire schema matters beyond validation: the 220-char
evidence bound is what structurally stops in-string repetition loops. The
`model_max_response_tokens` option (Ollama `num_predict`, default 2048) is the
backstop when generation runs away anyway — healthy responses run 350–800
tokens.

Consequences, learned the hard way in the milestone-9a benchmarks and the
2026-07-09 TestingFileSet runs:

1. **Anything the model must always emit goes in top-level `required`.**
   Schema 1.4.0 made `species` conditionally required via `allOf`/`if`/`then`;
   the grammar ignored that, the model omitted the optional field, the local
   validator rejected the response, and an image-less repair call could only
   patch in `species: []` — losing the identification and paying a second model
   call. Schema 1.5.0 requires `species` unconditionally (empty array when not
   applicable). The dominant real-model schema failure disappeared with it.
2. **Conditional rules move downstream.** "Species only for wildlife /
   bird_photography / plant_botanical genres" is now enforced by
   `CandidateExtractor` (skip reason `species_without_biological_genre`). The
   guard is deliberately lenient: it fires only when a genre list is present
   without a biological entry, so older or partially parsed sidecars that lack
   a genre list keep their species terms.
3. **Field emission order is alphabetical, not what the schema file says.**
   The schema is decoded into a Swift dictionary and re-encoded with
   `.sortedKeys` (`JSONCoding`), so the grammar forces the model to emit
   `proposed_keywords` before `species`, and within candidates `confidence`
   before `evidence` before `term`. Don't write prompt rules that assume a
   different generation order, and don't rely on the JSON file's property
   order meaning anything.

## Token budget (small-context models)

The default local model is a quantized ~26B vision model; the context window
is the scarcest resource in the pipeline:

- Base prompt: ~700 words (~1,000 tokens) per role after the v1.5.0 rewrite
  (~45% shorter than v1.4.0). Keep it there — every rule added must earn its
  tokens against a model that reads the whole thing per image.
- Image tokens: hundreds to ~1.5k depending on model and render size (the
  `profile` config / "Model image size" GUI control decides the render).
- Output: up to 30 evidence-bearing keyword objects plus the other arrays —
  easily 1–2k tokens, hard-capped by `model_max_response_tokens` (default
  2048).
- The **repair prompt is the biggest single consumer**: it embeds the compact
  wire schema *and* a bounded head+tail slice of the invalid response
  (`OllamaVisionRunner.truncatedRepairInput`). Both bounds exist because an
  unbounded runaway response once consumed the entire window by itself,
  leaving the repair call ~90 tokens to answer in — the repair then truncated
  and failed too.

Prompt-writing rules that follow from the budget:

- Sectioned, deduplicated, positive phrasing. One statement of each rule, in
  the section where the model needs it.
- No rule that exists only "when X is configured" — conditional content is
  *injected* (see GPS below), never carried as dead weight.
- Concrete one-line examples beat paragraphs ("Good evidence: … Bad
  evidence: …").

## Runtime option tuning: `num_ctx` and `num_predict`

**`model_context_window`** (config key, `AISIDECAR_MODEL_CONTEXT_WINDOW`, GUI
controls in Settings and Step 3, choices up to 262144 for 256k models) is sent
as Ollama `num_ctx`. The built-in default is `0` — the "model default"
sentinel: no `num_ctx` is sent and Ollama sizes the window itself. Pin a
positive value when a model's own default is too small for the prompt, image
tokens, and full JSON response; the KV cache grows with the window, so bigger
is not free.

History, for anyone wondering why the default is what it is: before 2026-07,
the pipeline never sent `num_ctx` at all — the option existed but nothing set
it, so window sizing was invisibly left to Ollama. When the runaway-repair
failure was found, the default briefly became a pinned 8192 for headroom. Once
the wire schema restored grammar enforcement, the repair prompt was bounded,
and `num_predict` capped runaways, the pinned default was no longer needed and
`0` (model default) became the shipped default — the same wire behavior as the
original code, but now explicit, recorded in provenance
(`run_configuration.model_context_window`), and overridable per run.

**`model_max_response_tokens`** (config key,
`AISIDECAR_MODEL_MAX_RESPONSE_TOKENS`, default 2048) is sent as Ollama
`num_predict`. Two facts govern tuning it:

- The model cannot see it. It is not in the prompt or the grammar, so it has
  zero influence on response quality or richness — it is purely a guillotine
  that decides where a *runaway* generation gets cut. Raising it cannot invite
  better output; it only lets a failure burn more time before repair.
- Measured across 133 schema-valid runs on the TestingFileSet (gemma4 26B,
  whole + subject roles, 2026-07-09): median 577 output tokens, p90 700,
  p99 796, maximum 811, none over 1024. A realistically maxed-out legitimate
  response (every array at its item cap, normal evidence lengths) is roughly
  1,300–1,600 tokens. 2048 therefore has ~2.5× headroom over anything real
  ever produced; the only responses that approached it were repetition loops,
  where an early cut is the point.

Retuning signal: every sidecar records `runtime_metrics.eval_count` per model
run. If valid responses start trending toward the cap — or a `json_valid:
false` run stops at exactly the cap without being a loop — raise the config
value; do not raise it speculatively for a new model, measure first.

## GPS / external context

Since v1.5.0 the base prompts say **nothing** about GPS, EXIF, coordinates, or
external context (regression-tested in `PromptSchemaTests`). When
`gps_context` is `coarse` or `exact` and the source file has EXIF GPS, the
pipeline appends the self-contained `MODEL INPUT CONTEXT` block from
`ModelInputContext.promptBlock`: the coordinates plus all four usage rules
(narrow only visually-supported IDs; never the sole reason; never cite in
evidence; never output coordinate terms).

Invariant 3's defense in depth, in order:

1. Prompt block tells the model not to cite or output GPS.
2. `CandidateExtractor` drops coordinate-like terms
   (`coordinate_like_term`) and candidates whose evidence cites GPS
   (`gps_only_evidence`) — model mistakes never reach XMP.
3. Normalization mirrors those skip reasons and blocks the observations from
   the observed-tag vocabulary.

If you add a new context type (season, elevation, …), follow the same shape:
a self-contained injected block owning both the data and its rules, plus a
downstream guard for model mistakes. Do not add it to the base prompt.

## Shipping a new prompt/schema version — checklist

1. Copy the current prompt/schema files to the new version number; edit the
   copies. Update `PROMPT_VERSION:` header and schema `$id`/`title`.
2. Point `PromptRegistry.resourceName(for:)` and
   `ResponseSchemas.resourceName(for:)` at the new names.
3. Keep the schema grammar-friendly: everything mandatory in `required`, no
   `allOf`/`if`/`then`/`else`/`not`/`contains`, and nothing new that
   `OllamaWireSchema` doesn't already strip or Ollama can't enforce (when in
   doubt, re-probe a live Ollama with the wire form and check the output
   conforms). Conditional semantics go into
   `CandidateExtractor` with a new additive `SkippedCandidateReason` case,
   mirrored in `NormalizationCandidateSkipReason`,
   `CandidateCanonicalizer.convert`, `NormalizationDecisionExplainer`,
   `NormalizedXMPChangePlanner`, and (if it should block vocabulary
   observations) `ObservedTagVocabulary.blockedObservationKeys`.
4. Update version strings in `PromptSchemaTests`, `JSONSidecarTests`,
   `ModelRuntimeTests`, `CandidateExtractorTests`, and the golden fixture
   `Tests/AISidecarCoreTests/Fixtures/golden-sidecars/phase1-both-normalized.json`
   (prompt_version, response_schema_version; request_options /
   run_configuration values if options changed).
5. Confirm the recorded model-response fixtures in
   `Tests/AISidecarCoreTests/Fixtures/model-responses/` still validate against
   the new schema; add a new fixture generation only if the shape changed.
6. `swift test` — the golden sidecar test and the prompt regression tests
   (deterministic hashes, no-GPS-in-base, species contract) are the backstops.
7. Bench with real images before trusting it: the failure mode that motivated
   v1.5.0 only showed up in `benchmarks/` runs, never in unit tests.
