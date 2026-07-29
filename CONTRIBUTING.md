# Contributing to negaflow

Thank you for helping improve negaflow. Small, focused changes with clear verification are the
easiest to review.

## Before opening an issue

- Search existing issues first.
- Use the bug report or feature request form and include only information needed to reproduce or
  evaluate the request.
- Do not disclose a security vulnerability in a public issue. Follow
  [the security policy](SECURITY.md).
- Report SANE backend, device discovery, and scanner-plugin packaging problems to
  [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane/issues).
  Issues in negaflow's plugin host, capability UI, or scan workflow belong here.

## Development setup

The project requires macOS 14 or later. The GUI build uses Xcode 26, and the engine and CLI require
Swift 5.9 or later.

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Engine and CLI
swift build

# XCTest with the full Xcode toolchain
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI Release build without launching
bash scripts/run-app.sh build
```

See [Product Architecture](docs/architecture/PRODUCT_ARCHITECTURE.md) before changing module
boundaries or persistent data.

## Making a change

1. Keep the change limited to one problem.
2. Match the existing Swift, SwiftUI, test, and documentation conventions.
3. Add behavior-focused tests for new behavior and bug fixes.
4. Update durable documentation and every supported localization affected by visible product copy.
5. Run the smallest relevant check first, then the broader checks appropriate to the change.

The following project rules are especially important:

- Imported and scanned source files are immutable. Keep edits, sidecars, thumbnails, and caches
  separate from the source.
- Never silently fall back to the original when a required non-destructive result cannot be rebuilt.
- Scanner controls and requests must use only capabilities reported by the installed plugin.
- Do not add SANE implementation code or a second app-to-plugin communication path to this
  repository.
- Automated checks do not replace real-scanner, final-image, signing, or notarization verification.

## Verification

```bash
# Fast static and repository-contract checks
bash scripts/ci/verify-static.sh

# Full Swift test suite
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI Release build
bash scripts/run-app.sh build

# Local CI gate
bash scripts/ci-gate.sh
```

Document any check that was not run and why. UI, image-quality, performance, scanner, and release
changes should include the relevant screenshots, measurements, hardware details, or artifact
evidence.

## Pull requests

- Explain the problem and the chosen solution.
- Link the issue when one exists.
- Keep unrelated cleanup and formatting out of the pull request.
- Describe the commands and manual scenarios used for verification.
- Call out data migration, source-file safety, plugin-contract, localization, performance, or release
  impact.
- Do not include build products, credentials, private scans, proprietary datasets, or third-party
  material without clear redistribution rights.

By submitting a contribution, you confirm that you have the right to provide it under this
repository's [Apache License 2.0](LICENSE).

All contributors must follow the [Code of Conduct](CODE_OF_CONDUCT.md).
