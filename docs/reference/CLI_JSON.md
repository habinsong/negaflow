# Scanner CLI JSON

[Docs home](../README.md)

This is the shape a script or another app reads scanner information from.
It stays separate from the scanner implementation.
The CLI only turns the device information and capabilities that `ScannerKit` received into JSON.

| Item | Contract |
|---|---|
| Supported commands | `detect --json`, `capabilities <scannerID> --json` |
| stdout | One JSON document and a final newline |
| stderr | Diagnostic log |
| Current schema | `negaflow.scanner-cli`, version `1` |

## Commands

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

For now `--json` works only on those two read-only commands.
Put it on `scan` or `develop`, which change files or report progress, and it ends with an
`unsupported_json_command` error.

## Common shape

Success and failure both write one JSON document to stdout, with a newline at the end.

<details>
<summary>Example of a success response</summary>

```json
{
  "schema": "negaflow.scanner-cli",
  "schemaVersion": 1,
  "command": "capabilities",
  "status": "ok",
  "payload": {},
  "error": null
}
```

</details>

On failure `status` is `error` and `payload` is `null`.
`error` carries a machine code that does not change and a description for people.
Diagnostic logs go to stderr. Logs and progress never get mixed into stdout.

## Capability information

The `payload` of `capabilities` always carries all of these fields.

- `resolutionsDPI`, `modes`, `bitDepths`
- `sourceModes`, `transparencyModes`
- `supportsPreview`, `supportsTransparency`, `supportsInfrared`
- `supportsMultiExposure`, `supportsScanArea`, `supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`, `contrastRange`, `hardwareExposureRange`
- `scanOriginXRange`, `scanOriginYRange`, `scanWidthRange`, `scanHeightRange`
- `disabledReasons`
- `minScanArea`, `maxScanArea`, `scanAreaUnit`
- `outputFormats`, `estimatedScanSpeeds`

Values the device did not report are not guessed.
Depending on the value it uses `null`, an empty array, `false`, or the `disabledReasons` the plugin
sent.

`estimatedScanSpeeds` is an array of this object, sorted by ascending DPI.

```json
{ "dpi": 3600, "seconds": 42.0 }
```

The app screen and the CLI read the same `ScannerCapabilities`.
The consistency check confirms that the controls opened on screen follow the same values as the JSON
fields.

## Version rules

- The meaning and type of an existing field do not change.
- A new optional field goes in only when older programs can ignore fields they do not know.
- Removing a field, renaming it, or changing its type raises `schemaVersion`.
- Resolutions, modes, and bit depths keep the plugin's order.
- Only the estimated speeds are sorted by DPI.
