<p align="center">
  <img src="src/Shell/Assets/AppIcon-1024.png" width="128" alt="negaflow app icon">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">Import, invert, and develop scanned film — or film copied with a digital camera — on Windows</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="website"></a>
  <img src="https://img.shields.io/badge/release-1.1.0-EF8B26" alt="1.1.0">
  <img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0 license"></a>
</p>

---

negaflow is an app for the analog-film workflow: bring in a scan or a camera copy, measure the film
base, invert it, develop it, and print it. It handles color and black-and-white, negative and
positive. Your original file is never rewritten — every edit lives in the catalog beside it.

The develop engine is called **Chroma Engine**. Dust and scratch repair is called **GrainMend**.

This is the Windows build. It is a native port, not a wrapper: a C++20 imaging engine behind a
narrow C ABI, a .NET 10 / WinUI 3 shell, and Direct3D 11 compute for the develop pipeline. It
matches the macOS app's results and its interface.

## Install

Download `Negaflow-1.1.0-x64-setup.exe` from
[GitHub Releases](https://github.com/habinsong/negaflow/releases) and run it.

The installer writes only to your own user profile — `%LOCALAPPDATA%\Negaflow\App`. It does not
need administrator rights to install the app.

Everything the app needs is inside the installer. You do not have to install .NET, the Windows App
Runtime, or the Visual C++ redistributable separately.

**Requirements**

| | |
|---|---|
| Windows | Windows 11, build 26100 or newer |
| Architecture | x64 |
| Graphics | Any Direct3D 11 GPU. There is a full CPU path when none is available. |

The release is not signed with a commercial certificate, so SmartScreen will warn on first run.
Check the SHA-256 published beside the download before choosing **More info → Run anyway**.

## Scanners

Scanner controls appear only when a scanner plugin is installed. negaflow itself contains no
scanner code and stays neutral about how a scanner is driven.

For SANE-supported scanners, install
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) — a separate,
GPL-licensed project. Its Windows installer carries the plugin, the patched SANE runtime, and the
device-interface INF that opens the scanner through Windows' own `usbscan` driver. No vendor
software and no driver replacement tools are involved.

Verified on real hardware: Plustek OpticFilm 8100 (`genesys`) and Epson GT-X900 / V700
(`epson2`), including the infrared channel that feeds GrainMend IR.

## What it does

- Film-base measurement, then color or black-and-white inversion
- Exposure, contrast, curves, HSL, color grading, black-and-white toning
- Sharpening, noise reduction, grain, vignette, halation
- GrainMend dust and scratch repair, including GrainMend IR from a scanner's infrared pass
- Rolls, folders, collections, ratings, stacks, virtual copies
- Zoom, crop, rotation, comparison views, histogram, clipping display
- Camera, lens, film, and exposure notes written into the exported file's EXIF
- JPEG and 16-bit TIFF export, ICC profiles, print layouts
- C-print destination settings and lab ICC soft proof
- Presets and copy/paste covering process, target, adjustments, crop, and orientation
- Seven print layouts, from a single image to contact sheets, cyanotype, and gelatin silver

**Camera RAW.** Windows ships no RAW codec of its own — RAW is a separate Store package that is not
guaranteed to be present. negaflow bundles LibRaw so the same file opens here and on macOS. Canon
CR3, Sony ARW, Fujifilm RAF, Panasonic RW2, Olympus/OM ORF, Nikon NEF, Adobe DNG and the rest of
LibRaw's list all import directly.

## Building from source

You need Visual Studio 2022 or newer with the C++ desktop workload, the .NET 10 SDK, CMake, and
NSIS. Then:

```powershell
# native engine, managed shell, tests, installer, and a silent install/uninstall check
.\scripts\local-ci.ps1

# just the installer
.\scripts\build-release.ps1 -Architecture x64
```

`build-release.ps1` produces `out\release\win-x64\Negaflow-<version>-x64-setup.exe` together with
its SHA-256. `scripts\build-libraw.ps1` builds the bundled RAW decoder from a pinned upstream
commit and refuses to continue if the result would need a redistributable runtime.

## Third-party code

The imaging engine links no third-party libraries. It calls Windows itself — WIC, ICM, Direct3D —
and nothing else, with the MSVC runtime linked statically.

Three components ship alongside it, each loaded at run time rather than linked in:

| Component | License | Why |
|---|---|---|
| LibRaw | LGPL-2.1 (or CDDL-1.0) | Camera RAW decoding, which Windows does not provide |
| SQLite (`e_sqlite3`) | Public domain | Catalog storage |
| Windows App Runtime | Microsoft | WinUI 3 |

Exact versions, pinned source URLs, hashes, and the obligations each one carries are recorded in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) and
[`third_party/manifest/components.json`](third_party/manifest/components.json).

negaflow itself is Apache-2.0. The SANE scanner plugin is GPL and lives in its own repository for
that reason.
