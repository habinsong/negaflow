# How the macOS and Windows versions differ

[Docs home](../README.md)

negaflow exists twice, once for macOS and once for Windows. The two share no source code, and each is written the way its own system does things.

## Why two builds

One cross-platform codebase would mean one toolkit and its compromises on both systems: menus and file dialogs that behave oddly, an extra color translation layer, windows that do not match the system. Writing each side natively roughly doubles the work, since every feature is built and tested twice. In return each version behaves the way people expect on their system.

## What is identical

The picture. The same scan gives the same result on both.

The macOS build renders a set of reference images in `docs/verification/macos-golden`. Git ignores that folder, so the images exist only where they were rendered. The Windows engine tests read copies and compare pixel values, so a drift in the Windows engine fails the tests.

The same holds for:

- Film base measurement and inversion
- All develop targets: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`, `CS`
- Tone, curves, HSL, color grading, black-and-white toning
- GrainMend detection and repair, including the infrared path
- Print layouts and page geometry
- Export file naming across formats, and EXIF/metadata policy on JPEG, TIFF, and DNG (on Windows, PNG export carries DPI and ICC profile without EXIF metadata)
- The catalog format (`library.sqlite`)

## What differs

### Color management

macOS uses ColorSync and Windows uses ICM. Both take the same ICC profiles and give the same numbers within rounding. The parity tests cover this because it is the part most likely to drift quietly.

On screen, macOS draws through the display's ColorSync profile. Windows does that only when Advanced Color is on. With it off, Windows sends application pixels to the display as sRGB, so negaflow applies the monitor's ICC profile through a 33³ LUT to both the develop canvas and the print preview (including small contact-sheet tiles) just before drawing, and refreshes it automatically when switching monitors or returning to the window after changing display settings. Thumbnails and the rest of the interface are drawn as sRGB.

### Graphics

macOS runs the develop chain on Core Image in 16-bit half-float linear precision (`RGBAh`) by default. Windows runs it on Direct3D 11 compute shaders, with a CPU fallback where the GPU path is unavailable, and uses 32-bit float precision (`RGBA32F`) on both paths.

### Where files live

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Catalog, defect sidecars, recipes, print templates | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| App preferences | `UserDefaults` (`~/Library/Preferences/com.songhabin.negaflow.plist`) | `%LOCALAPPDATA%\Negaflow` |

### Install and removal

macOS ships a PKG that puts the app in `/Applications`. To remove it, drag the app to the Trash. Windows ships an installer that writes into `%LOCALAPPDATA%\Negaflow\App` and asks for a one-time administrator confirmation only if Windows does not already allow registering unsigned loose application packages (`AllowDevelopmentWithoutDevLicense`). Removal goes through `Uninstall negaflow` in the Start menu or through Settings, and takes out the app folder, the Start menu entry and the package registration.

### Command line

The GUI release installers do not ship a command-line binary; each platform's source build provides its own CLI. Building macOS from source with `swift build` produces `negaflow`, a CLI that detects scanners, develops files, runs GrainMend and benchmarks. Building Windows from source with CMake produces `negaflow-cli.exe`, a smaller diagnostic tool that checks what the engine does with one file and takes flags rather than subcommands.

### Signing

Neither build is signed with a paid developer certificate, so both systems warn on first launch. The Mac build is signed ad hoc and not notarized: allow it with Open Anyway in Privacy & Security. The Windows installer is unsigned: click More info in SmartScreen, then run it.

## Scanners

The scanner plugin is a separate GPL project, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), and it exists for both systems. It runs as its own process and talks JSON, so negaflow contains no SANE code on either platform. On Windows it goes through the scanner driver path Windows already provides, so VueScan and SilverFast keep working on the same machine.

## Keeping them matched

Each feature lands on macOS first and then on Windows against the actual macOS behavior. Where output can be measured, the macOS reference images decide whether Windows is correct. When the two disagree, macOS is the answer and the Windows side has the bug.
