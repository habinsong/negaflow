<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow app icon">
</p>

<h1 align="center">negaflow</h1>

<p align="center">An app for the analog-film workflow, from camera copy or scanning through development and printing. Native on both macOS and Windows.</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="website"></a>
  <a href="#install"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="version 1.1.0"></a>
  <a href="negaflow-mac/docs/README.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
  <a href="negaflow-windows/docs/README.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
    <img src="docs/images/en/develop-light.webp" alt="negaflow Develop">
  </picture>
</p>

negaflow imports scanned film or film copied with a digital camera, then inverts and develops it.<br>
It handles color and black-and-white, negative and positive. Your edits stay separate from the original file.<br>
Library, development, and printing all happen in one app.

The develop engine is called **Chroma Engine**. Dust and scratch repair is called **GrainMend**.<br>
You can import image files and develop them without any scanner. Scanner controls appear only when a separate plugin is installed.

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
> **negaflow** is independently developed, shaped by workflows used both in film labs and at home.
>
> **Celebrating this summer, the bicentennial of Niépce's first-ever photograph.**

---

## Two apps, built separately

negaflow runs on macOS and on Windows. The two apps share no code.

| | macOS | Windows |
|---|---|---|
| Interface | SwiftUI | WinUI 3 |
| Engine | Swift and Core Image | C++ and Direct3D |
| Color management | ColorSync | Windows ICM |

Feed the same photo to both and you get the same picture out. Reference images captured
from the macOS build are read back by the Windows test suite, so the two stay matched
pixel for pixel.

Each version is written for its own platform instead of ported across, which meant
building the whole thing twice. In exchange, both behave the way people expect on the
system they are using.

- [macOS docs](negaflow-mac/docs/README.md)
- [Windows docs](negaflow-windows/docs/README.md)
- [How the two differ](docs/platform/PLATFORM_DIFFERENCES.md)

---

## Install

Download the current release from [GitHub Releases](https://github.com/habinsong/negaflow/releases).

### macOS

| Download | Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon and Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Apple Silicon only |

Most Macs should use the Universal PKG. Apple Silicon Macs can use the arm64 PKG instead.

1. Download the PKG that matches your Mac.
2. Open it and follow the installer.
3. Launch **negaflow** from `/Applications`.

The PKG installs `negaflow.app` straight into `/Applications`.
A DMG and a ZIP are on the same release page if you would rather install by hand.
The app is not notarized, so the first launch needs you to open System Settings,
go to Privacy and Security, and click Open Anyway.

### Windows

| Download | PC |
|---|---|
| `negaflow-1.1.0-x64-setup.exe` | Windows 11 (x64) |

1. Download the installer and run it.
2. Pick a language and follow the prompts.
3. Launch **negaflow** from the Start menu.

Everything is installed inside your user folder, so no administrator rights are needed.
To remove it, use `Uninstall negaflow` in the Start menu or the app list in Settings.
The installer is unsigned, so SmartScreen warns once. Click More info, then Run anyway.

> Connecting a real scanner needs a separate plugin.<br>
> SANE scanners are handled by [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), which supports both macOS and Windows.

---

## Features

- Film base measurement, inversion for color and black-and-white film
- Exposure, contrast, curves, HSL, color grading, black-and-white toning
- Sharpening, noise reduction, grain, vignette, halation
- GrainMend for dust and scratch repair, plus GrainMend IR when the scanner offers an infrared channel
- Rolls, folders, collections, ratings, stacks, virtual copies
- Zoom, crop, rotate, before-and-after view, histogram, clipping display
- Camera, lens, film, and exposure notes written into the EXIF of exported files
- Per-roll shooting notes and library search by camera, lens, or film
- JPEG and 16-bit TIFF export with ICC profiles and print layouts
- Black, gray, and white sheets per layout, matte, glossy, luster, and silk previews, photo and ISO paper sizes, rulers in inches or centimeters
- C-print lab and paper settings with a soft-proof preview through the lab ICC profile
- Import progress, batch develop process and target per folder, processing progress
- Folder list that remembers what you collapsed, drag to move photos, automatic pickup of changes made in File Explorer or Finder
- Presets and copy-paste that carry process, target, tone, color, detail, crop, and orientation together
- Seven print layouts: single image, contact sheet, picture package, custom package, cyanotype, dry plate, gelatin
- Contact sheets export as one composed file, one-per-page layouts export as separate files, both with a progress bar

---

## Chroma Engine

**Chroma Engine** handles film inversion and development.<br>
Before inverting a negative it measures the film base from an area the light never reached.<br>
If the automatic measurement is off, pick an area with the eyedropper or type RGB values yourself.<br>
The default is `MAIN` with manual adjustments. Auto tone, auto white balance, auto levels, and auto color only run when you press them.
<br><br>
Develop targets:

- `MAIN`: normal development
- `PRINT`: output through a printer ICC profile
- `HS`, `SP`: minilab-style development
- `F135`, `HR`: lab-scanner-style development
- `EXPIRED`: recovery for old film

Output can be sRGB, Display P3, Adobe RGB, or your own RGB ICC profile.<br>
The order of inversion and color processing is in the [Chroma Engine doc](docs/product/CHROMA_ENGINE.md).

---

## GrainMend

**GrainMend repairs dust, pinholes, scratches, and emulsion damage.**

| GrainMend RGB | What it does |
| ----- | ------------------------- |
| Auto | Finds and repairs defects across the whole photo. |
| Guided | Looks for defects only inside an area you mark. |
| Brush | Paint over the spots you want repaired. |
| Clone stamp | Copies pixels from one place to another. |

Auto and Guided fill defects using the texture around them.<br>
They also check direction and surrounding structure so that a line or grid in the photo does not get mistaken for a scratch.<br>
Repairs are kept as GrainMend layers.<br><br>

> Auto handles ordinary defects. When too many candidates pile up to apply safely, it stops without changing the photo and suggests using Guided instead. <br>
> Guided is aimed at dust that appears during scanning. Brush repairs what Auto missed, and Clone stamp copies source pixels you choose. <br>

Every **GrainMend RGB** layer can have its strength changed, its mask inspected, and can be turned off or deleted on its own.

**GrainMend IR** adds infrared detection results to the same edit history when the scanner plugin provides an infrared channel.<br><br>

**GrainMend RGB** is a software approach and works differently from hardware infrared cleaning.<br>
**GrainMend IR** uses the scanner's infrared channel, but it is not an implementation of, or a compatibility mode for, Digital ICE, iSRD, or SRDx.

How it works, along with the quality and performance targets, is in the [GrainMend doc](docs/product/GRAINMEND.md).

---

## Film profiles

The bundle ships 15 scanner profiles built from film I shot myself.<br>
They hold 928 image observations in total, and every one is currently marked `realOnly`.
<br>

`realOnly` means the profile was built from real scans but has not yet been checked against an independent reference scan pair.<br>
Profiles are never applied automatically from a scanner name. You pick them yourself. SHA-256 hashes for the files and the list are published alongside.

<br>

The number 928 is the sum of observations across profiles. The same film can be counted on more than one device, so it does not mean 928 different photos. Each of the 928 scans was checked by hand and files with bad detections were left out. The profiles are built on those measurements.<br><br>
How the material was gathered is in the [film profiles doc](docs/product/FILM_PROFILES.md).

---

## Basic workflow

1. Import image files, or scan with an installed plugin.
2. Choose the film type and measure the film base.
3. Adjust color and tone in Chroma Engine.
4. Apply GrainMend where a photo needs it.
5. Check the result with the before-and-after view and the histogram, then print or export.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/en/library-dark.webp">
    <img src="docs/images/en/library-light.webp" alt="negaflow Library">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/en/print-dark.webp">
    <img src="docs/images/en/print-light.webp" alt="negaflow Print">
  </picture>
</p>

## From library to print

Importing on its own does not develop anything. Thumbnails and folders come first.
Development starts when you pick a process and target for a folder and press **Apply**,
or when you open the Develop view. If you want it to happen automatically, turn on the
default in Settings under workflow. It ships off.

Collapsed and expanded folders stay that way after a restart. Photos can be dragged
between folders, and a name collision gets a number rather than overwriting the original.
Move or rename a file or folder in File Explorer or Finder and the library rereads just
that folder to catch up.

Copying develop settings, pasting them, and saving presets all carry the process, target,
film base, tone, color, detail, crop, rotation, flip, and straightening. Select several
photos and it applies to all of them at once.

The printer output profile in the Print view applies to the finished page, after layout.
Put the same photo in a picture package several times, or mix different photos, and
nothing gets skipped. This profile does not affect the preview in the Develop view.

The details, and what each action does to your original files, are in
[From library to print](docs/product/WORKFLOW.md).

## Building from source

The tools and commands differ per platform. Each platform doc has the full version.

**macOS**

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Build a Release app and launch it
bash scripts/run-app.sh

# Build without launching
bash scripts/run-app.sh build
```

You need macOS 14 or later and Xcode 26. To build only the engine and CLI, use `swift build`.
More in the [macOS docs](negaflow-mac/docs/README.md).

**Windows**

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Build the engine
.\scripts\build.ps1 -Preset x64-release

# Build the app and launch it
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

You need Windows 11, Visual Studio 2022, and the .NET 10 SDK.
More in the [Windows docs](negaflow-windows/docs/README.md).

## Scanners

negaflow never guesses a scanner model and opens features based on the name.<br>
It uses only the resolution, bit depth, scan area, exposure, and infrared support that the plugin reports.

SANE devices are handled by [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), a separate GPL project.<br>
The plugin runs as its own process and talks over JSON.<br>
**negaflow** neither includes nor links SANE code.

## Repository

```
negaflow/
├── negaflow-mac/       macOS app and engine (Swift)
├── negaflow-windows/   Windows app and engine (C#, C++)
└── docs/               shared documentation
```

**macOS**

| Module | Role |
| ------------- | ----------------------------- |
| `Chromabase` | Chroma Engine, GrainMend, profiles, export |
| `ScannerKit` | Scanner capability checks and plugin connection |
| `negaflowApp` | Library, develop, scan, and export screens |
| `negaflowCLI` | Develop, scan, benchmark, and self-check commands |

**Windows**

| Module | Role |
| ------------- | ----------------------------- |
| `Native` | Chroma Engine, GrainMend, export (C++) |
| `Interop` | The bridge between engine and app |
| `Catalog.Core` | Library storage |
| `Shell.Core` | Develop, print, and export logic |
| `Shell` | Library, develop, and print screens (WinUI 3) |

How data moves between modules is in the [product architecture doc](docs/architecture/PRODUCT_ARCHITECTURE.md).

## Documentation

| Doc | Contents |
| -------------------------------------------------- | ------------------------------- |
| [Chroma Engine](docs/product/CHROMA_ENGINE.md) | Film base, inversion, color processing, develop order |
| [GrainMend](docs/product/GRAINMEND.md) | Defect detection and repair, IR, edit history, quality and performance targets |
| [Film profiles](docs/product/FILM_PROFILES.md) | Source material analysis and profile generation |
| [From library to print](docs/product/WORKFLOW.md) | Import, folder sync, batch develop, settings copy, print profile |
| [Product architecture](docs/architecture/PRODUCT_ARCHITECTURE.md) | App, engine, scanner, storage, export structure |
| [How the two differ](docs/platform/PLATFORM_DIFFERENCES.md) | What is the same and what is not, between macOS and Windows |
| [macOS docs](negaflow-mac/docs/README.md) | macOS install, build, CLI |
| [Windows docs](negaflow-windows/docs/README.md) | Windows install, build, engine checks |

---
## License

**negaflow** is released under the [Apache License 2.0](LICENSE).

**negaflow** is not affiliated with or sponsored by Kodak, Fujifilm, Noritsu, LaserSoft Imaging, or any other trademark holder.<br>
Product names appear only to identify what something is compatible with or measured against. See the [trademark notice](TRADEMARKS.md).
