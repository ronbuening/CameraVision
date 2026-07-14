# Release Channels and Distribution Plan — Unsigned Beta Now, Signed Later

Version: 0.1
Date: 2026-07-14
Implements: `agent_docs/09-post-m11-feature-roadmap.md` F4-R3 (GitHub Actions release workflow) and F4-R4 (release checklist)
Depends on: `agent_docs/06-packaging-single-app-plan.md` (bundle layout, `Scripts/build-release.sh`, §4 signing runbook), `agent_docs/invariants.md` (all rules apply; §6 version single-sourcing is load-bearing here)
Companion: `agent_docs/release-checklist.md` (the human runbook this plan produces; written alongside this doc)
Audience: junior engineer or Sonnet-level coding agent. Each work item is self-contained: goal, exact location, change, and acceptance criteria.

## 0. Where this plan comes from

Goal shift (2026-07-14): stop distributing the beta as source-only and start shipping **downloadable, unsigned builds from GitHub Releases**, while laying the track for a second **signed/notarized stable channel** later — both visible on the same Releases page. This realizes the distribution work the packaging plan handed to roadmap F4 (`06-packaging-single-app-plan.md` status ledger: "CLI install action, CI, Sparkle auto-update — owned by roadmap F4").

The build side already exists: `Scripts/build-release.sh` assembles `dist/CupricAspect.app` + a DMG, single-sources the version from `AISidecarVersion.swift`, and ad-hoc signs by default with a `--sign "Developer ID…"` path stubbed in. What is missing is (a) a tag-triggered CI workflow that publishes a GitHub Release, (b) a small script addition (checksums), and (c) user-facing download/Gatekeeper docs. This plan covers exactly that.

**Not in scope:** Sparkle auto-update (roadmap F4-R2), the "Install Command Line Tool" GUI action (F4-R1). The tag scheme here is deliberately Sparkle-compatible so F4-R2 slots in later without rework.

## 1. Decisions (with rationale)

**D1 — A channel is a *tag shape*, not a branch.**
A GitHub Release binds to a **git tag**, which resolves to exactly one commit. The branch a tag is cut from only decides *which commit*; it is not what GitHub keys on. So the beta-vs-stable distinction rides on the **tag name** and the Release **prerelease flag**, not on a branch:

| Channel | Tag example | Signing | GitHub Release |
|---|---|---|---|
| Beta | `v0.1.0-beta.2` | ad-hoc (unsigned) | marked **prerelease** |
| Stable | `v1.0.0` | Developer ID + notarized + stapled *(later)* | full release, "Latest" |

Rationale: making the tag the source of truth means a commit tagged on the wrong branch cannot silently publish a "stable" build — the presence of a semver pre-release suffix (`-beta`, `-rc`) is the gate. It also survives a future decision to collapse to a single branch. See D8 for the branch-model question, which is now independent of the channel mechanism.

**D2 — One workflow, one build, secret-gated signing.**
`release.yml` runs the *same* `build-release.sh` for both channels. Signing is chosen by **whether Developer ID secrets exist** in the repo, not by a separate pipeline. No secrets → ad-hoc build ships as-is (today). Add secrets later → the identical tag flow starts signing and notarizing, with no workflow rewrite. This is the "keep the door open, costs nothing" posture chosen 2026-07-14.

**D3 — "Unsigned" means ad-hoc signed, not notarized.**
On Apple Silicon a binary must carry at least an ad-hoc signature to execute at all; `build-release.sh` already ad-hoc signs. So the honest user-facing phrasing is *"not notarized by Apple,"* never "unsigned binary." The cost of skipping notarization is a Gatekeeper prompt on first launch (see §2), not an unrunnable app.

**D4 — Build in CI on tag push, not locally.**
`on: push: tags: ['v*']` fires regardless of branch. CI produces a reproducible universal (arm64 + x86_64) build from a clean checkout, so Intel Macs are covered and no build-machine state leaks into the artifact. Local `build-release.sh` remains the dev/debug path; it is not the publish path.

**D5 — Artifacts: DMG + `SHA256SUMS`, nothing else.**
The DMG is the drag-to-Applications installer; `SHA256SUMS` verifies it. No zipped `.app` — that was an earlier over-reach justified by "Sparkle needs a zip," which is false: Sparkle 2 delivers updates from a `.dmg` directly. Adding a zip later, if a concrete need appears (e.g. a scripted-install path), is a few lines in `build-release.sh`, the workflow's attestation `subject-path`, and the `gh release create` asset list — cheap and reversible. So the beta ships one artifact plus its checksum; keep the Releases page uncluttered until a second format earns its place.

**D6 — Trust substitutes while unsigned: checksums + build provenance.**
Every Release carries `SHA256SUMS`, and CI emits a **GitHub build attestation** (SLSA provenance) via `actions/attest-build-provenance`. A downloader can run `gh attestation verify` to confirm the artifact was produced by this repo's CI from a specific commit — a partial, verifiable trust signal that stands in for Apple notarization during the beta. This is defense-in-depth, not a Gatekeeper bypass (it does not remove the quarantine prompt).

**D7 — First-party tooling only in the workflow.**
Use the preinstalled `gh` CLI (`gh release create`) to cut the Release rather than a third-party marketplace action, matching the repo's existing supply-chain posture (`ci.yml` pins `actions/checkout` to a commit SHA; least-privilege `permissions`). The one third-party action introduced — `actions/attest-build-provenance` — is first-party GitHub and must be SHA-pinned like `checkout` is.

**D8 — Branch model is an open maintainer decision, and now decoupled from channels.**
Because D1 makes the tag the channel gate, you can either (a) keep a long-lived `beta` branch you promote to `main`, or (b) tag both betas and stables off `main`. The workflow is identical either way. Recommendation: **(b) tag off `main`** unless you have a concrete need to stabilize beta commits separately — a long-lived branch adds ongoing merge/promotion overhead for no benefit the tag scheme doesn't already provide. Left as STOP: maintainer decision (§4).

## 2. The user download experience (the Gatekeeper reality)

This is the whole cost of the unsigned beta, and it is documented, not coded around. When a user downloads the DMG, macOS attaches a `com.apple.quarantine` attribute. Because the app is ad-hoc signed and **not notarized**, Gatekeeper blocks the first launch with a message like *"Apple could not verify … is free of malware."* On macOS Sequoia (15) the old right-click → Open shortcut is gone. The two supported paths, both of which go in the README (W3):

1. **GUI path** — try to open the app once, then **System Settings → Privacy & Security → scroll to the blocked-app notice → "Open Anyway."** Subsequent launches are unobstructed.
2. **Terminal path** — `xattr -dr com.apple.quarantine /Applications/CupricAspect.app` removes the flag directly.

Users who want assurance first verify the download against the published `SHA256SUMS` (and optionally `gh attestation verify`). Once the stable channel is notarized (§ later), neither path is needed for that channel — the prompt simply does not appear.

## 3. Work items

Order: **W1 → W2 → W3 → W4**. W5 is deferred (secret-gated, executed when/if Developer ID is adopted). Each item is independently committable with `swift test` green; docs and code commit separately (invariant 17, and repo memory "commit at breakpoints").

### W1 — Extend `build-release.sh`: checksums, CI-universal default

**Goal.** Make the script emit everything a Release needs, so `release.yml` is a thin caller.

**Location.** `Scripts/build-release.sh`.

**Change.**
- Inside the DMG step, emit a `SHA256SUMS` in `dist/` covering the DMG: `shasum -a 256` over the artifact basename, written with the path relative to `dist/` so the file verifies from inside the download folder. Gated on the DMG existing (`--no-dmg` produces no distributable, so no checksum file).
- Add a `--for-release` convenience flag (or have `release.yml` pass the existing flags) that implies `--universal`. Keep local default as-is (host arch, fast) so dev builds stay quick. Do **not** change the default of a bare `Scripts/build-release.sh` invocation.
- Leave the ad-hoc-vs-`--sign` logic untouched; W5 extends it.

**Acceptance.**
- `Scripts/build-release.sh --universal` yields `dist/CupricAspect-<v>.dmg` and `dist/SHA256SUMS`.
- `shasum -a 256 -c dist/SHA256SUMS` passes when run with `dist/` as the working directory.
- `lipo -archs dist/CupricAspect.app/Contents/MacOS/CupricAspect` lists both `arm64` and `x86_64`.
- The embedded-CLI version cross-check and plist-version check (existing lines 78–84) still pass.

### W2 — Add `.github/workflows/release.yml`

**Goal.** Tag push → universal build → GitHub Release with assets, checksums, and provenance; prerelease flag derived from the tag.

**Location.** `.github/workflows/release.yml` (new).

**Change (shape, not final source).**
- Trigger: `on: push: tags: ['v*']`.
- `permissions:` least-privilege but with what publishing needs: `contents: write` (create the Release), `id-token: write` + `attestations: write` (provenance). Nothing else.
- Pin `DEVELOPER_DIR` to the same Xcode as `ci.yml` (single source of truth for the toolchain — if `ci.yml` moves, this moves with it).
- Runs on `macos-15`, checks out at SHA-pinned `actions/checkout` (same pin as `ci.yml`).
- **Version/tag guard:** read `AISidecarVersion.current`; assert the pushed tag equals `v$VERSION`. Mismatch → fail the job. This makes the tag and the single-sourced version physically incapable of disagreeing (invariant 19 extended to the tag).
- Build: `Scripts/build-release.sh --universal` (signing auto-selected — see W5; absent secrets → ad-hoc).
- Attest: `actions/attest-build-provenance` (SHA-pinned) over the DMG.
- Publish with `gh release create "$TAG" dist/CupricAspect-*.dmg dist/SHA256SUMS --title … --generate-notes --prerelease` where `--prerelease` is passed iff the tag contains a `-` (semver pre-release suffix). Bare `vX.Y.Z` publishes as a full release; `gh` marks it Latest by default.
- Release notes: point `--notes-file` at a generated file or `--generate-notes` for the auto changelog; refine later.

**Acceptance.**
- Pushing `v0.1.0-beta.2` (after the source version is bumped to match) produces a **prerelease** GitHub Release carrying the DMG and `SHA256SUMS`, with a verifiable provenance attestation.
- Pushing a tag whose version does not match `AISidecarVersion.current` fails the job before publishing.
- The job requests no permission beyond the four listed.
- Re-running does not silently move a tag (see checklist: bump, never re-tag).

### W3 — README "Download" section

**Goal.** Replace the source-only distribution note with a real download path plus the Gatekeeper and checksum instructions from §2.

**Location.** `README.md`, the block currently at lines ~96–113 ("During the beta, CameraVision is distributed as source…").

**Change.**
- Lead with a link to the Releases page and which asset to grab (the DMG).
- Include both Gatekeeper paths verbatim from §2 (Privacy & Security "Open Anyway"; `xattr -dr com.apple.quarantine`).
- Include the checksum verification one-liner (`shasum -a 256 -c SHA256SUMS`) and a note on `gh attestation verify` for the security-minded.
- Keep the "build from source" path as a secondary option, not the headline.
- State plainly that the beta is **not notarized** and what that means (the prompt), so the experience is expected, not alarming.

**Acceptance.** A reader who has never seen the repo can download, verify, bypass Gatekeeper, and launch using only the README. No mention of a Developer ID requirement for the beta.

### W4 — `agent_docs/release-checklist.md`

**Goal.** The human runbook that mirrors `release.yml` — this is roadmap F4-R4. Written as the companion to this plan.

**Location.** `agent_docs/release-checklist.md` (new; drafted alongside this doc).

**Content.** Pre-tag checks (tests green, version bump in `AISidecarVersion.swift`, changelog), the tag command (annotated tag, `v$VERSION`), what CI does, post-publish smoke test (download on a clean profile, verify checksum, Gatekeeper bypass, launch, `aisidecar --version`), and the **re-tag prohibition** (mistake → bump to next `-beta.N`, never force-move a published tag — checksums would no longer match). Includes the secret-gated notarization addendum (W5) marked "when Developer ID is adopted."

**Acceptance.** Following the checklist top to bottom cuts a beta release with no reference to this plan or tribal knowledge.

### W5 — Notarization wiring *(DEFERRED — secret-gated; execute only if Developer ID is adopted)*

**Goal.** Turn on the stable channel's signing without touching W1–W4.

**Location.** `Scripts/build-release.sh` (activate the notarize+staple step that is currently a NOTE at lines 92–93) and `release.yml` (import cert, pass identity).

**Change (recorded now for completeness).**
- Secrets: `MACOS_CERTIFICATE` (base64 p12), `MACOS_CERTIFICATE_PWD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (app-specific password). Never in the repo.
- Workflow imports the p12 into a throwaway keychain, then calls `build-release.sh --universal --sign "$IDENTITY"`.
- Script, when `--sign` is present: after codesign, `xcrun notarytool submit "$DMG" --apple-id … --team-id … --password … --wait`, then `xcrun stapler staple "$DMG"`. The DMG step must remain last (any file added after signing invalidates the seal — packaging plan §4).
- `release.yml` selects `--sign` iff the certificate secret is present, so the same tag flow degrades gracefully to ad-hoc when it is not.

**Acceptance (when adopted).** `spctl --assess --type execute` passes on the app copied out of the mounted DMG; `xcrun stapler validate` passes on the DMG; a stable `vX.Y.Z` tag publishes a notarized artifact that launches on a clean machine with **no** Gatekeeper prompt.

## 4. Open maintainer decisions (STOP items)

1. **Branch model (D8).** Tag betas + stables off `main` (recommended), or maintain a long-lived `beta` branch promoted to `main`? Decision changes only the checklist's "where to tag" line, not the workflow.
2. **Developer ID / notarization (W5).** Adopt the $99/yr Apple Developer Program for the stable channel, or keep all channels unsigned and lean on checksums + provenance? Currently **undecided (2026-07-14)** — plan is built so this stays a drop-in, not a rewrite.

## 5. Exit gate for this plan

- W1–W4 landed; `swift test` green throughout.
- A real `v0.1.0-beta.2` prerelease published by CI, downloadable, checksum-verifiable, and launchable on a clean macOS profile following only the README.
- Release checklist exercised end-to-end during that tag run and corrected against reality (F4-R4 is "revise against the first real run," not "write in the abstract").
- Roadmap F4-R3/R4 status updated to reflect the shipped workflow and checklist.
