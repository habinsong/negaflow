# How the macOS and Windows versions differ

[Docs home](../README.md)

negaflow exists twice, once for macOS and once for Windows. The two share no source
code, and each is written the way its own system does things.

This page covers what that means in practice: what is identical, what looks different,
and what only one side can do.

## Why two

A single cross-platform codebase would have meant picking one toolkit and accepting the
result on both systems. Menus in the wrong place, file dialogs that behave oddly, color
that goes through one more translation layer, and a window that never quite matches the
rest of the system.

Writing each side for its own platform costs roughly twice the work, and every feature has
to be built and tested twice. The trade is that both versions behave the way people expect
on the system they are using.

## What is identical

The picture. Feed the same scan to both and you get the same result.

That is not a promise on paper. The macOS build renders a set of reference images, and
those files live in the repository under `docs/verification/macos-golden`. The Windows
engine tests read them back and compare pixel values. If a change to the Windows engine
drifts away from the macOS result, the tests fail.

The same goes for:

- Film base measurement and inversion
- All develop targets: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`
- Tone, curves, HSL, color grading, black-and-white toning
- GrainMend detection and repair, including the infrared path
- Print layouts and page geometry
- Export file naming, EXIF writing, and metadata policy
- The catalog format, so a library made on one system reads on the other

## What differs

### Color management

macOS uses ColorSync. Windows uses ICM. Both take the same ICC profiles and produce the
same numbers within rounding. The parity tests cover this, since it is the part most
likely to drift quietly.

### Graphics

macOS runs the develop chain on Core Image. Windows runs it on Direct3D compute shaders
with a CPU fallback for machines where the GPU path is unavailable.

Speed depends on the machine rather than the platform. An Apple Silicon Mac and a PC with
a discrete GPU both handle a 35mm scan without waiting.

### Where files live

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Library and settings | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| Logs | Console and the app support folder | `%LOCALAPPDATA%\Negaflow\Logs` |

### Install and removal

macOS ships a PKG that puts the app in `/Applications`. Removing it means dragging the app
to the Trash, the way any Mac app works.

Windows ships an installer that writes into your user folder without asking for
administrator rights. Removal goes through `Uninstall negaflow` in the Start menu or
through Settings, and takes out the app folder, the Start menu entry, and the package
registration.

### Command line

macOS ships `negaflow`, a full CLI that can detect scanners, develop files, run GrainMend,
and benchmark. It is meant to be used.

Windows ships `negaflow-cli.exe`, which is a smaller tool for checking what the engine does
with one file. It takes flags rather than subcommands and exists for diagnosis, not for
daily work.

### Signing

Neither build is signed by a paid developer certificate, so both systems warn on first
launch. macOS needs Open Anyway in Privacy and Security. Windows needs More info, then Run
anyway, past SmartScreen.

## Scanners

The scanner plugin is a separate GPL project,
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), and it also
exists for both systems. The plugin runs as its own process and talks over JSON, so
negaflow itself contains no SANE code on either platform.

On Windows the plugin goes through the scanner driver path Windows already provides.
Nothing gets replaced, so VueScan and SilverFast keep working on the same machine.

## Keeping them matched

Every feature lands on macOS first, then on Windows against the macOS behavior rather than
against a written spec. Where output can be measured, the macOS reference images decide
whether the Windows side is correct.

When the two disagree, macOS is the answer and the Windows side is the bug.
