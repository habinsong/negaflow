# Scanner CLI JSON

[Docs home](../README.md)

Scripts and other apps read scanner information from this JSON. The CLI only serializes the device information and capabilities that `ScannerKit` received.

| Item | Contract |
|---|---|
| Commands | `detect --json`, `capabilities <scannerID> --json` |
| stdout | One JSON document and a final newline |
| stderr | Diagnostic log |
| Schema | `negaflow.scanner-cli`, version `1` |

## Commands

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json` works only on these two read-only commands. On `scan` or `develop` it ends with an `unsupported_json_command` error.

## Common shape

Success and failure each write one JSON document to stdout.

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

On failure `status` is `error` and `payload` is `null`. `error` holds a stable machine-readable code and a description. Logs and progress go to stderr only.

## Capability information

The `capabilities` payload always has these fields:

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

A value the device did not report is not guessed. It becomes `null`, an empty array, `false`, or the plugin's `disabledReasons`.

`estimatedScanSpeeds` is an array of this object, sorted by ascending DPI:

```json
{ "dpi": 3600, "seconds": 42.0 }
```

The app and the CLI read the same `ScannerCapabilities`. A consistency check confirms that the controls on screen follow the JSON fields.

## Version rules

- The meaning and type of an existing field do not change.
- A new optional field is added only when older programs can ignore it.
- Removing, renaming or retyping a field raises `schemaVersion`.
- Resolutions, modes and bit depths keep the plugin's order. Only the estimated speeds are sorted.
