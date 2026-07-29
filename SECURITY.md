# Security Policy

## Supported versions

Security fixes are prioritized for the latest published release and the current `main` branch.
Older releases may be asked to upgrade before a fix is provided.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub's
[private vulnerability reporting](https://github.com/habinsong/negaflow/security/advisories/new)
and include:

- The affected negaflow version or commit
- The macOS version and Mac architecture
- The impact and conditions required to reproduce the issue
- Minimal reproduction steps or a proof of concept
- Any suggested mitigation, if known

Do not attach private photographs, scanner output containing personal information, credentials,
signing material, or other secrets. Use synthetic or redacted samples whenever possible.

If private vulnerability reporting is unavailable, open a public issue containing no vulnerability
details and request a private contact channel from the maintainer.

The maintainer will acknowledge the report when it has been received, investigate the impact, and
coordinate a disclosure timeline when a fix is required. Please allow a reasonable period for a fix
before public disclosure.

## Scope

Security reports for negaflow may include source-file safety, catalog or sidecar integrity,
path handling, external scanner-plugin process boundaries, malformed image or plugin input, and
release artifact integrity.

SANE backend implementation and installer vulnerabilities belong to the separate
[`negaflow-scanner-sane` project](https://github.com/habinsong/negaflow-scanner-sane/security).
