<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, built natively for Windows.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="version 1.2.6"></a>
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
- 8 GB of memory, 16 GB recommended for medium format

To build it:

- Visual Studio 2026 with the Desktop development with C++ workload (`.vsconfig` lists the components)
- Windows 11 SDK 10.0.26100 or later
- .NET 10 SDK (`global.json` pins 10.0.302)
- CMake 4.2 or later (the `Visual Studio 18 2026` generator needs it)
- Python 3, for the icon and resource scripts

The build also has Arm64 presets. Releases ship x64 only.

## Installing

Download `negaflow-1.2.6-win-x64.exe` from [Releases](https://github.com/habinsong/negaflow/releases) and run it. By default it installs into `%LOCALAPPDATA%\Negaflow\App` and asks for no administrator rights.

[negaflow-1.2.6-win-x64-setup.zip](https://github.com/habinsong/negaflow/releases/download/v1.2.6/negaflow-1.2.6-win-x64-setup.zip) holds the same installer EXE with installation instructions, notices and SHA-256 checksums. Extract all files before running the installer. It is an installer archive, not a portable app.

The installer is unsigned. SmartScreen warns once on the first run: click More info, then run it.

To uninstall, use `Uninstall negaflow` in the Start menu or the app list in Settings. Your library and photos are left alone.

At launch the app asks GitHub once for the latest release. If a newer version is out, the bottom of the ⋯ menu at the top right reads "Update to Version X.Y.Z". Choosing it opens the release page and saves the `win-x64.exe` installer to Downloads, checked against the release's `SHA256SUMS.txt`. You install it yourself. When the app is current the item reads "You're on the latest version." and opens the project page. If the check fails, for example offline, the item does not appear.

## Building

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Build the C++ engine
.\scripts\build.ps1 -Preset x64-release

# Build the app and launch it
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` accepts `x64-debug`, `x64-release`, `arm64-debug` and `arm64-release`.

During development, launch the app with `run-app.ps1` only. The app builds as an MSIX package, so running the exe in the build folder does nothing. The script builds the package, registers it for the current user and starts it by app ID.

To build the installer:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

The output goes to `out\release\win-x64`.

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

Run `scripts\verify-installer.ps1` (also called by `local-ci.ps1`) in a signed-in desktop session. In an SSH session, AppX registration can fail with `0x80070005`, so the script stops before it touches the existing installation.

CI runs only the self-contained engine tests. The macOS reference files stay outside Git. To run those comparisons, set `NEGAFLOW_MACOS_GOLDEN_ROOT` to the reference directory when configuring CMake. It must contain `task6-metadata-policy`, `task9-bw-slide`, `task7-coreimage-filters`, `task8-digital-film-look` and `vibrance`. A missing or unreadable file fails the selected comparisons. `ctest --preset x64-release -L external-golden` runs them, and the ordinary unit tests stay enabled.

## Custom color targets

CS follows MAIN, HS, SP, F135 and HR in the target capsules. Selecting it opens a two-column list of 18 Custom targets at the lower left, in groups of 11, 4 and 3; the Look selector stays on the right. Entering CS selects Emulsion, and a photo that already uses a Custom target keeps it.

Custom uses the same custom-3 coefficients and string IDs as macOS. The chosen target is stored in the photo settings and the catalog, and preview and export run the same stage. A folder header applies the chosen target to the folder with the existing Apply button.

## Checking the engine from the command line

`negaflow-cli.exe` runs the engine on a single file. It takes flags, not subcommands.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Build information
& $cli --build-info

# What a scan file contains
& $cli --probe-tiff scan.tif

# Develop and save as 16-bit TIFF
& $cli --export-developed-tiff16 scan.tif out.tif

# Where the time goes in one develop pass
& $cli --develop-timing scan.tif

# Automatic film base and what it picked
& $cli --auto-base-probe scan.tif
```

Run it with no arguments for the full list.

## Scanners

Scanner controls stay hidden until a plugin is installed. SANE devices use [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), installed separately.

The plugin reaches the scanner through the driver paths Windows already provides, so VueScan or SilverFast can stay installed on the same machine.

## When something goes wrong

The app writes text logs to `%LOCALAPPDATA%\Negaflow\Logs`.

| File | What it records |
|---|---|
| `export-trace.txt` | Export and quick export, including failures |
| `termination.txt` | What happened while the app was closing |
| `settings-change.txt` | Settings that changed and what changed them |

These three are always on. Two more are off by default:

- `preview-trace.txt`: create an empty file named `preview-trace.on` in the same folder.
- `stage-trace.txt`: set the environment variable `NEGAFLOW_STAGE_TRACE=1` before launching the app. It records pixel statistics at each develop stage.

## Layout

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, decoding and export (C++)
│   ├── Interop/       The layer between engine and app (C#)
│   ├── Catalog.Core/  Library storage (C#)
│   ├── Shell.Core/    Develop, print and export logic (C#)
│   ├── Shell/         Library, develop and print screens (WinUI 3)
│   └── Cli/           Engine inspection tool (C++)
├── scripts/           Build, test and packaging scripts
├── tests/             Engine, app and boundary tests
└── Installer/windows/ NSIS installer
```

## Related documents

- [How the two differ](../../docs/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/product/GRAINMEND.md)
- [Product architecture](../../docs/architecture/PRODUCT_ARCHITECTURE.md)
