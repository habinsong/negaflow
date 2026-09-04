<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, built natively for Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.4-EF8B26" alt="version 1.1.4\"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 or later"></a>
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

- Windows 11 24H2 (build 26100) or later, 64-bit
- 8 GB of memory for 35mm work, 16 GB is more comfortable with medium format

To build it:

- Visual Studio 2022 with the Desktop development with C++ workload
- Windows 11 SDK (10.0.26100 or later)
- .NET 10 SDK
- CMake 3.28 or later
- Python 3.11 or later, for the icon and resource scripts

It runs on Arm64 machines too. Arm64 releases are less tested than x64.

## Installing

Download `negaflow-1.1.4-win-x64.exe` from [Releases](https://github.com/habinsong/negaflow/releases) and run it.

No administrator rights are needed. SmartScreen warns once on the first run. Click More info, then run it.

Uninstall from `Uninstall negaflow` in the Start menu or the app list in Settings. Your library and photos are left alone.

## Building

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Build the C++ engine
.\scripts\build.ps1 -Preset x64-release

# Build the app and launch it
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` accepts `x64-debug`, `x64-release`, `arm64-debug`, and `arm64-release`.

`run-app.ps1` is the only way to launch the app during development. The app builds as an MSIX package, so running the exe in the build folder does nothing. The script builds the package, registers it for the current user, and launches it by app ID.

To build the installer:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

The output lands in `out\release\win-x64`.

## Checks

```powershell
# C++ engine tests
ctest --preset x64-release --output-on-failure

# App and catalog tests
.\scripts\test-managed.ps1

# Engine and app boundary tests
.\scripts\test-interop.ps1

# All of the above at once
.\scripts\local-ci.ps1
```

The engine tests include a golden image comparison. They read the reference files rendered by the macOS build and check that the Windows engine produces the same pixels.

## Checking the engine from the command line

`negaflow-cli.exe` shows how the engine handles a single file. It takes flags rather than subcommands.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# See what this build is
& $cli --build-info

# See what is inside a scan file
& $cli --probe-tiff scan.tif

# Develop and save as 16-bit TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# See where the time goes in one develop pass
& $cli --develop-timing scan.tif

# Find the film base automatically and see what it picked
& $cli --auto-base-probe scan.tif
```

Run it with no arguments for the full list.

## Scanners

Scanner controls stay hidden until a plugin is installed. SANE devices are handled by [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), installed separately.

The plugin talks to the scanner through the driver paths Windows already provides. You can keep using VueScan or SilverFast on the same machine.

## When something goes wrong

The app writes text logs to `%LOCALAPPDATA%\Negaflow\Logs`.

| File | What it records |
|---|---|
| `export-trace.txt` | Export and quick export, including failures |
| `termination.txt` | What happened while the app was closing |
| `settings-change.txt` | Settings that changed and what changed them |

Those three are always on. Two more turn on only when you are chasing a specific problem.

- `preview-trace.txt`. Create an empty file named `preview-trace.on` in the same folder to turn it on.
- `stage-trace.txt`. Set the environment variable `NEGAFLOW_STAGE_TRACE=1` before launching the app. It records pixel statistics at each develop stage.

## Layout

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, decoding and export (C++)
│   ├── Interop/       The layer between engine and app (C#)
│   ├── Catalog.Core/  Library storage (C#)
│   ├── Shell.Core/    Develop, print, and export logic (C#)
│   ├── Shell/         Library, develop, and print screens (WinUI 3)
│   └── Cli/           Engine inspection tool (C++)
├── scripts/           Build, test, and packaging scripts
├── tests/             Engine, app, and boundary tests
└── Installer/windows/ NSIS installer
```

## Related documents

- [How the two differ](../../docs/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/product/GRAINMEND.md)
- [Product architecture](../../docs/architecture/PRODUCT_ARCHITECTURE.md)
