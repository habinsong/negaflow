# Scanner Backend Strategy

negaflow is image-import first. Scanner support is optional and is loaded through external scanner plugins.

## Current Roles

| Component | Role |
| --- | --- |
| Image import | Primary entry point. RAW/DNG/TIFF/PNG/JPEG files can be brought directly into the same develop pipeline. |
| External scanner plugins | Optional hardware bridge. Plugins run out of process and communicate with negaflow through JSON. |
| Mock scanner backend | Development and demo path when no hardware plugin is installed. |
| ImageCaptureCore bridge | Inactive compatibility bridge. Kept for a future scanner that is exposed through macOS Image Capture. |

The main negaflow repository does not contain a SANE scanner backend. SANE support lives in the GPL plugin project:

- `https://github.com/habinsong/negaflow-scanner-sane`

## Architecture

```text
UI
  -> ScannerKit
       -> ExternalScannerBackend  -> installed plugin process
       -> MockScannerBackend      -> synthetic frames
       -> InactiveImageCaptureBackend
```

The UI talks only to `ScannerBackend`. A detected hardware scanner is exposed by an installed plugin as a `plugin:<pluginId>:<deviceId>` scanner id. Before invoking the plugin, negaflow removes the `plugin:<pluginId>:` prefix and passes the plugin's own device id back to that executable.

## Plugin Discovery

Plugins are discovered from:

```text
~/Library/Application Support/negaflow/Plugins/<id>/manifest.json
```

For tests and local development, `NEGAFLOW_PLUGINS_DIR` can point to another plugin directory.

Each plugin manifest declares:

- `schemaVersion`
- `id`
- `name`
- `kind`
- `license`
- `homepage`
- `executable`

Only executable scanner plugins with a valid manifest are loaded.

## Plugin Protocol

negaflow starts the plugin executable as a separate process. The protocol is intentionally small:

| Command | Result |
| --- | --- |
| `detect` | JSON device list. |
| `capabilities <deviceId>` | JSON scanner capabilities. |
| `scan` | Options JSON on stdin, progress NDJSON on stdout, final result event. |

The process boundary is part of the licensing and stability design: negaflow stays Apache-2.0, while a SANE plugin can carry its own GPL license and dependencies.

## SANE Plugin Notes

The SANE plugin wraps `scanimage` and is maintained outside this repository. It is responsible for:

- detecting SANE devices from `scanimage -L`;
- reading real capabilities from `scanimage -A`;
- resolving changing USB device addresses before scan;
- selecting transparency/film/infrared options from device capability output;
- writing the scanned TIFF and reporting the result path to negaflow.

End users who want SANE scanning install the plugin separately. Users who only import existing image files do not need SANE or the plugin.

## Verification

The main app scanner host is covered by tests that exercise a fake external plugin end to end: discovery, device detection, capability mapping, scan progress, and scan result mapping.

The SANE implementation itself is verified in the plugin repository with its own SwiftPM test suite and release build.
