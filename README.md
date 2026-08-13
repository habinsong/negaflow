<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow app icon">
</p>

<h1 align="center">negaflow</h1>

<p align="center">A macOS app for the analog-film workflow, from camera copy or scanning through development</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="website"></a>
  <a href="docs/product/PROJECT_STATUS.md"><img src="https://img.shields.io/badge/status-1.0.9%20release-EF8B26" alt="Release status"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
  <a href="negaflow-mac/Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 or later"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0 license"></a>
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
  <a href="https://habinsong.github.io/negaflow-site/">Website</a> ·
  <a href="https://habinsong.github.io/negaflow-site/camera-scanning/">Camera scanning guide</a> ·
  <a href="https://habinsong.github.io/negaflow-site/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/en/develop-dark.webp">
    <img src="docs/images/en/develop-light.webp" alt="negaflow — Develop">
  </picture>
</p>

negaflow is a macOS app for importing, inverting, and developing scanned film or film copied with a digital camera.<br>
It works with color and black-and-white, negative and positive film. Edits are stored separately from the original file.<br>
It covers the digital film workflow from library and development through printing.

The develop engine is called **Chroma Engine**. Dust and scratch repair is called **GrainMend**.<br>
In summary, it is a process that easily supports the entire process of converting analog films into digital.<br>
Scanner controls appear only when a separate plugin is installed.

> Technology keeps moving, but the process around analog photography has stood still even as film itself has become popular again.<br>
>
> Unless you make a darkroom print, film has to be converted to digital before most of us can see and share it.<br>
> That part of the process is shrinking as film labs and processing shops disappear and the available support narrows.
> <br>
> This project started with things that bothered me in different workflows, and with features I kept wishing existed.<br>
> My experience with 35mm and medium-format film became the foundation, and I built every part myself from the ground up.<br>
> It began as a toy project for my own use, but **negaflow** has since grown into something more.<br>
>
> In the end, a tool like this has to work well, stay out of the way, move quickly, and handle the routine parts properly.<br>
> **negaflow** is independently developed as a native macOS app, shaped by workflows used both in film labs and at home.
>
> **Celebrating this summer, the bicentennial of Niépce's first-ever photograph.**

---

## Install

Download the current release from [GitHub Releases](https://github.com/habinsong/negaflow/releases).<br>
For most Macs, use the Universal PKG.

| Download | Mac |
|---|---|
| `negaflow-1.0.9-1-macOS-universal.pkg` | Apple Silicon and Intel |
| `negaflow-1.0.9-1-macOS-arm64.pkg` | Apple Silicon only |

1. Download the PKG for the Mac.
2. Open it and follow the onscreen instructions.
3. Launch **negaflow** from `/Applications`.

The PKG installs `negaflow.app` directly in `/Applications`.<br>
DMG and ZIP builds are available on the same release page for manual installation.<br>
Current GitHub release files are ad-hoc signed and are not notarized by Apple.<br>
macOS may block the first launch. After attempting to open negaflow, review the warning in
**System Settings → Privacy & Security** and choose **Open Anyway** only if the downloaded
file's SHA-256 checksum matches the checksum published with the release.

> Scanner hardware requires a separate scanner plugin.<br>
> SANE scanners use [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

## Features

- Film-base measurement and color or black-and-white film inversion
- Exposure, contrast, curves, HSL, color grading, and black-and-white toning
- Sharpening, noise reduction, grain, vignette, and halation
- GrainMend dust and scratch repair, including GrainMend IR driven by a scanner infrared pass, including GrainMend IR driven by a scanner infrared pass
- Rolls, folders, collections, ratings, stacks, and virtual copies
- Zoom, crop, rotation, comparison views, histogram, and clipping display
- Camera, lens, film, and exposure notes written into the EXIF of the exported file
- Roll-level shooting notes, and library search by camera, lens, or film
- JPEG and 16-bit TIFF export, ICC profiles, and print layouts
- Per-layout black/gray/white sheets, common matte/glossy/lustre/silk previews, photo/ISO paper
  sizes, and optional in/cm rulers
- C-print destination settings and lab ICC soft proof
- Import progress, per-folder process/target development, and batch progress
- Persistent folder expansion, photo drag-and-drop, and live Finder synchronization
- Presets and copy/paste that include process, target, adjustments, crop, and orientation
- Seven print layouts: single image, contact sheet, picture package, custom package, cyanotype,
  glass plate, and gelatin silver
- Page-aware Print Export and Quick Export: a 39-photo 6 × 7 contact sheet is one composed output,
  while individual-image layouts are a bounded 39-file batch, with linear progress and percentage

> Completed checks are recorded in [Project Status](docs/product/PROJECT_STATUS.md). <br>

## Chroma Engine

Chroma Engine is the film inversion and develop engine in the `Chromabase` module.<br>
Before inverting a negative, it measures the unexposed film base.<br>
If automatic measurement is wrong, you can sample an area with the eyedropper or enter RGB values yourself.

The default is the `MAIN` target with manual adjustments.<br>
Auto Tone, Auto White Balance, Auto Levels, and Auto Color run only when you ask for them.

Available develop targets:

- `MAIN`: standard development
- `PRINT`: output through a printer ICC profile
- `HS`, `SP`: minilab-style development
- `F135`, `HR`: development styles for those equipment families
- `EXPIRED`: old-film recovery

Output can use sRGB, Display P3, Adobe RGB, or a custom RGB ICC profile.<br>
See [Chroma Engine](docs/product/CHROMA_ENGINE.md) for the inversion and color-processing order.

## GrainMend

**GrainMend repairs film defects: dust, pinholes, scratches, and emulsion damage.** <br>


| GrainMend RGB | What it does |
|---|---|
| Auto | Finds and repairs defects across the whole photograph. |
| Guided | Searches for defects inside an area you mark. |
| Brush | Lets you paint the place to repair. |
| Clone Stamp | Copies pixels from a source point you choose. |


The Auto and Guided tools in **GrainMend RGB** fill a defect using nearby texture, and they <br>
also inspect direction and surrounding structure so lines or grids in the scene are not erased as scratches. <br>
Each result is kept as a GrainMend layer. <br><br>
> Auto removes the defects common to a photograph. If candidates crowd in too densely to apply safely, it stops without changing the image and points you to Guided. <br>
> Guided is made for the varied dust that scanning introduces. Brush repairs what the automatic passes missed, and Clone Stamp copies the source pixels you pick. <br>
Every **GrainMend RGB** layer can have its strength changed, its mask inspected, and can be turned off or deleted on its own.



If the scanner plugin supplies an infrared channel, **GrainMend IR** adds its detection result to the same edit history.<br><br>

**GrainMend RGB** is an independent software method, distinct from hardware infrared cleaning, and <br>
**GrainMend IR** uses the scanner's infrared channel — it is not an implementation of, or compatibility mode for, Digital ICE, iSRD, or SRDx.

See [GrainMend](docs/product/GRAINMEND.md) for the implementation and its quality and performance checks.

## Film profiles

The app includes 15 scanner profiles made from film material shot by the project author.<br>
Together, they contain 928 image observations.<br>
Every profile is currently marked `realOnly`: it is based on real scans, but has not passed an independent paired-reference accuracy check.

Profiles are never applied from the scanner name alone.<br>
You must choose one yourself.<br>
The app also checks the SHA-256 of each profile and its manifest.

`928` is the sum of observations across profile groups, not 928 different photographs.<br>
The same film can appear in more than one scanner group.<br>
I reviewed all 928 source scans directly and excluded files with false detections or missed defects before measuring the data used to build the profiles.<br>
The data and build process are documented in [Film Profiles](docs/product/FILM_PROFILES.md).

## Basic workflow

1. Import an image or scan with an installed plugin.
2. Choose the film type and measure the film base.
3. Adjust color and tone in Chroma Engine.
4. Apply GrainMend where it is needed.
5. Check the result with comparison views and the histogram, then print or export it.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/en/library-dark.webp">
    <img src="docs/images/en/library-light.webp" alt="negaflow — Library">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/en/print-dark.webp">
    <img src="docs/images/en/print-light.webp" alt="negaflow — Print">
  </picture>
</p>

The interface was made for people who actually work with photographs, not as a generic AI-generated mockup.<br>
Anyone who enjoys photography should be able to find their way around it.

## From library to print

Import does not develop a photo by default. It first creates the source thumbnail and folder entry.
Development starts when you apply a process and target to a folder or enter Develop. Automatic
development can be enabled under Workflow in Settings; its default is off.

Collapsed folders stay collapsed after relaunch. Photos can be dragged between folders. If the
destination already has the same file name, negaflow adds a number instead of overwriting it.
Moving or renaming a source or folder in Finder updates the library by rescanning only the folder
that changed.

Develop copy/paste and user presets include process, target, film-base settings, tone, color,
detail, crop, rotation, flips, and straightening. When several photos are selected, paste applies
to the whole selection.

A printer output profile in Print is applied to the composed page, so repeated placements and
mixed-photo packages all receive the same output conversion. It does not change the Develop
preview.

See [Library to print workflow](docs/product/WORKFLOW.md) for the exact behavior and its effect on
source files.

## Build from source

### Requirements

- macOS 14.0 or later
- GUI app: Xcode 26
- Engine and CLI: Swift 5.9 or later
- Hardware scanning: a separate scanner plugin

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Build a Release app and launch it
bash scripts/run-app.sh

# Build without launching
bash scripts/run-app.sh build
```

The GUI app is built with `xcodebuild`.<br>
`scripts/run-app.sh` builds the code, assembles the app bundle, and signs it locally.<br>
Use `swift build` when you only need the engine and CLI.

## CLI

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

# List profiles and check the engine
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

Run `negaflow` without arguments to see every option.

## Scanners

negaflow does not guess features from a scanner model name.<br>
It uses only the resolutions, bit depths, scan areas, exposure controls, and IR support reported by the plugin.

SANE devices are handled by the separate GPL project [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).<br>
The plugin runs as a separate process and talks to the app through JSON.<br>
The main negaflow app does not contain or link SANE code.

## Repository

| Module | Job |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, profiles, and export |
| `ScannerKit` | Scanner capabilities and external plugin connection |
| `negaflowApp` | Library, develop, scan, and export interface |
| `negaflowCLI` | Develop, scan, benchmark, and self-test commands |

See [Product Architecture](docs/architecture/PRODUCT_ARCHITECTURE.md) for the data flow between modules.

## Development checks

```bash
# Swift tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI Release build
bash scripts/run-app.sh build

# Full repository gate
bash scripts/ci-gate.sh
```

Automated tests cover code behavior and regressions.<br>
Scanner-specific behavior, final image quality, signing, and notarization are separate checks.

## Documentation

| Document | Contents |
|---|---|
| [Chroma Engine](docs/product/CHROMA_ENGINE.md) | Film base, inversion, color processing, and develop order |
| [GrainMend](docs/product/GRAINMEND.md) | Detection and repair, IR, edit history, performance, and quality checks |
| [Film profiles](docs/product/FILM_PROFILES.md) | Source analysis and profile generation |
| [Library-to-print workflow](docs/product/WORKFLOW.md) | Import, folder synchronization, batch develop, settings transfer, and print profiles |
| [Product architecture](docs/architecture/PRODUCT_ARCHITECTURE.md) | App, engine, scanner, storage, and export |
| [Project status](docs/product/PROJECT_STATUS.md) | Implementation state, measurements, and work still to verify |
| [Real-device QA checklist](docs/validation/REAL_QA_CHECKLIST.md) | Checks that require real hardware or a visual review |

## License

The main negaflow project is distributed under the [Apache License 2.0](LICENSE).

negaflow is not affiliated with or sponsored by Kodak, Fujifilm, Noritsu, LaserSoft Imaging, or other trademark owners.<br>
Product names are used only to identify a measured or compatible target.<br>
See [Trademark Notice](TRADEMARKS.md).
