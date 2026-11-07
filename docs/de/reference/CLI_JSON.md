# Scanner-CLI-JSON

[Dokumentationsstart](../README.md)

Skripte und andere Apps lesen Scannerinformationen aus diesem JSON. Die CLI serialisiert nur die Geräteinformationen und Fähigkeiten, die `ScannerKit` erhalten hat.

| Element | Vertrag |
|---|---|
| Befehle | `detect --json`, `capabilities <scannerID> --json` |
| stdout | Ein JSON-Dokument und ein abschließender Zeilenumbruch |
| stderr | Diagnoseprotokoll |
| Schema | `negaflow.scanner-cli`, Version `1` |

## Befehle

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

`--json` funktioniert nur bei diesen beiden lesenden Befehlen. Bei `scan` oder `develop` endet es mit dem Fehler `unsupported_json_command`.

## Gemeinsame Form

Erfolg wie Fehler schreiben ein JSON-Dokument nach stdout.

<details>
<summary>Beispiel einer erfolgreichen Antwort</summary>

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

Bei einem Fehler ist `status` gleich `error` und `payload` gleich `null`. `error` enthält einen stabilen maschinenlesbaren Code und eine Beschreibung. Protokolle und Fortschritt gehen nur nach stderr.

## Fähigkeiten

Der `payload` von `capabilities` enthält immer alle diese Felder:

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

Ein Wert, den das Gerät nicht gemeldet hat, wird nicht geraten. Er wird zu `null`, einem leeren Array, `false` oder den `disabledReasons` des Plug-ins.

`estimatedScanSpeeds` ist ein Array dieses Objekts, aufsteigend nach DPI sortiert:

```json
{ "dpi": 3600, "seconds": 42.0 }
```

App und CLI lesen dieselben `ScannerCapabilities`. Eine Konsistenzprüfung stellt sicher, dass die Bedienelemente auf dem Bildschirm den JSON-Feldern folgen.

## Versionsregeln

- Bedeutung und Typ eines vorhandenen Feldes ändern sich nicht.
- Ein neues optionales Feld kommt nur hinzu, wenn ältere Programme es ignorieren können.
- Entfernen, Umbenennen oder Typwechsel eines Feldes erhöht `schemaVersion`.
- Auflösungen, Modi und Bittiefen behalten die Reihenfolge des Plug-ins. Nur die geschätzten Geschwindigkeiten werden sortiert.
