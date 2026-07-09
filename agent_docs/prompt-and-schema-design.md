# Prompt and Response-Schema Design (v1.5.0)

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

## The constraint that shapes everything: Ollama's grammar

Every model call sends the response schema through Ollama's `format` field,
which compiles it to a token-level grammar (llama.cpp GBNF). The grammar can
force structure the model physically cannot violate — but only for a subset of
JSON Schema:

**Enforced at generation time:** `type`, `properties`, `required`,
`additionalProperties: false`, `enum`, `items`, and (approximately) string
`pattern`/length and array `minItems`/`maxItems`.

**Silently ignored:** `allOf`, `if`/`then`/`else`, `not`, `contains` — any
conditional or combinator logic.

Consequences, learned the hard way in the milestone-9a benchmarks:

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
  easily 1–2k tokens.
- The **repair prompt is the biggest single consumer**: it embeds the full
  schema JSON *and* the invalid response *and* instructions.

`model_context_window` (config key, `AISIDECAR_MODEL_CONTEXT_WINDOW`, GUI
controls in Settings and Step 3) is sent as Ollama `num_ctx` on every call,
default 8192. Before that key existed, no `num_ctx` was sent and Ollama's
runtime default could silently truncate the prompt or response.

Prompt-writing rules that follow from the budget:

- Sectioned, deduplicated, positive phrasing. One statement of each rule, in
  the section where the model needs it.
- No rule that exists only "when X is configured" — conditional content is
  *injected* (see GPS below), never carried as dead weight.
- Concrete one-line examples beat paragraphs ("Good evidence: … Bad
  evidence: …").

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
   `allOf`/`if`/`then`/`else`/`not`/`contains`. Conditional semantics go into
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
