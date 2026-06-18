<div align="center">
  <h1>Negaflow</h1>
  <p>macOS Native Film Scanning & Developing Application for Plustek OpticFilm</p>

  [![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg?logo=apple)](#)
  [![Swift](https://img.shields.io/badge/Swift-5.9-F05138.svg?logo=swift)](#)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](#)
  <br/>
  <a href="README.md">한국어로 읽기</a>
</div>

<br/>

> **Status Notice:** This project is currently **Under Active Development**. APIs, project structures, and hardware support are subject to change.

## About The Project

**Negaflow** is a macOS-native film scanning and developing application designed exclusively for Plustek OpticFilm scanners. 

It completely bypasses the legacy workflows of traditional scanning software. Instead, Negaflow captures the high-bit-depth raw scan data and directly pipes it into its built-in **Chromabase color engine**. This unified approach ensures seamless orange mask removal, accurate negative inversion, and modern tone mapping, all within a single app.

## Key Features

* **Direct Scanner Control:** Achieves near-native integration utilizing the SANE `genesys` backend, supporting up to 7200 dpi and 16-bit RGB depth.
* **Chromabase Pipeline:** An automated color engine that handles film base color estimation, density inversion, and highlight roll-off mathematically.
* **Unified Format Support:** Processes not only scanner film formats (Color Negative, Slide, B&W) but also digital camera scans (RAW/DNG files).
* **Production-Ready Looks:** Comes with 6 built-in presets (Neutral, Rich Neutral, Soft Print, Clear Chrome, Warm Lab, Deep Slide) ready for immediate use.

## Prerequisites

* **OS:** macOS 13.0 (Ventura) or higher
* **Build:** Xcode 15 or higher (or Command Line Tools)
* **Dependencies:** SANE backends (`scanimage`) - *Required for actual hardware scanning*

## Installation & Build

Clone the repository and build the application using the provided shell script.
(*Note: Due to SPM CLI linker constraints with the Xcode 26 SDK's private `SwiftUICore` framework, the GUI must be built via `xcodebuild`.*)

```bash
# 1. Clone the repository
git clone <repo> Negaflow
cd Negaflow

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
Provides a single-window interface containing a preview canvas, development parameter controls, and a real-time histogram.

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

Negaflow avoids hardcoded device names. Instead, it dynamically queries the scanner's **Capabilities** to enable features.

* **Verified:** Plustek OpticFilm 8200i
* **Compatible Targets:** Plustek OpticFilm 8100, 8300i
* **Experimental:** Legacy OpticFilm series (e.g., 7200i, 7400, 7600i)

*(If you do not have scanner hardware, you can toggle **Demo** mode in the app to test the Chromabase engine using a Mock backend and bundled sample scans.)*

## Architecture

The codebase is strictly layered to separate hardware communication from mathematical color processing.

1. **ScannerKit:** The hardware abstraction layer (currently defaulting to SANE).
2. **Chromabase:** The core mathematical engine handling color transformations and density inversions.
3. **NegaflowApp / negaflow:** The user-facing interfaces (SwiftUI desktop app and CLI).

## License

The source code for this project is released under the **Apache License 2.0**.
(SANE's `scanimage` is invoked as a separate background process, and `libsane` is not statically linked. Therefore, this project is not considered a GPL derivative work.)
