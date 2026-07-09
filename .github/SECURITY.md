# Security Policy

## Supported versions

CameraVision is pre-1.0 and under active development. Security fixes are applied
to the latest `main` and to the most recent tagged release only.

| Version            | Supported |
| ------------------ | --------- |
| `main` (latest)    | ✅        |
| Latest tagged beta | ✅        |
| Older tags         | ❌        |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for a
suspected vulnerability.

- Preferred: use GitHub's **Report a vulnerability** button under the
  repository's **Security** tab (Private vulnerability reporting).
- Alternatively, email the maintainer at **inquiries@ronbuening.com**.

Please include enough detail to reproduce: affected command or code path,
inputs, and the observed vs. expected behavior. You can expect an initial
acknowledgement within a few days.

## Scope notes

CameraVision is a local-first tool. It runs image analysis against a **local**
Ollama endpoint and does not upload source images or derivatives. Areas most
relevant to security reports:

- File-system writes (raw `.ai.json` sidecars, XMP sidecars, backups, caches)
  landing outside their intended target directories.
- XMP parser/writer handling of untrusted sidecar input.
- Handling of the local model endpoint URL and any configured credentials.
- Release-artifact integrity (signing / notarization of `CupricAspect.app`).

Please do not include real credentials or Developer ID signing material in a
report.
