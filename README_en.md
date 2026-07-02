<div align="center">
  <h1>negaflow</h1>
  <p>macOS Native Film Import, Scan & Developing Application</p>

  [![macOS](https://img.shields.io/badge/macOS-14.0+-black.svg?logo=apple)](#)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift)](#)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#)
  <br/>
  <a href="README.md">한국어로 읽기</a>
</div>

<br/>

> **Status Notice:** The main negaflow app is image-import and development first. Real SANE hardware scanning is enabled only when the separate GPL plugin [negaflow-scanner-sane](https://github.com/habinsong/negaflow-scanner-sane.git) is installed.

## About The Project

**negaflow** is a macOS-native application for importing, developing, and exporting film scan sources.

It imports RAW/DNG/TIFF/JPEG/PNG sources first, and can add real scanner capture through an external scanner plugin when needed. The built-in **Chromabase color engine** handles negative inversion, film-base correction, `main`/`print` targets, tone mapping, soft proofing, local adjustments, and export in one workflow.

## Key Features

* **Image Import First:** Imports RAW/DNG/TIFF/JPEG/PNG/HEIF and camera RAW formats recognized by macOS.
* **Optional Scanner Plugins:** SANE scanning code is removed from this repository and provided by the external-process `negaflow-scanner-sane` plugin over a JSON/CLI contract.
* **Chromabase Pipeline:** Handles film-base estimation, orange-mask removal, highlight roll-off, flat `main` masters, and finished `print` targets.
* **Darkroom-Style Local Adjustments:** Applies non-destructive dodge/burn with brush, radial, linear, and polygon masks.
* **Soft Proof Preview:** Uses built-in ICC-backed soft proofing with paper/black-ink simulation for sRGB, Display P3, and print-oriented output checks.
* **B&W Toning:** Applies Selenium, Sepia, Shadow Hue, Highlight Hue, and Strength to black-and-white negative/positive frames.
* **Paired Export:** Can export the corrected file together with a `-main-flat` `main` master for later editing.
* **Built-In Looks:** Includes 6 looks (Neutral, Rich Neutral, Soft Print, Clear Chrome, Warm Lab, Deep Slide).
* **Frame-Based Roll Workflow:** `Scan Next` adds the next frame in the current session, while each frame keeps its own raw scan, development state, and export result.
* **Photo-First Editor:** The canvas supports zoom, pan, drag crop, raw/developed comparison, an interactive histogram, and rotate/flip tools.
* **Session Orientation:** Rotation and flips apply to the current frame and become the default for following scans. Crop never carries forward, and the orientation template resets when the app restarts.
* **Progressive Development Controls:** Basic Tone, Tone Curve, Color, Calibration, and Detail & Effects can be opened or closed independently and reset by section.

## Prerequisites

* **OS:** macOS 14.0 (Sonoma) or higher
* **Build:** Xcode 15 or higher (or Command Line Tools)
* **Dependencies:** The main app has no scanner runtime dependency. Real SANE hardware scanning requires the separate `negaflow-scanner-sane` plugin and `scanimage`.

## Installation & Build

Clone the repository and build the application using the provided shell script.
(*Note: Due to SPM CLI linker constraints with the Xcode 26 SDK's private `SwiftUICore` framework, the GUI must be built via `xcodebuild`.*)

```bash
# 1. Clone the repository
git clone https://github.com/habinsong/negaflow.git negaflow
cd negaflow

# 2. Build and run the app
bash scripts/run-app.sh
```

To use a real SANE scanner, install the plugin from its own repository:

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
brew install sane-backends
./install.sh
```

## Usage

### GUI Application
```bash
bash scripts/run-app.sh run
```
The single window is split into a frame list, a central canvas, and a right inspector. The inspector follows `Scan → Base → Tools → Tone → Color → Detail → Export`, keeping only the section being used open.

1. Import image files, or select a real scanner and choose `Scan` / `Scan Next` when the SANE plugin is installed.
2. Use the central canvas for zoom, pan, crop, and raw/developed comparison.
3. Set orientation in the tool strip; the displayed `Next scan` value is inherited by later frames.
4. Open the required development section and use its reset control to clear only that section's manual adjustments.
5. Export JPEG or 16-bit TIFF with an optional sidecar JSON file.

### Command Line Interface (CLI)
The CLI supports automated scripting, batch processing, and headless testing.

```bash
# Build the targets
swift build

# Scanner operations (external plugin required)
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>
.build/debug/negaflow scan --dpi 3600

# Film Development
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target print
.build/debug/negaflow develop photo.dng out.jpg --look clear-chrome
```

## Supported Hardware

The main app avoids hardcoded device names. Installed scanner plugins report **Capabilities**, and negaflow builds the UI and scan options from those capabilities.

* **Plugin repository:** [habinsong/negaflow-scanner-sane](https://github.com/habinsong/negaflow-scanner-sane.git)
* **Verified path:** Plustek OpticFilm 8100 SANE `genesys` detection and 3600 dpi / 16-bit RGB scan flow
* **Compatible targets:** Plustek OpticFilm and other SANE-supported scanners reported by `scanimage -L` / `scanimage -A`

Without scanner hardware or the plugin, the app still supports image import and the Mock backend for engine verification.

## Verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/run-app.sh build
```

Automated tests cover the color engine, image transforms, import loaders, the external scanner plugin host, and export. GUI changes are exercised through `Import/Scan → Develop → Export` using imported files or an installed scanner plugin.

## Architecture

The codebase is strictly layered to separate hardware communication from mathematical color processing.

1. **ScannerKit:** The scanner abstraction layer. The main app includes Mock and external-process plugin hosting; SANE implementation lives in a separate repository.
2. **Chromabase:** The core mathematical engine handling color transformations and density inversions.
3. **negaflowApp / negaflow:** The user-facing interfaces (SwiftUI desktop app and CLI).

## License

The source code for this project is released under the **Apache License 2.0**.
SANE scanner support is provided by the separate GPL-2.0-or-later `negaflow-scanner-sane` project. The main app invokes that plugin only as a separate OS process over a JSON/CLI protocol and does not link or include GPL scanner code.
