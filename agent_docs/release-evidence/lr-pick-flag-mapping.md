# Lightroom Classic Pick-Flag XMP Mapping

Lightroom Classic version: 15.4.1 (Macintosh), from `stEvt:softwareAgent` in the samples.
Samples: `agent_docs/XMP_Samples/Lightroom_Flags/` (Nikon Z 8 NEF sidecars), captured 2026-07-17.

## Observed serialization

Lightroom stores the pick flag as a coupled pair of `xmpDM` properties
(namespace `http://ns.adobe.com/xmp/1.0/DynamicMedia/`), both in **attribute
form** on the main `rdf:Description`:

| Sample | Flag state | `xmpDM:pick` | `xmpDM:good` |
|---|---|---|---|
| RZ8_3573.xmp | Unflagged | `0` | absent |
| RZ8_3574.xmp | Rejected | `-1` | `false` |
| RZ8_3575.xmp | Picked | `1` | `true` |

exiftool's XMP xmpDM table documents `good` as the Boolean "Good" tag
(<https://exiftool.sourceforge.net/TagNames/XMP.html#xmpDM>); `pick` is the
ternary Lightroom writes alongside it.

## What the engine does with this

- `xmpDM:pick` and `xmpDM:good` are managed scalars written only as the
  consistent pairs `1`/`true` (picked) and `-1`/`false` (rejected); the engine
  refuses to write a split pair.
- Unflagged (`pick="0"`, no `good`) is never written: grading has no
  "clear the flag" channel, and under the `preserve` conflict policy an
  existing `pick="0"` counts as a user decision and is skipped.
- The grading flag channel (`xmp_quality_write_flag` / `xmp_quality_flag_map`)
  defaults to on with reject→rejected and excellent→picked, mirroring the
  Red/Green label defaults.

## Boundary

This records what Lightroom Classic 15.4.1 *writes*. Whether Lightroom reads
the pair back from externally written sidecars (import/read-metadata behavior)
remains gated on the IQ-M5 live verification (S5.2), like the other managed
scalars.
