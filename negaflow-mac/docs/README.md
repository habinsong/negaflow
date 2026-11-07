<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, built natively for macOS.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="version 1.2.6"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README.md">Shared documentation</a> ·
  <a href="../../negaflow-windows/docs/README.md">Windows</a>
</p>

---

## What you need

To run it:

- macOS 14.0 or later (macOS 14, 26 and 27 are supported)
- Apple Silicon or Intel
- 8 GB of memory, 16 GB recommended for medium format

To build it:

- Xcode 26 or later for the app
- Swift 5.9 or later for the engine and CLI

## Installing

Download from [Releases](https://github.com/habinsong/negaflow/releases).

| File | Supported Macs |
|---|---|
| `negaflow-1.2.6-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.2.6-mac-arm64.pkg` | Apple Silicon only |

The Universal PKG fits most Macs and installs into `/Applications`. The same page has a DMG and a ZIP if you want to place the app yourself.

The app is signed ad hoc and not notarized, so macOS blocks the first launch. Allow it in System Settings under Privacy & Security with Open Anyway.

The library and settings are in `~/Library/Application Support/negaflow`.

At launch the app asks GitHub once for the latest release. If a newer version is out, the bottom of the ⋯ menu at the top right reads "Update to Version X.Y.Z". Choosing it opens the release page and saves the PKG for this Mac to Downloads, checked against the release's `SHA256SUMS.txt`. You install it yourself. When the app is current the item reads "You're on the latest version." and opens the project page. If the check fails, for example offline, the item does not appear.

## Building

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Build a Release app and launch it
bash scripts/run-app.sh

# Build without launching
bash scripts/run-app.sh build
```

`run-app.sh` calls `xcodebuild`, assembles the app bundle and signs it locally. For the engine or the CLI alone, `swift build` is enough.

Release artifacts:

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## Checks

```bash
# Swift tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Release build of the app
bash scripts/run-app.sh build

# Everything the repository checks
bash scripts/ci-gate.sh
```

## Custom color targets

CS follows MAIN, HS, SP, F135 and HR in the target capsules. Selecting it opens a two-column list of 18 Custom targets in the lower-left selector; the Look selector stays on the right. Entering CS selects Emulsion, and an image that already uses a Custom target keeps it.

The list has three groups: Emulsion to Dichroic (11), Wetzlar to Rochester (4), Slide Show to Point & Shoot (3). Custom targets apply the custom-3 tone, density and chroma response. Saving, previews, thumbnails and export use the selected target ID. Other targets are unchanged.

The CLI takes the same IDs: `--target classic`, `--target dye-transfer`, `--target point-and-shoot`.

## Command line

The macOS build ships a CLI.

```bash
swift build

# Find scanners
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# Develop
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# Profiles and engine self-check
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

Run `negaflow` with no arguments for the full option list.

## Scanners

Scanner controls stay hidden until a plugin is installed. SANE devices use [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), installed separately.

## Modules

| Module | Role |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, profiles, export |
| `ScannerKit` | Scanner capability checks and plugin connection |
| `negaflowApp` | Library, develop, scan and export screens |
| `negaflowCLI` | Develop, scan, benchmark and self-check commands |

## Reference images

`docs/verification/macos-golden` holds images rendered by this build. Git ignores that folder, so it exists only on the machine that rendered them. The Windows engine tests compare against copies pixel for pixel. Regenerate the images only when the macOS output is meant to change.

## Related documents

- [How the two differ](../../docs/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/product/GRAINMEND.md)
- [Product architecture](../../docs/architecture/PRODUCT_ARCHITECTURE.md)
