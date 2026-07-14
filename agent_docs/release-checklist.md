# Release Checklist — Cutting a CupricAspect Release

Version: 0.1
Date: 2026-07-14
Mirrors: `.github/workflows/release.yml` (once landed — plan `agent_docs/11-release-channels-and-distribution-plan.md` W2)
Owns: roadmap `agent_docs/09-post-m11-feature-roadmap.md` F4-R4
Audience: the maintainer cutting a release. This is the human-readable mirror of the release workflow — follow it top to bottom.

> **Status (2026-07-14):** the workflow (W2) and script additions (W1) are **not yet landed**. Until they are, the "CI does this" steps are aspirational and a release is cut with a local `Scripts/build-release.sh --universal` build uploaded to a hand-created Release. Revise this file against the first real CI tag run (F4-R4 is "correct against reality," not "write in the abstract").

## Channels at a glance

A release is a **git tag** resolving to **one commit**. The tag name is the channel gate:

- **Beta:** `v0.1.0-beta.2`, `v0.1.0-beta.3`, … — any semver pre-release suffix (`-beta.N`, `-rc.N`). Published as a GitHub **prerelease**. Unsigned (ad-hoc), not notarized.
- **Stable:** `v1.0.0`, `v1.1.0`, … — no suffix. Published as a full release ("Latest"). Signed + notarized **only once Developer ID is adopted** (plan W5); until then a stable tag also ships unsigned.

The branch you tag from does not change the channel — the tag name does. (Branch model is a maintainer decision; see plan §4.)

## Before you tag

1. **Working tree is the commit you mean to ship.** `git status` clean; you are on the intended branch/commit.
2. **Tests green locally.** `swift test` — 0 failures. If XCTest is missing, prefix with `DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer` (same toolchain as CI).
3. **Bump the version — single source.** Edit `Sources/AISidecarCore/Support/AISidecarVersion.swift` so `current` equals the tag minus its leading `v` (tag `v0.1.0-beta.2` → `current = "0.1.0-beta.2"`). Nothing else carries a version number; the About card, `aisidecar --version`, and `CFBundleShortVersionString` all derive from this (packaging plan §6 / invariant 19). Commit this bump on its own.
4. **Changelog / release notes.** Note what changed since the last tag; this becomes the Release body.
5. **Local build sanity (optional but recommended).** `Scripts/build-release.sh --universal` and confirm `dist/` contains the DMG and `SHA256SUMS`, and that `shasum -a 256 -c dist/SHA256SUMS` passes from inside `dist/`.

## Cutting the tag

Use an **annotated** tag (carries a message, tagger, date — the release anchor):

```bash
git tag -a v0.1.0-beta.2 -m "CupricAspect 0.1.0-beta.2"
git push origin v0.1.0-beta.2
```

The push triggers `release.yml`, which:

- asserts the tag equals `v$AISidecarVersion.current` (mismatch fails the build — this is why step 3 above matters);
- builds a universal (arm64 + x86_64) `.app`, DMG, and `SHA256SUMS` via `Scripts/build-release.sh --universal`;
- emits a build-provenance attestation over the DMG;
- creates the GitHub Release, marking it **prerelease** iff the tag has a pre-release suffix, and attaches all three artifacts.

## After CI publishes — smoke test on a clean profile

Do this on a machine/user account that has never run the app (quarantine only applies to real downloads):

1. Download the DMG from the Releases page.
2. **Verify the checksum:** download `SHA256SUMS` next to it, then `shasum -a 256 -c SHA256SUMS`. Optionally `gh attestation verify CupricAspect-<v>.dmg --repo <owner>/CameraVision`.
3. Mount the DMG, drag `CupricAspect.app` to Applications.
4. **Expect the Gatekeeper prompt** (beta is not notarized). Clear it via **System Settings → Privacy & Security → "Open Anyway"**, or `xattr -dr com.apple.quarantine /Applications/CupricAspect.app`.
5. Launch. Confirm the About card shows the expected version.
6. Confirm the embedded CLI matches: the app bundles `aisidecar` at `Contents/Helpers/aisidecar` — `"/Applications/CupricAspect.app/Contents/Helpers/aisidecar" --version` prints the same version.
7. If anything is wrong, **do not re-tag** — see below.

## The re-tag prohibition

**Never force-move a tag that CI has already published.** The published `SHA256SUMS` and provenance attestation pin a specific artifact; moving the tag makes every downloader's verification fail and breaks the "one tag → one commit → one build" chain.

- Bad beta build? Fix the code, bump to `v0.1.0-beta.3`, tag that.
- Bad stable build? Same — `v1.0.1`.

A tag is cheap; trust is not.

## Addendum — notarized stable channel (only once Developer ID is adopted)

This section activates plan W5. Until Developer ID is adopted, skip it entirely.

- One-time: create a **Developer ID Application** certificate; export as p12; store CI secrets `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (app-specific password). Never commit any of these.
- With the certificate secret present, `release.yml` builds with `--sign "$IDENTITY"`; the script codesigns inside-out with hardened runtime, `xcrun notarytool submit --wait`, then `xcrun stapler staple` (DMG last — any file added after signing invalidates the seal).
- Stable smoke test replaces step 4 above: there should be **no** Gatekeeper prompt. Verify with `spctl --assess --type execute` on the app copied out of the mounted DMG and `xcrun stapler validate` on the DMG.

Full runbook: `agent_docs/06-packaging-single-app-plan.md` §4.
