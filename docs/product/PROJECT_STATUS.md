# Project status

[Docs home](../README.md)

This is the reference for what is built and what has been checked.
The README explains the product and how to use it; the documents under docs hold the detailed specs
and decisions.

## Basics

| Item | Current value |
|---|---|
| Version | `1.0.7` |
| Build | `1` |
| OS | macOS 14 or later |
| Workflow | import or scan → develop → export |
| Default develop | `main`, manual correction |
| Originals | Original files and third-party sidecars are not modified |

> [!WARNING]
> The `1.0.7` label and a successful build do not mean real scanner compatibility, final image
> quality, external signing, or notarization have been confirmed. Real hardware and release
> approval are recorded separately in the checklist below.

## Built, and checked automatically

- Non-destructive catalog, sidecars, virtual copies, collections, rolls, ratings, pick and reject
- Duplicate import, relinking originals, removing from the library, moving originals to Trash
- Catalog health check, process lock, recovery block, backup generations, restore rehearsal, redeveloping selected frames
- Shared develop and export path, metadata, processing history, edit history, multi-file output
- JPEG encoded without chroma subsampling at 95% quality and above, selectable 8 or 16-bit PNG, and a Quick Export that carries its own encoding settings
- Recorded camera, lens, film and exposure written to the exported file, with the shooting camera taking precedence over the scanner in EXIF
- Roll notes filling only the empty fields of a frame, with roll code, film and camera as file-name tokens
- Evicted iCloud originals materialized before an export, and standard or strict export verification
- Frame selection on a flatbed preview locked to the aspect of the selected film format
- Automatic flatbed frame detection that finds film by grain and picture rather than brightness, refuses empty windows and half-cut slots, and measures the spacing between cuts instead of guessing it
- Infrared cleaning offered for every dye-image film, colour negative and colour slide alike, and withheld from silver-image black and white
- A low-frequency observation boundary that refreshes the export button as develop and reprocess state changes
- Scanner plugin discovery and approval, capability checks, protocol v1/v2, cancellation, time limits, output caps
- Plugin owner and permission checks, and validation of temporary output
- Consistency check between the CLI scanner JSON and the capabilities shown in the app
- Accessibility, selection state, text size, window resizing, screen state restore
- Compare and survey views, photo stacks, duplicate candidate review
- BagIt preservation archive holding originals, IR, GrainMend records, and virtual copy links
- Render manifest v3 linking source and output by SHA-256
- IR alignment diagnostics and film compatibility limits
- Repeat measurement for scanner noise and the separate validation spec
- Frame cache cleanup under memory pressure
- Strict Swift concurrency diagnostics in CI
- Import progress, automatic development off by default, and persistence of that setting
- Persistent folder expansion, an internally scrolling Develop file list, and the same remove-from-library action on every folder
- Photo moves across imported, app-created, and scanner folders, with numbered names on collision
- Finder file and folder move/rename events, bookmark relinking, and changed-folder-only rescans
- Per-folder process and target application, including previously developed photos, with batch progress
- Presets and multi-selection copy/paste including process, target, adjustments, crop, and orientation
- Developed scanner thumbnails in Develop and Print for every supported film type
- The shared scanner sidebar stays hidden when no plug-in is installed, while rescan and simulator entry points remain available
- Large-catalog filmstrips avoid long automatic jumps, build rows lazily, and have an opt-in 2,000-frame actual-pixel stress check
- Profile preview on every print-package item and printer ICC conversion of the complete composed page
- A workspace boundary that keeps the C-print proof profile out of Develop and delivery files
- Seven Print layouts: single image, contact sheet, picture package, custom package, cyanotype, glass plate, and gelatin silver
- A vertical page stack for multi-selection individual layouts, with historical styles rendered identically by Export and Quick Export
- Finished-page output counts: 39-photo 6 × 7 contact sheet as one page, four-up picture package as 10 pages, default custom package as one page, or 39 individual files
- Print preview reuse, source preparation limited to two to four items, a connected Core Image page graph, and a 512 MiB per-page source-raster budget
- A localized About window with the bold Niépce bicentennial message between the product name and version

## Catalog

The main store is `library.sqlite`.
An existing `library.json` is opened read-only, checked for health, backed up, and moved into a
temporary SQLite.
It becomes the main store only when the contents of both catalogs and SQLite integrity agree.

When resuming interrupted work, mismatched evidence fails closed.
JSON stays as the portable backup and archive exchange format, but two main stores are never used at
once.

The details are in [catalog storage](../architecture/CATALOG_STORAGE.md).

## Scanners

This repository holds a device-independent external process host and the JSON spec.
The SANE implementation, its dependencies, configuration, and distribution files are not here.
That code lives in the separate GPL project
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

The app shows only what the installed plugin reported.
It does not guess capabilities from a model name.
Unless you pick the demo, no fake scanner stands in.

Detailed specs:

- [Scanner plugin architecture](../architecture/SCANNER_PLUGINS.md)
- [Scanner CLI JSON](../reference/CLI_JSON.md)
- [Flatbed frame detection](../reference/FRAME_DETECTION.md)

## Build and release

<details>
<summary>Local checks and release commands</summary>

Local checks:

```bash
bash scripts/ci-gate.sh
bash scripts/run-app.sh build
bash scripts/run-gui-e2e.sh  # needs macOS Automation Mode
```

Building the release files:

```bash
bash scripts/build-release.sh
```

</details>

`scripts/run-app.sh build` only assembles the app. It does not launch the app or a UI-test runner;
GUI automation starts only through the separate `scripts/run-gui-e2e.sh` command.

On July 31, 2026, the current worktree passed a strict Swift concurrency build, 1,800 parallel
tests, and 9 timing-sensitive serial tests. `scripts/run-app.sh build` also produced a fresh arm64
Release app, and the executable and dSYM UUIDs matched. This does not replace GUI use, real-scanner,
Developer ID, or notarization checks.

One run of `build-release.sh` builds the Apple Silicon (`arm64`) and Universal (`arm64`, `x86_64`)
apps and writes ZIP, PKG, DMG, dSYM, and the SHA-256 list.
Locally it uses an ad-hoc signature.
A real release needs both a Developer ID Application and a Developer ID Installer signature.

The manual `Distribution` workflow uses the protected Developer ID and the App Store Connect API
key.
It sends the app archive, DMG, and PKG to Apple, staples the notarization ticket, then checks the
checksums and Gatekeeper again.
Without a real workflow run and Apple's response, no claim is made about external signing or
notarization.

## Performance measurements

Performance checks cover the catalog, library search, high-resolution adjustment, GrainMend region
work, and a real pixel roll.

Recent Release measurements on one Mac:

| Operation | Result |
|---|---:|
| 50,000-frame JSON read p95 | about 7.4 s |
| 50,000-frame SQLite read p95 | about 7.4 s |
| 50,000-frame SQLite commit p95 | about 3.7 s |
| SQLite commit with no changes p95 | about 3.9 s |
| 50,000-frame filter and name sort | about 158 ms |
| Quick preview for 48 frames | about 10.6 s, max RSS about 504 MiB |
| Develop 48 frames | about 20.9 s, max RSS about 1,012 MiB |

On July 31, 2026, the opt-in `PrintExportPerformanceTests` used 39 separate 4,000 × 3,000 TIFF
sources and 300 DPI JPEG output on this Mac:

| Print output | Export | Quick Export |
|---|---:|---:|
| 6 × 7 contact sheet, 39 photos → 1 file | 1.177 s | — |
| Single image, 39 photos → 39 files | — | 5.234 s |
| Cyanotype, 39 photos → 39 files | 5.467 s | 5.659 s |
| Glass plate, 39 photos → 39 files | 5.960 s | 6.278 s |
| Gelatin silver, 39 photos → 39 files | 6.732 s | 6.697 s |

These do not guarantee performance on another Mac. New measurements come from this command.

```bash
bash scripts/run-performance-suite.sh
```

The macOS 26 arm64 limits in `Config/performance-budget-v1.json` are wide caps for catching large
regressions.
Passing them does not mean every delay feels good in use.

## GrainMend measurements

The FILM-R v2 material is pinned by DOI, 44 pairs, 437,570,872 bytes, and Figshare MD5 information.

The automatic path for the release runs at sensitivity 0.7 with an over-detection safety line.
Here it is against the previous regression baseline of 3.0.

| Metric | Previous baseline 3.0 | Safe auto 0.7 |
|---|---:|---:|
| Weighted worsened pixels | 0.792% | 0.017% |
| Weighted changed pixels | 0.794% | 0.043% |
| Mean PSNR change | -1.688 dB | +0.466 dB |
| Worst PSNR change | -18.952 dB | -1.338 dB |
| Improved / worsened / same images | 11 / 33 / 0 | 34 / 6 / 4 |

Besides the observed regression check, absolute floors are enforced: mean and median PSNR at 0 dB or
better, at most 10 worsened images, and a worst case of -1.5 dB or better.
The automatic safety line stopped repair on 3 images, and in that case the app points to Guided.

FILM-R validates the GrainMend RGB automatic path and nothing else.
It is not grounds for claiming parity with hardware IR or the RGB/IR alignment quality of a real
scanner.

The manual `GrainMend corpus` workflow fetches the 44 pairs, runs the Release default path, then
does the regression check and uploads the report.

## Not settled by automated checks

- Final UI review at supported window sizes and accessibility settings
- Real plugins and scanners
- Real negatives and IR image quality
- Developer ID, notarization, Gatekeeper, install on a clean Mac
- Performance on every supported Mac

The final look and the real hardware are the user's call.
A successful build does not stand in for them; results go in the
[real-device QA checklist](../validation/REAL_QA_CHECKLIST.md).

## Which document owns what

| Topic | Reference document |
|---|---|
| Current implementation and checks | This document |
| Library, folder develop, settings transfer, and print workflow | [Library to print workflow](WORKFLOW.md) |
| Scanner host spec | [Scanner plugin architecture](../architecture/SCANNER_PLUGINS.md) |
| Scanner CLI JSON | [Scanner CLI JSON](../reference/CLI_JSON.md) |
| How the catalog is stored | [Catalog storage](../architecture/CATALOG_STORAGE.md) |
| Release rules for scanner profiles | [Scanner profile quality gate](../reference/PROFILE_QUALITY_GATE.md) |
| GrainMend implementation and limits | [GrainMend](GRAINMEND.md) |
| Final look and real-device approval | [Real-device QA checklist](../validation/REAL_QA_CHECKLIST.md) |
| Install and usage | The README files in the repository root |
