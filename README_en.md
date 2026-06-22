<div align="center">
  <h1>negaflow</h1>
  <p>macOS Native Film Scanning & Developing Application for Plustek OpticFilm</p>

  [![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg?logo=apple)](#)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift)](#)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#)
  <br/>
  <a href="README.md">한국어로 읽기</a>
</div>

<br/>

> **Status Notice:** The app now provides a real SANE scan-to-development workflow. Hardware coverage and output quality continue to be verified.

## About The Project

**negaflow** is a macOS-native film scanning and developing application designed exclusively for Plustek OpticFilm scanners. 

It completely bypasses the legacy workflows of traditional scanning software. Instead, negaflow captures the high-bit-depth raw scan data and directly pipes it into its built-in **Chromabase color engine**. This unified approach ensures seamless orange mask removal, accurate negative inversion, and modern tone mapping, all within a single app.

## Key Features

* **Direct Scanner Control:** Achieves near-native integration utilizing the SANE `genesys` backend, supporting up to 7200 dpi and 16-bit RGB depth.
* **Chromabase Pipeline:** An automated color engine that handles film base color estimation, density inversion, and highlight roll-off mathematically.
* **Unified Format Support:** Processes not only scanner film formats (Color Negative, Slide, B&W) but also digital camera scans (RAW/DNG files).
* **Production-Ready Looks:** Comes with 6 built-in presets (Neutral, Rich Neutral, Soft Print, Clear Chrome, Warm Lab, Deep Slide) ready for immediate use.
* **Frame-Based Roll Workflow:** `Scan Next` adds the next frame in the current session, while each frame keeps its own raw scan, development state, and export result.
* **Photo-First Editor:** The canvas supports zoom, pan, drag crop, raw/developed comparison, an interactive histogram, and rotate/flip tools.
* **Session Orientation:** Rotation and flips apply to the current frame and become the default for following scans. Crop never carries forward, and the orientation template resets when the app restarts.
* **Progressive Development Controls:** Basic Tone, Tone Curve, Color, Calibration, and Detail & Effects can be opened or closed independently and reset by section.

## Prerequisites

* **OS:** macOS 13.0 (Ventura) or higher
* **Build:** Xcode 15 or higher (or Command Line Tools)
* **Dependencies:** SANE backends (`scanimage`) - *Required for actual hardware scanning*

## Installation & Build

Clone the repository and build the application using the provided shell script.
(*Note: Due to SPM CLI linker constraints with the Xcode 26 SDK's private `SwiftUICore` framework, the GUI must be built via `xcodebuild`.*)

```bash
# 1. Clone the repository
git clone <repo> negaflow
cd negaflow

# 2. Install SANE backend (via Homebrew)
brew install sane-backends

# 3. Build and run the app
bash scripts/run-app.sh
```

## Usage

### GUI Application
```bash
bash scripts/run-app.sh run
```
The single window is split into a frame list, a central canvas, and a right inspector. The inspector follows `Scan → Base → Tools → Tone → Color → Detail → Export`, keeping only the section being used open.

1. Select the connected scanner and choose `Scan` or `Scan Next`.
2. Use the central canvas for zoom, pan, crop, and raw/developed comparison.
3. Set orientation in the tool strip; the displayed `Next scan` value is inherited by later frames.
4. Open the required development section and use its reset control to clear only that section's manual adjustments.
5. Export JPEG or 16-bit TIFF with an optional sidecar JSON file.

### Command Line Interface (CLI)
A robust CLI is available for automated scripting, batch processing, or headless testing.

```bash
# Build the targets
swift build

# Scanner Operations
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>
.build/debug/negaflow scan --dpi 3600

# Film Development
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral
.build/debug/negaflow develop photo.dng out.jpg --look clear-chrome
```

## Supported Hardware

negaflow avoids hardcoded device names. Instead, it dynamically queries the scanner's **Capabilities** to enable features.

* **Verified:** Plustek OpticFilm 8100 — real consecutive 3600 dpi / 16-bit RGB scans and development completed
* **Compatible Targets:** Plustek OpticFilm 8200i, 8300i
* **Experimental:** Legacy OpticFilm series (e.g., 7200i, 7400, 7600i)

*(If you do not have scanner hardware, you can toggle **Demo** mode in the app to test the Chromabase engine using a Mock backend and bundled sample scans.)*

## Verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/run-app.sh build
```

Automated tests cover the color engine, image transforms, SANE capability discovery, and bracket merging. GUI changes are exercised on the real scanner path with Demo disabled using `Scan → rotate/flip → Scan Next`.

## Architecture

The codebase is strictly layered to separate hardware communication from mathematical color processing.

1. **ScannerKit:** The hardware abstraction layer (currently defaulting to SANE).
2. **Chromabase:** The core mathematical engine handling color transformations and density inversions.
3. **negaflowApp / negaflow:** The user-facing interfaces (SwiftUI desktop app and CLI).

## License

The source code for this project is released under the **Apache License 2.0**.
(SANE's `scanimage` is invoked as a separate background process, and `libsane` is not statically linked. Therefore, this project is not considered a GPL derivative work.)
