# Commenting Guide - CameraVision

This guide is prescriptive for new and modified code in this repository.
Comments should make the code easier to maintain without turning files into
narrated transcripts of obvious operations.

## Philosophy

Comment the why, constraints, and domain meaning. Do not comment the plain
mechanics that the Swift code already states.

Good comments answer questions such as:

- Why does this branch exist?
- Which requirement or phase boundary does this protect?
- What filesystem, Apple framework, model-runtime, or schema constraint is easy
  to miss?
- What unit, identity policy, provenance rule, or failure contract is being
  preserved?

Bad comments restate code:

```swift
// Set recursive to true.
let recursive = true
```

## Swift Comment Forms

Use `///` for public API documentation and `//` for short implementation notes.
Use `/* ... */` only when a multi-line explanation is materially clearer than
several line comments, such as a state transition table or a formula.

Do not add decorative section dividers. Prefer small types and well-named helper
functions over visual separators. If a file becomes hard to scan, first consider
splitting it along existing module boundaries.

## Public API Documentation

Add `///` documentation to public types, public enums, public protocols, and
public functions that are meant to be reused across modules or phases.

Document semantics rather than repeating the signature:

```swift
/// Stable source-file identity used by later phases to detect changed images.
///
/// The `sha256` value is interpreted according to `policy`; callers must record
/// both fields anywhere the identity is persisted.
public struct SourceIdentity: Codable, Sendable, Equatable {
    public var policy: SourceIdentityPolicy
    public var sha256: String
}
```

Include units, accepted ranges, persistence guarantees, and requirement IDs when
they prevent misinterpretation:

```swift
/// Scans a file or folder according to FR1-001 through FR1-006b.
///
/// Unsupported visible files are returned as recoverable scan errors so a batch
/// can continue. Missing input roots fail the command because there is no batch
/// to continue.
public func scan(...) throws -> ScanResult
```

Avoid low-value documentation on trivial cases:

```swift
/// Log level.
public var logLevel: LogLevel
```

The type name already says that.

## Inline Comments

Use inline comments sparingly for non-obvious implementation logic.

Good targets for inline comments:

- Requirement-preserving behavior, especially Phase 1 boundaries such as "no
  XMP writes".
- Filesystem edge cases: hidden files, resource forks, sidecar exclusion,
  case-insensitive collision handling, atomic rename behavior.
- Source identity and hashing policy details.
- Apple framework constraints: Image I/O orientation, Core Image color spaces,
  Vision mask coordinate mapping.
- Model/runtime contracts: Ollama endpoint choices, retry boundaries, schema
  validation, raw response preservation.
- Concurrency choices: why a stage is bounded, serialized, or isolated.
- Magic numbers: chunk sizes, cache caps, timeout defaults, crop margins.

Example:

```swift
// Hidden path components are ignored, not reported, because photo folders often
// contain macOS metadata files that should not appear as batch failures.
if components.contains(where: { $0.hasPrefix(".") }) {
    return true
}
```

Do not write comments for straightforward control flow:

```swift
// Return true if this is a directory.
return isDirectory
```

## Requirement References

Use requirement IDs when they anchor behavior that may otherwise look arbitrary.
Keep the comment short and local to the relevant decision.

```swift
// FR1-005: existing Phase 1 sidecars are scan inputs to ignore, not images.
if lowercasedName.hasSuffix(".ai.json") {
    return true
}
```

Do not paste long requirement text into source files. The full source of truth is
`agent_docs/01-cli-raw-json-sidecar-requirements.md`.

## Errors and User-Facing Behavior

Comments are useful where error classification affects batch behavior:

- Why an error is recoverable or fatal.
- Why an unsupported file is recorded rather than thrown.
- Why raw model output is preserved even when parsing fails.
- Why a write path must be atomic.

Prefer comments near the classification point, not at distant call sites.

## Tests

Test comments should explain the scenario or regression, not each assertion.
Use comments only when fixture construction is non-obvious.

Good:

```swift
// This byte sits outside the first and last 4 MiB windows, so the fast identity
// must remain stable when only this middle gap changes.
data[(4 * 1024 * 1024) + 10] ^= 0xff
```

Avoid:

```swift
// Assert there is one image.
XCTAssertEqual(result.images.count, 1)
```

## TODO and FIXME

Use `TODO:` and `FIXME:` sparingly. Every entry must include the missing behavior
and the reason it is deferred.

```swift
// TODO: add multi-subject output once Phase 1 records per-instance provenance.
```

Do not add open-ended notes such as:

```swift
// TODO: clean this up
```

## Checklist

Before finishing a change:

1. Add `///` comments only for reusable public API whose semantics are not
   obvious from the name and type.
2. Add inline comments only for non-obvious constraints, requirement-driven
   behavior, domain rules, formulas, or failure policy.
3. Remove stale comments and comments that restate the next line of code.
4. Keep comments close to the behavior they explain.
5. Run the relevant SwiftPM checks, normally `swift test`.
