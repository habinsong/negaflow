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
- Export file naming, EXIF writing and metadata policy
- The catalog format (`library.sqlite`)

## What differs

### Color management

macOS uses ColorSync and Windows uses ICM. Both take the same ICC profiles and give the same numbers within rounding. The parity tests cover this because it is the part most likely to drift quietly.

### Graphics

macOS runs the develop chain on Core Image. Windows runs it on Direct3D compute shaders, with a CPU fallback where the GPU path is unavailable.

### Where files live

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Library and settings | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |

### Install and removal

macOS ships a PKG that puts the app in `/Applications`. To remove it, drag the app to the Trash. Windows ships an installer that writes into your user folder without administrator rights. Removal goes through `Uninstall negaflow` in the Start menu or through Settings, and takes out the app folder, the Start menu entry and the package registration.

### Command line

macOS ships `negaflow`, a full CLI that detects scanners, develops files, runs GrainMend and benchmarks. Windows ships `negaflow-cli.exe`, a smaller diagnostic tool that checks what the engine does with one file. It takes flags, not subcommands.

### Signing

Neither build is signed with a paid developer certificate, so both systems warn on first launch. The Mac build is signed ad hoc and not notarized: allow it with Open Anyway in Privacy & Security. The Windows installer is unsigned: click More info in SmartScreen, then run it.

## Scanners

The scanner plugin is a separate GPL project, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), and it exists for both systems. It runs as its own process and talks JSON, so negaflow contains no SANE code on either platform. On Windows it goes through the scanner driver path Windows already provides, so VueScan and SilverFast keep working on the same machine.

## Keeping them matched

Each feature lands on macOS first and then on Windows against the actual macOS behavior. Where output can be measured, the macOS reference images decide whether Windows is correct. When the two disagree, macOS is the answer and the Windows side has the bug.
