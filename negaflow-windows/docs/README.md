<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, built natively for Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="version 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
  <a href="../../negaflow-mac/docs/README.md">macOS</a>
</p>

---

## What you need

To run it:

- Windows 11 (build 26100 or later), 64-bit
- 8 GB of memory for 35mm work. 16 GB is more comfortable with medium format.

To build it:

- Visual Studio 2022 with the Desktop development with C++ workload
- Windows 11 SDK (10.0.26100 or later)
- .NET 10 SDK
- CMake 3.28 or later
- Python 3.11 or later, for the icon and resource scripts

The app runs on Arm64 machines too. Release builds for Arm64 are less tested than x64.

## Installing

Download `negaflow-1.1.0-x64-setup.exe` from
[Releases](https://github.com/habinsong/negaflow/releases) and run it.

No administrator rights are needed. SmartScreen warns the first time you run it.
Click More info, then Run anyway.

To remove it, use `Uninstall negaflow` in the Start menu, or find negaflow in
Settings under Apps. Your library and photos are left alone.

## Building

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Build the C++ engine
.\scripts\build.ps1 -Preset x64-release

# Build the app and launch it
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` takes `x64-debug`, `x64-release`, `arm64-debug`, or `arm64-release`.

`run-app.ps1` is the only way to start the app during development. The app is built as an
MSIX package, so the loose executable in the build folder will not run on its own. The
script packages it, registers it for your user, and launches it by app ID. That is the same
path the installer takes, minus the installer itself.

To build the installer:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

The result lands in `out\release\win-x64`.

## Checks

```powershell
# C++ engine tests
ctest --preset x64-release --output-on-failure

# App and catalog tests
.\scripts\test-managed.ps1

# Engine and app boundary tests
.\scripts\test-interop.ps1

# Everything above in one go
.\scripts\local-ci.ps1
```

The engine tests include golden image comparisons. They read reference files that were
captured from the macOS build and check that the Windows engine produces the same pixels.

## Engine checks from the command line

`negaflow-cli.exe` is a small tool for looking at what the engine does with one file.
It is meant for checking behavior, not for daily use, so it takes flags rather than
subcommands.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# What this build is
& $cli --build-info

# Read a scan and report what the file contains
& $cli --probe-tiff scan.tif

# Develop and write a 16-bit TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# Where time goes in a develop pass
& $cli --develop-timing scan.tif

# Find the film base automatically and report what it picked
& $cli --auto-base-probe scan.tif
```

Run it with no arguments to see the full list.

## Scanners

Scanner controls stay hidden until a plugin is installed.
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) covers SANE
devices on Windows. Install it separately.

The plugin talks to scanners through the driver path Windows already provides, so software
like VueScan and SilverFast keeps working on the same machine.

## When something goes wrong

The app writes plain text logs to `%LOCALAPPDATA%\Negaflow\Logs`.

| File | What it records |
|---|---|
| `export-trace.txt` | Every export and quick export, including failures |
| `termination.txt` | What happened while the app was closing |
| `settings-change.txt` | Settings that changed and what changed them |

These are always on. If you report a problem, the relevant one usually explains it.

Two more are off by default and only for digging into a specific problem:

- `preview-trace.txt`, enabled by creating an empty file named `preview-trace.on` in the
  same folder
- `stage-trace.txt`, enabled by setting the environment variable `NEGAFLOW_STAGE_TRACE=1`
  before launching. It records pixel statistics after each step of a develop pass, which
  is how you find out where a preview and an export stopped agreeing.

## Layout

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, decoding and export (C++)
│   ├── Interop/       The bridge between the engine and the app (C#)
│   ├── Catalog.Core/  Library storage (C#)
│   ├── Shell.Core/    Develop, print, and export logic (C#)
│   ├── Shell/         Library, develop, and print screens (WinUI 3)
│   └── Cli/           Engine check tool (C++)
├── scripts/           Build, test, and packaging scripts
├── tests/             Engine, app, and boundary tests
└── Installer/windows/ NSIS installer
```

## Related documents

- [How the two differ](../../docs/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/product/GRAINMEND.md)
- [Product architecture](../../docs/architecture/PRODUCT_ARCHITECTURE.md)
