# Scanner plugin architecture

[Docs home](../README.md)

The default input for negaflow is importing images. A real scanner is connected only when an external plugin is present.

> [!IMPORTANT]
> The app does not guess capabilities from a scanner model name. Only what the plugin reports goes into the screen and the requests, and the demo device appears only when you pick demo mode yourself.

## Parts

| Part | Role |
|---|---|
| Image import | Sends RAW, DNG, TIFF, PNG and JPEG into the develop path. |
| External plugin | Runs as its own process, drives the real device and talks JSON. |
| Demo scanner | Provides `negaflow Scanner` and `negaflow Flatbed Scanner` for development. You have to select demo to use it. |
| ImageCaptureCore link | Inactive compatibility code for macOS Image Capture devices. |

There is no SANE implementation in this repository. That code lives in a separate GPL project:

- <https://github.com/habinsong/negaflow-scanner-sane>

## How it connects

On macOS, the screen talks to `ScannerKit`, which routes to one of three `ScannerBackend` implementations:

1. `ExternalScannerBackend`, which runs the installed external plugin.
2. `MockScannerBackend`, which makes synthetic images for development.
3. `InactiveImageCaptureBackend`, which is inactive for now.

On Windows, the shell routes to `ScannerPluginGateway` for external plugins or `SimulatedScannerGateway` when demo mode is selected.

A plugin device ID appears in the app as `plugin:<pluginId>:<deviceId>`.

When the plugin runs, `plugin:<pluginId>:` is stripped and only the plugin's own device ID is sent.

## Finding plugins

The default manifest path is `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json` on macOS and `%LOCALAPPDATA%\Negaflow\Plugins\<id>\manifest.json` on Windows. On macOS, `NEGAFLOW_PLUGINS_DIR` can point at another folder for tests and local development.

| Field | Rule |
|---|---|
| `schemaVersion` | Exactly `1` today |
| `protocolVersion` | `1` if omitted (`1` and `2` supported; Windows requires `2` when scanning) |
| `id` | Unique plugin ID |
| `name` | Name shown on screen |
| `pluginVersion` | Optional plugin version string |
| `kind` | Defaults to `"scanner"` if omitted; other values are refused |
| `license` | Distribution license |
| `homepage` | Project address |
| `executable` | Relative path inside the plugin directory (no `.`, `..`, leading `/`, symlinks or reparse points) |

`id` is 1 to 64 ASCII characters. The first is a letter or digit and the rest are letters, digits, `.`, `_` or `-`. `:` is the device ID separator, so it is not allowed.

A plugin opens only when the manifest and the executable both check out. Older or future schemas and unknown protocols are not read by guesswork.

### File safety checks

> [!WARNING]
> If the bytes of the manifest or the executable change, the earlier approval is discarded. File safety and SHA-256 hashes are checked again right before running.

- On macOS, the plugin folder, manifest and executable must be owned by the current user, group or other write permissions are refused, and symlinks are refused.
- On Windows, reparse points are refused on the plugin folder, manifest and executable, and the executable path must stay inside the plugin directory.
- The SHA-256 of the manifest and the executable is recorded on both platforms.
- The user approves it the first time it is used.
- Changed file bytes void the approval.
- The hashes and IDs are recomputed right before running.

## Commands

The plugin runs as its own process.

| Command | Result |
|---|---|
| `detect` | JSON device list |
| `capabilities <deviceId>` | JSON capability list. Can take the device ID, vendor and model JSON reported by `detect` on stdin |
| `scan` (macOS) / `scan <deviceId>` (Windows) | Settings JSON on stdin; progress NDJSON and a final result on stdout |

## Scan protocol

### Version 1

The older compatibility spec. Requests and NDJSON have no `protocolVersion`, `requestID` or `sequence`. It cannot report the settings that were actually applied, so the result is recorded as `.unknownLegacy(protocolVersion: 1)`. Request values are not copied over as if they had been verified.

### Version 2

Used only when the manifest carries `"protocolVersion": 2`. Windows requires protocol v2 when running a scan.

A request contains:

- `protocolVersion: 2`
- A `requestID` UUID created by the app

A `capabilities` response may return the optional field `capabilityToken`. The app does not interpret it. It passes the value through to the next v2 `scan` request for the same device, and nowhere else. It is left out of v1 requests, and tokens are never mixed between devices. The plugin has to check the token's format and validity itself.

To stop a wrong reconnection to another model on the same backend, the app passes the `deviceID`, `vendor` and `model` from the last `detect` back in as optional stdin JSON for `capabilities`. Existing plugins can ignore this input. A plugin whose device address can change should tie that identity into the capability snapshot and check it again on the next `scan`.

Every NDJSON event repeats the same version and request ID, and carries a `sequence` of zero or more that is larger than the one before. Only `progress`, `result` and `error` are allowed. `result` and `error` are final events, and anything after them fails. A scan that did not end in an error has exactly one `result`.

All of these fail closed:

- An event that cannot be read
- A missing or different version or request ID
- A repeated or out-of-order sequence
- An unknown event
- A duplicate result
- Extra output after the final event
- Invalid UTF-8

On macOS, a mid-stream v2 spec violation ends the plugin immediately instead of waiting for the usual time limit. On Windows, the v2 event stream is validated after the process exits.

### Settings that were actually applied

A v2 `result` must carry `appliedOptions`:

- `deviceID`, `resolutionDPI`, `bitDepth`, `colorMode`, `filmType`
- `scanArea`: `originXMM`, `originYMM`, `widthMM`, `heightMM`, the area the plugin actually sent to the backend. `originXMM`, `originYMM` and `widthMM` must match the request, and only `heightMM` may differ by less than 1 mm to work around a backend that miscomputes the scan height. The app checks the returned pixel size against this area, so copying the request would defeat the check.
- `infrared`, `multiExposure`
- `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`
- `outputRawTIFF`

The last three adjustments need their keys present even when the value is `null`.

`resolutionDPI: 0` means preview. A preview that is not 0, or a full scan that is 0, is refused. Unknown values, a different device, and a resolution, bit depth or IR state that disagrees between the result header and `appliedOptions` are refused as well.

Once the checks pass, the app records its own scanner ID and request ID instead of the plugin ID, and keeps the final output path. Only then is the result marked `.verified(options)`.

In v1, `ScanResult.resolution` and `bitDepth` may fall back to the requested values. The fields that show the origin, `reportedResolution` and `reportedBitDepth`, take only correct values the result reported itself.

## Positioned flatbed scan area

The preview for this workflow asks for an explicit resolution, the closest supported value to 300 dpi, instead of leaving it to the device. A device default can be as low as 25 dpi, which is far too coarse to place frames on or to detect them. A preview that carries a resolution is an ordinary scan, so it does not use the plugin's preview path.

A flatbed scan with a chosen position turns on only when the plugin reports all of these:

- Preview
- `supportsScanArea: true` and `supportsPositionedScanArea: true`
- Physical scan area units (`scanAreaUnit != "pixel"`)
- `scanOriginXRange` and `scanOriginYRange` in mm with non-negative origins and valid bounds
- `scanWidthRange` and `scanHeightRange` in mm with positive minimum and maximum bounds

The app expands the chosen area outward to the plugin's step size and makes one full scan job per area. It never guesses this from a model name. Older plugins without the optional fields keep the fixed frame flow.

## Process limits and cancellation

- macOS caps: stdout 4 MiB, stderr 1 MiB; timeouts are 90 s for `detect`, 180 s for `capabilities` and 2 hours for `scan`, with immediate termination on a mid-stream v2 spec violation.
- Windows caps: stdout 4 MiB for `detect` and `capabilities`, 8 MiB for `scan` (256 KiB per stdout line), stderr 512 KiB; timeouts are 15 s for `detect`, 180 s for `capabilities` and 2 hours for `scan`, with v2 stream validation after process exit.

Going over the cap ends the process and fails. During cleanup, only the bytes that already arrived are read. Even if a child process inherited the pipe, nothing waits for EOF.

`cancelScan()` returns after the plugin has ended, the pipe handlers are closed and the slot for the next job is free.

## Publishing the scan file

The plugin writes the source image to exactly the `outputPath` the app gave it, and returns that path in the result's `path` field. That path is a temporary location on the same disk as the final folder. The flow:

1. The app sends the settings JSON and `outputPath` to the plugin.
2. The plugin writes the scan file to the temporary folder.
3. The plugin returns a result whose `path` matches the requested `outputPath`.
4. The app checks format, size and path.
5. If the checks pass, the app publishes the file atomically to the final scan folder. On cancel, failure or wrong output, it deletes the temporary material.

The app confirms:

- A regular file that is not empty
- An image that ImageIO can decode on macOS (enforcing TIFF in v2), or a TIFF whose metadata passes `NativeTiffSourceProbe` on Windows
- The expected format and pixel size
- The same path in the request's `outputPath` and the result's `path`

On cancel, timeout, wrong output or plugin failure, the temporary folder is deleted and no partial scan is published.

A v2 IR file also has to sit inside the temporary folder the app gave. File type, readability and pixel size are checked. v1 can take an external IR path, for compatibility with plugins already in the field.

## The SANE boundary

The SANE implementation, its dependencies, configuration, device-specific processing, tests and release documentation all live in the separate [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) repository.

That project publishes a standard macOS 14+ installer using Homebrew's stock SANE and a separate macOS 26+ Coolscan installer that builds official SANE 1.4.0 with the minimal upstream `coolscan2`/`coolscan3` allocation fix. The standard path does not proactively block Coolscan, but it does not contain that fix.

This repository documents and checks the device-independent external process spec only. Anyone who just imports image files does not need a scanner plugin.

The negaflow app does not link the SANE implementation or put it in the app distribution. The plugin has its own repository, executable, source distribution and GPL license. This document records the structure and does not settle whether something is a derivative work. Before an actual release, the files in both artifacts and the communication contract are checked again.

## Checks

The app tests run a fake external plugin as a real process and confirm:

- Finding plugins
- Finding devices
- Capability wiring
- Progress events
- The final result
- Cleanup after cancel and failure

The SANE implementation is checked separately, in the plugin repository's SwiftPM tests and Release build.
